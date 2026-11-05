import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'safe_archive_path.dart';

/// Handles packing and unpacking of a single ZIP archive containing
/// the database, identity file, and attachments.
class UnifiedBackupManager {
  const UnifiedBackupManager({
    Future<Directory> Function()? temporaryDirectoryProvider,
  }) : _temporaryDirectoryProvider = temporaryDirectoryProvider;

  final Future<Directory> Function()? _temporaryDirectoryProvider;

  static const String dbEntryName = 'qayd_finance.db';
  static const String identityEntryName = 'qayd_identity.dat';
  static const String attachmentsEntryName = 'qayd_attachments.zip';

  Future<Directory> _temporaryDirectory() =>
      _temporaryDirectoryProvider?.call() ?? getTemporaryDirectory();

  /// Creates a single ZIP archive containing the provided files.
  Future<File> createArchive({
    required File dbFile,
    File? identityFile,
    File? attachmentsZip,
  }) async {
    final archive = Archive();

    // 1. Add Database
    final dbBytes = await dbFile.readAsBytes();
    archive.addFile(ArchiveFile.bytes(dbEntryName, dbBytes));

    // 2. Add Identity (if exists)
    if (identityFile != null && identityFile.existsSync()) {
      final idBytes = await identityFile.readAsBytes();
      archive.addFile(ArchiveFile.bytes(identityEntryName, idBytes));
    }

    // 3. Add Attachments ZIP (if exists)
    if (attachmentsZip != null && attachmentsZip.existsSync()) {
      final zipBytes = await attachmentsZip.readAsBytes();
      archive.addFile(ArchiveFile.bytes(attachmentsEntryName, zipBytes));
    }

    final zipData = ZipEncoder().encodeBytes(archive);
    final tmpDir = await _temporaryDirectory();
    final outputPath = p.join(
      tmpDir.path,
      'qayd_unified_backup_${DateTime.now().microsecondsSinceEpoch}.qback',
    );
    final outputFile = File(outputPath);
    await outputFile.writeAsBytes(zipData, flush: true);
    return outputFile;
  }

  /// Extracts the archive to a temporary directory and returns paths to components.
  ///
  /// Every regular-file entry is validated before any contents are written;
  /// absolute names and traversal paths are rejected so a crafted backup cannot
  /// write outside the temporary restore directory.
  Future<UnpackedBackup> unpack(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    final tmpDir = await _temporaryDirectory();
    final extractDir = await tmpDir.createTemp('qayd_extract_');

    try {
      for (final entry in archive) {
        if (entry.isSymbolicLink) {
          throw const FormatException(
            'Symbolic links are not supported in backup archives.',
          );
        }
        if (!entry.isFile) continue;
        if (safeArchiveDestination(extractDir.path, entry.name) == null) {
          throw const FormatException('Unsafe path in backup archive.');
        }
      }

      String? dbPath;
      String? identityPath;
      String? attachmentsPath;

      for (final entry in archive) {
        if (!entry.isFile) continue;

        final outPath = safeArchiveDestination(extractDir.path, entry.name)!;
        final data = entry.readBytes();
        if (data == null) {
          throw const FormatException('Backup archive entry has no data.');
        }
        final outFile = File(outPath);
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data, flush: true);

        final normalizedName = p.posix.normalize(
          entry.name.replaceAll(r'\', '/'),
        );
        if (normalizedName == dbEntryName) {
          dbPath = outPath;
        } else if (normalizedName == identityEntryName) {
          identityPath = outPath;
        } else if (normalizedName == attachmentsEntryName) {
          attachmentsPath = outPath;
        }
      }

      return UnpackedBackup(
        databasePath: dbPath,
        identityPath: identityPath,
        attachmentsZipPath: attachmentsPath,
        tempDirectory: extractDir.path,
      );
    } catch (_) {
      if (extractDir.existsSync()) await extractDir.delete(recursive: true);
      rethrow;
    }
  }

  /// Checks if a file is likely a unified ZIP archive.
  bool isZipArchive(String path) {
    return path.toLowerCase().endsWith('.zip') ||
        path.toLowerCase().endsWith('.qback');
  }
}

class UnpackedBackup {
  final String? databasePath;
  final String? identityPath;
  final String? attachmentsZipPath;
  final String tempDirectory;

  UnpackedBackup({
    this.databasePath,
    this.identityPath,
    this.attachmentsZipPath,
    required this.tempDirectory,
  });

  Future<void> dispose() async {
    try {
      final dir = Directory(tempDirectory);
      if (dir.existsSync()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {}
  }
}
