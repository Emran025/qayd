import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:qayd/data/backup/attachments_zip_builder.dart';
import 'package:qayd/data/backup/safe_archive_path.dart';
import 'package:qayd/data/backup/unified_backup_manager.dart';

void main() {
  group('UnifiedBackupManager ZIP compatibility', () {
    late Directory tempRoot;
    late UnifiedBackupManager manager;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp('qayd_backup_test_');
      manager = UnifiedBackupManager(
        temporaryDirectoryProvider: () async => tempRoot,
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
    });

    test('round-trips a new unified backup through archive 4', () async {
      final db = File(p.join(tempRoot.path, 'source.db'))
        ..writeAsStringSync('current encrypted database bytes');
      final identity = File(p.join(tempRoot.path, 'source.identity'))
        ..writeAsStringSync('current identity bytes');
      final attachments = File(p.join(tempRoot.path, 'source.zip'))
        ..writeAsStringSync('current attachment ZIP bytes');

      final archiveFile = await manager.createArchive(
        dbFile: db,
        identityFile: identity,
        attachmentsZip: attachments,
      );
      final unpacked = await manager.unpack(archiveFile.path);
      addTearDown(unpacked.dispose);

      expect(
        await File(unpacked.databasePath!).readAsString(),
        'current encrypted database bytes',
      );
      expect(
        await File(unpacked.identityPath!).readAsString(),
        'current identity bytes',
      );
      expect(
        await File(unpacked.attachmentsZipPath!).readAsString(),
        'current attachment ZIP bytes',
      );
    });

    test('opens a unified qback written by archive 3.6.1', () async {
      final legacy = File('test/fixtures/legacy_unified_backup.qback');
      final copiedLegacy = await legacy.copy(
        p.join(tempRoot.path, 'legacy.qback'),
      );

      final unpacked = await manager.unpack(copiedLegacy.path);
      addTearDown(unpacked.dispose);

      expect(
        await File(unpacked.databasePath!).readAsString(),
        'legacy encrypted database placeholder',
      );
      expect(
        await File(unpacked.identityPath!).readAsString(),
        'legacy identity seed placeholder',
      );
      expect(
        await File(unpacked.attachmentsZipPath!).readAsBytes(),
        await File('test/fixtures/legacy_attachments.zip').readAsBytes(),
      );
    });

    test('rejects traversal entries before extracting any file', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.bytes('../escaped.txt', utf8.encode('escape')));
      final zipPath = p.join(tempRoot.path, 'malicious.qback');
      await File(zipPath).writeAsBytes(ZipEncoder().encodeBytes(archive));

      await expectLater(
        manager.unpack(zipPath),
        throwsA(isA<FormatException>()),
      );
      expect(File(p.join(tempRoot.path, 'escaped.txt')).existsSync(), isFalse);
    });
  });

  group('AttachmentsZipBuilder compatibility', () {
    late Directory tempRoot;

    setUp(() async {
      tempRoot = await Directory.systemTemp.createTemp(
        'qayd_attachments_test_',
      );
    });

    tearDown(() async {
      if (tempRoot.existsSync()) await tempRoot.delete(recursive: true);
    });

    test(
      'builds the current stable attachments/ layout from all source dirs',
      () async {
        final primary = Directory(p.join(tempRoot.path, 'primary'));
        final documents = Directory(p.join(tempRoot.path, 'documents'));
        final docsImages = Directory(p.join(documents.path, 'qayd_images'));
        await Directory(p.join(primary.path, 'nested')).create(recursive: true);
        await docsImages.create(recursive: true);
        await File(
          p.join(primary.path, 'nested', 'invoice.bin'),
        ).writeAsString('primary payload');
        await File(
          p.join(docsImages.path, 'legacy-image.bin'),
        ).writeAsString('documents fallback payload');

        final builder = AttachmentsZipBuilder(
          imagesDirectoryProvider: () async => primary,
          applicationDocumentsDirectoryProvider: () async => documents,
        );
        final output = File(p.join(tempRoot.path, 'current_attachments.zip'));
        expect(await builder.buildZip(output.path), 2);

        final entries = ZipDecoder()
            .decodeBytes(await output.readAsBytes())
            .where((entry) => entry.isFile)
            .map((entry) => entry.name)
            .toSet();
        expect(entries, contains('attachments/nested/invoice.bin'));
        expect(entries, contains('attachments/legacy-image.bin'));

        final restoredDir = Directory(p.join(tempRoot.path, 'restored'));
        final restoreBuilder = AttachmentsZipBuilder(
          imagesDirectoryProvider: () async => restoredDir,
          applicationDocumentsDirectoryProvider: () async => documents,
        );
        expect(await restoreBuilder.restoreFromZip(output.path), 2);
        expect(
          await File(
            p.join(restoredDir.path, 'nested', 'invoice.bin'),
          ).readAsString(),
          'primary payload',
        );
        expect(
          await File(
            p.join(restoredDir.path, 'legacy-image.bin'),
          ).readAsString(),
          'documents fallback payload',
        );
      },
    );

    test(
      'restores an old archive 3.6.1 attachment ZIP and ignores unknown keys',
      () async {
        final activeDir = Directory(p.join(tempRoot.path, 'active'));
        final builder = AttachmentsZipBuilder(
          imagesDirectoryProvider: () async => activeDir,
          applicationDocumentsDirectoryProvider: () async => tempRoot,
        );

        final restored = await builder.restoreFromZip(
          'test/fixtures/legacy_attachments.zip',
        );
        expect(restored, 2);
        expect(
          await File(p.join(activeDir.path, 'receipt_old.jpg')).readAsString(),
          'legacy encrypted attachment one',
        );
        expect(
          await File(
            p.join(activeDir.path, 'legacy', 'صور', 'فاتورة.png'),
          ).readAsString(),
          'legacy encrypted attachment two',
        );
        expect(
          File(p.join(activeDir.path, 'ignore.txt')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'rejects traversal in attachments ZIP before writing safe entries',
      () async {
        final activeDir = Directory(p.join(tempRoot.path, 'active'));
        final malicious = Archive()
          ..addFile(
            ArchiveFile.bytes(
              'attachments/safe.txt',
              utf8.encode('should not be written'),
            ),
          )
          ..addFile(
            ArchiveFile.bytes(
              r'attachments\..\..\escaped.txt',
              utf8.encode('escape'),
            ),
          );
        final zipPath = p.join(tempRoot.path, 'malicious_attachments.zip');
        await File(zipPath).writeAsBytes(ZipEncoder().encodeBytes(malicious));

        final builder = AttachmentsZipBuilder(
          imagesDirectoryProvider: () async => activeDir,
          applicationDocumentsDirectoryProvider: () async => tempRoot,
        );
        await expectLater(
          builder.restoreFromZip(zipPath),
          throwsA(isA<FormatException>()),
        );
        expect(activeDir.existsSync(), isFalse);
        expect(
          File(p.join(tempRoot.path, 'escaped.txt')).existsSync(),
          isFalse,
        );
      },
    );
  });

  test(
    'safeArchiveDestination rejects absolute and traversing names',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'qayd_safe_path_test_',
      );
      addTearDown(() => root.delete(recursive: true));

      expect(safeArchiveDestination(root.path, '../escape.txt'), isNull);
      expect(safeArchiveDestination(root.path, r'..\escape.txt'), isNull);
      expect(safeArchiveDestination(root.path, 'C:/escape.txt'), isNull);
      expect(safeArchiveDestination(root.path, '/escape.txt'), isNull);
      expect(
        safeArchiveDestination(root.path, 'nested/receipt.png'),
        p.join(root.path, 'nested', 'receipt.png'),
      );
    },
  );
}
