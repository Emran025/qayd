import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:qayd/data/file_system/backup_file_manager.dart';
import 'safe_archive_path.dart';

/// Builds and restores a ZIP archive containing **all encrypted attachment
/// files** (voucher images, PDFs, collateral attachments, etc.).
///
/// ### ZIP internal structure
/// Every source directory is identified by a stable **logical key** rather
/// than its absolute file-system path:
/// ```
/// attachments/          ← key for qayd_images/ (primary store)
///   img_abc_enc.jpg
///   subdir/img_xyz.png
/// ```
/// Separating the logical key from the absolute path means that on
/// restoration, every file lands directly inside the **active**
/// `externalImagesDir()` of the *current* device — even if the absolute path
/// differs (e.g. different package name, Android version, or new device).
///
/// The files are already AES-encrypted by [AttachmentStorageService] using
/// the same key as the database, so the ZIP requires no extra encryption.
///
/// Drive / backup file name: `qayd_attachments.zip`
final class AttachmentsZipBuilder {
  const AttachmentsZipBuilder({
    BackupFileManager fileManager = const BackupFileManager(),
    this.imagesDirectoryProvider,
    this.applicationDocumentsDirectoryProvider,
  }) : _fileManager = fileManager;

  final BackupFileManager _fileManager;
  final Future<Directory?> Function()? imagesDirectoryProvider;
  final Future<Directory> Function()? applicationDocumentsDirectoryProvider;

  /// File name used for Drive uploads and local backup copies.
  static const String zipFileName = 'qayd_attachments.zip';

  /// Stable logical key stored as the top-level directory inside the ZIP.
  /// Must never change so that older ZIPs remain restorable.
  static const String _attachmentsKey = 'attachments';

  // ── Build ──────────────────────────────────────────────────────────────────

  /// Creates a ZIP of all attachment files found in the known storage
  /// directories and writes it to [outputPath].
  ///
  /// Each entry's name inside the ZIP is:
  ///   `attachments/<path-relative-to-that-source-dir>`
  ///
  /// Returns the number of files added (0 if there are no attachments; the
  /// ZIP is still written as an empty archive so callers need no special-casing).
  Future<int> buildZip(String outputPath) async {
    final archive = Archive();
    int count = 0;

    for (final dir in await _sourceDirs()) {
      if (!dir.existsSync()) continue;

      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File) continue;

        final bytes = await entity.readAsBytes();

        // Path inside the ZIP: logicalKey/path-relative-to-source-dir
        // e.g.  attachments/img_abc_enc.jpg
        //       attachments/sub/img_xyz_enc.png
        final relInsideDir = p
            .relative(entity.path, from: dir.path)
            .replaceAll(r'\', '/');
        final entryName = '$_attachmentsKey/$relInsideDir';

        archive.addFile(ArchiveFile.bytes(entryName, bytes));
        count++;
      }
    }

    final zipData = ZipEncoder().encodeBytes(archive);
    await File(outputPath).writeAsBytes(zipData);
    return count;
  }

  /// Builds the ZIP into the system temp directory and returns the [File].
  Future<File> buildZipToTemp() async {
    final tmpDir = await getTemporaryDirectory();
    final outputPath = p.join(tmpDir.path, zipFileName);
    await buildZip(outputPath);
    return File(outputPath);
  }

  // ── Restore ────────────────────────────────────────────────────────────────

  /// Extracts the ZIP at [zipPath] and places every file **directly inside**
  /// the active source directory on the current device.
  ///
  /// Restoration mapping (logical key → live directory):
  ///   `attachments/*`  →  `externalImagesDir()`
  ///
  /// This guarantees that:
  /// - Files end up exactly where [AttachmentStorageService] expects them.
  /// - No path-remapping or `_resolvePath` fallback is needed after restore.
  /// - The app can open / decrypt attachments immediately without a restart.
  ///
  /// Any missing parent sub-directories inside the destination are created
  /// automatically. Returns the number of files restored.
  Future<int> restoreFromZip(String zipPath) async {
    final bytes = await File(zipPath).readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Resolve the active destination directory on THIS device right now.
    final activeDir =
        await (imagesDirectoryProvider?.call() ??
            _fileManager.externalImagesDir());
    if (activeDir == null) return 0;

    // Validate every recognized file path before writing anything. A malicious
    // `attachments/../../...` entry must not escape the active image directory.
    final attachments = <ArchiveFile>[];
    for (final entry in archive) {
      if (!entry.isFile) continue;
      final normalizedName = entry.name.replaceAll(r'\', '/');
      final relative = _stripPrefix(normalizedName);
      if (relative == null) continue;
      if (safeArchiveDestination(activeDir.path, relative) == null ||
          entry.readBytes() == null) {
        throw const FormatException(
          'Unsafe or unreadable attachment ZIP entry.',
        );
      }
      attachments.add(entry);
    }

    if (!activeDir.existsSync()) {
      await activeDir.create(recursive: true);
    }

    int count = 0;
    for (final entry in attachments) {
      // Strip the logical-key prefix.
      // "attachments/img_abc_enc.jpg"  →  "img_abc_enc.jpg"
      // "attachments/sub/img.png"      →  "sub/img.png"
      // "unknown_key/anything"         →  null  (skip)
      final normalizedName = entry.name.replaceAll(r'\', '/');
      final relative = _stripPrefix(normalizedName)!;

      // Build the absolute path inside the active directory.
      final destPath = safeArchiveDestination(activeDir.path, relative)!;

      final destFile = File(destPath);
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes(entry.readBytes()!, flush: true);
      count++;
    }
    return count;
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  /// Returns every directory from which attachments should be collected.
  ///
  /// The **primary** store is `externalImagesDir()`. The app-documents
  /// fallback (`qayd_images/`) is included only when it exists and differs
  /// from the primary path (iOS, desktop simulators, etc.).
  Future<List<Directory>> _sourceDirs() async {
    final dirs = <Directory>[];

    final externalDir =
        await (imagesDirectoryProvider?.call() ??
            _fileManager.externalImagesDir());
    if (externalDir != null) dirs.add(externalDir);

    final docsBase =
        await (applicationDocumentsDirectoryProvider?.call() ??
            getApplicationDocumentsDirectory());
    final docsImages = Directory(p.join(docsBase.path, 'qayd_images'));
    if (docsImages.existsSync() &&
        (externalDir == null || docsImages.path != externalDir.path)) {
      dirs.add(docsImages);
    }

    return dirs;
  }

  /// Strips the `attachments/` prefix from [entryName] and returns the
  /// remainder, or `null` if the prefix is absent or the remainder is empty.
  String? _stripPrefix(String entryName) {
    const prefix = '$_attachmentsKey/';
    if (!entryName.startsWith(prefix)) return null;
    final rest = entryName.substring(prefix.length);
    return rest.isEmpty ? null : rest;
  }
}
