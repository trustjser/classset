import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart' show getCrc32;
import 'package:class_set/data/database/app_database.dart';
import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:drift/native.dart';

/// A verified SQLite image and the metadata recorded when it was created.
class LocalBackup {
  const LocalBackup._({
    required this.id,
    required this.label,
    required this.createdAt,
    required this.file,
    required this.byteLength,
    required this.crc32,
    required this.schemaVersion,
  });

  final String id;
  final String label;
  final DateTime createdAt;
  final File file;
  final int byteLength;
  final String crc32;
  final int schemaVersion;
}

/// A copy of the original database files saved before a restore.
class RestoreResult {
  const RestoreResult(this.originalFilesDirectory);

  /// Contains the byte-for-byte copies of the previous main, WAL and SHM files.
  final Directory originalFilesDirectory;
}

/// Creates consistent local SQLite images and restores them after DB shutdown.
///
/// [databaseFile] must be the file used to open [database]. The caller must
/// serialize backup creation with scheduling commits. For restore, [closeDatabase]
/// must stop new database work and close every connection to [databaseFile].
class LocalBackupService {
  LocalBackupService(this.database, this.databaseFile)
    : backupDirectory = Directory(
        '${databaseFile.parent.path}${Platform.pathSeparator}backups',
      );

  final AppDatabase database;
  final File databaseFile;
  final Directory backupDirectory;

  static final _validId = RegExp(r'^\d{8}T\d{6}\.\d{6}Z-[0-9a-f]{12}$');

  /// Saves the committed logical database, including transactions in its WAL.
  ///
  /// Use labels such as `before-scheduling` and `after-scheduling` around a
  /// scheduling commit. An incomplete image is removed if creation fails.
  Future<LocalBackup> createSnapshot({required String label}) async {
    if (label.trim().isEmpty) {
      throw ArgumentError.value(label, 'label', 'Must not be empty');
    }
    await _ensureBackupDirectory();

    final now = DateTime.now().toUtc();
    final id = _newId(now);
    final image = _imageFile(id);
    final imagePending = File('${image.path}.pending');
    final metadata = _metadataFile(id);
    final metadataPending = File('${metadata.path}.pending');

    try {
      // SQLite creates the destination itself. VACUUM INTO reads a consistent
      // view even while the live database uses write-ahead logging.
      await database.customStatement('VACUUM INTO ?', [imagePending.path]);
      final details = await _inspectSqlite(imagePending);
      if (details.schemaVersion != database.schemaVersion) {
        throw StateError('备份数据库版本与当前应用不一致。');
      }
      final fingerprint = await _fingerprint(imagePending);
      if (fingerprint.byteLength == 0) {
        throw StateError('备份镜像为空。');
      }

      await imagePending.rename(image.path);
      final backup = LocalBackup._(
        id: id,
        label: label,
        createdAt: now,
        file: image,
        byteLength: fingerprint.byteLength,
        crc32: fingerprint.crc32,
        schemaVersion: details.schemaVersion,
      );
      await metadataPending.writeAsString(
        jsonEncode(_toJson(backup)),
        flush: true,
      );
      await metadataPending.rename(metadata.path);
      return backup;
    } catch (_) {
      await _deleteIfExists(imagePending);
      await _deleteIfExists(metadataPending);
      await _deleteIfExists(image);
      await _deleteIfExists(metadata);
      rethrow;
    }
  }

  /// Lists completed images, newest first. Partial writes are ignored.
  Future<List<LocalBackup>> listSnapshots() async {
    await _ensureBackupDirectory();
    final backups = <LocalBackup>[];
    await for (final entity in backupDirectory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      final name = _basename(entity.path);
      final id = name.substring(0, name.length - '.json'.length);
      if (!_validId.hasMatch(id)) continue;
      try {
        final backup = await _readMetadata(id);
        if (await backup.file.exists()) backups.add(backup);
      } on FormatException {
        // A damaged manifest is not a usable backup.
      }
    }
    backups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return backups;
  }

  /// Checks the manifest, file length, CRC32, SQLite integrity and schema.
  Future<void> verifySnapshot(LocalBackup backup) async {
    final stored = await _readMetadata(backup.id);
    if (backup.file.path != stored.file.path ||
        backup.byteLength != stored.byteLength ||
        backup.crc32 != stored.crc32 ||
        backup.schemaVersion != stored.schemaVersion) {
      throw StateError('备份元数据不匹配。');
    }
    if (!await stored.file.exists()) {
      throw StateError('备份镜像文件不存在。');
    }
    final fingerprint = await _fingerprint(stored.file);
    if (fingerprint.byteLength != stored.byteLength ||
        fingerprint.crc32 != stored.crc32) {
      throw StateError('备份镜像校验失败。');
    }
    final details = await _inspectSqlite(stored.file);
    final canMigrate =
        (details.schemaVersion == 16 && database.schemaVersion == 17) ||
        (const {16, 17}.contains(details.schemaVersion) &&
            database.schemaVersion == 18);
    if (details.schemaVersion != stored.schemaVersion ||
        (details.schemaVersion != database.schemaVersion && !canMigrate)) {
      throw StateError('备份数据库版本与当前应用不一致。');
    }
  }

  /// Restores [backup] and retains exact copies of the previous DB files.
  ///
  /// [closeDatabase] is called only after the backup passes verification. It
  /// must stop all writers and await closing every connection to this database.
  /// Reopen a new [AppDatabase] instance after this method returns.
  Future<RestoreResult> restoreSnapshot(
    LocalBackup backup, {
    required Future<void> Function() closeDatabase,
  }) async {
    await verifySnapshot(backup);
    await closeDatabase();
    if (!await databaseFile.exists()) {
      throw StateError('原数据库文件不存在，已取消恢复。');
    }

    await _ensureBackupDirectory();
    final restoreId = _newId(DateTime.now().toUtc());
    final originals = Directory(
      '${backupDirectory.path}${Platform.pathSeparator}original-$restoreId',
    );
    await originals.create();

    final currentFiles = <File>[
      databaseFile,
      File('${databaseFile.path}-wal'),
      File('${databaseFile.path}-shm'),
    ];
    final presentFiles = <File>[];
    final heldFiles = <File, File>{};
    final staged = File('${databaseFile.path}.restore-$restoreId.pending');
    var replacementInstalled = false;

    try {
      // Copy and compare each original before touching any live file. This
      // preserves WAL content as well as the main database when present.
      for (final source in currentFiles) {
        final type = await FileSystemEntity.type(
          source.path,
          followLinks: false,
        );
        if (type == FileSystemEntityType.notFound) continue;
        if (type != FileSystemEntityType.file) {
          throw StateError('原数据库路径不是普通文件。');
        }
        presentFiles.add(source);
        final copy = File(
          '${originals.path}${Platform.pathSeparator}${_basename(source.path)}',
        );
        await _copyBytes(source, copy);
        if (!await _filesEqual(source, copy)) {
          throw StateError('原数据库逐字节副本校验失败。');
        }
      }

      await _copyBytes(backup.file, staged);
      if (!await _filesEqual(backup.file, staged)) {
        throw StateError('待恢复镜像逐字节校验失败。');
      }
      final stagedFingerprint = await _fingerprint(staged);
      if (stagedFingerprint.byteLength != backup.byteLength ||
          stagedFingerprint.crc32 != backup.crc32) {
        throw StateError('待恢复镜像校验值不匹配。');
      }
      final stagedDetails = await _inspectSqlite(staged);
      if (stagedDetails.schemaVersion != backup.schemaVersion) {
        throw StateError('待恢复镜像版本不匹配。');
      }

      // Move the old main, WAL and SHM together out of SQLite's active paths.
      // A preserved copy remains in [originals] even if a later rename fails.
      for (final source in presentFiles) {
        final held = File('${source.path}.restore-$restoreId.old');
        await source.rename(held.path);
        heldFiles[source] = held;
      }
      await staged.rename(databaseFile.path);
      replacementInstalled = true;
      for (final held in heldFiles.values) {
        try {
          await _deleteIfExists(held);
        } on FileSystemException {
          // The restored database is already installed. Keep the extra old
          // file for manual cleanup rather than reporting a failed restore.
        }
      }
      return RestoreResult(originals);
    } catch (_) {
      if (!replacementInstalled) {
        for (final entry in heldFiles.entries.toList().reversed) {
          if (await entry.value.exists()) {
            await entry.value.rename(entry.key.path);
          }
        }
      }
      if (heldFiles.isEmpty && await originals.exists()) {
        try {
          await originals.delete(recursive: true);
        } on FileSystemException {
          // Preserve the original failure; partial copies can be removed later.
        }
      }
      rethrow;
    } finally {
      try {
        await _deleteIfExists(staged);
      } on FileSystemException {
        // Preserve any earlier error if temporary file cleanup fails.
      }
    }
  }

  Future<void> _ensureBackupDirectory() async {
    final type = await FileSystemEntity.type(
      backupDirectory.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.link) {
      throw StateError('备份目录不能是符号链接。');
    }
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.directory) {
      throw StateError('备份路径不是目录。');
    }
    await backupDirectory.create(recursive: true);
  }

  File _imageFile(String id) =>
      File('${backupDirectory.path}${Platform.pathSeparator}$id.sqlite');

  File _metadataFile(String id) =>
      File('${backupDirectory.path}${Platform.pathSeparator}$id.json');

  Future<LocalBackup> _readMetadata(String id) async {
    if (!_validId.hasMatch(id)) throw FormatException('Invalid backup ID');
    final metadata = _metadataFile(id);
    if (await FileSystemEntity.type(metadata.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatException('Backup metadata is missing or is a link');
    }
    final data = jsonDecode(await metadata.readAsString());
    if (data is! Map<String, dynamic> ||
        data['version'] != 1 ||
        data['id'] != id ||
        data['label'] is! String ||
        data['createdAt'] is! String ||
        data['byteLength'] is! int ||
        data['crc32'] is! String ||
        data['schemaVersion'] is! int) {
      throw FormatException('Invalid backup metadata');
    }
    final image = _imageFile(id);
    if (await FileSystemEntity.type(image.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw FormatException('Backup image is missing or is a link');
    }
    final createdAt = DateTime.tryParse(data['createdAt'] as String);
    final byteLength = data['byteLength'] as int;
    final crc32 = data['crc32'] as String;
    final schemaVersion = data['schemaVersion'] as int;
    if (createdAt == null ||
        byteLength <= 0 ||
        !RegExp(r'^[0-9a-f]{8}$').hasMatch(crc32) ||
        schemaVersion <= 0) {
      throw FormatException('Invalid backup metadata values');
    }
    return LocalBackup._(
      id: id,
      label: data['label'] as String,
      createdAt: createdAt,
      file: image,
      byteLength: byteLength,
      crc32: crc32,
      schemaVersion: schemaVersion,
    );
  }

  Map<String, Object> _toJson(LocalBackup backup) => {
    'version': 1,
    'id': backup.id,
    'label': backup.label,
    'createdAt': backup.createdAt.toIso8601String(),
    'byteLength': backup.byteLength,
    'crc32': backup.crc32,
    'schemaVersion': backup.schemaVersion,
  };

  static String _newId(DateTime now) {
    final timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}T'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}.'
        '${(now.millisecond * 1000 + now.microsecond).toString().padLeft(6, '0')}Z';
    final random = Random.secure();
    final suffix = List.generate(
      6,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    return '$timestamp-$suffix';
  }
}

class _Fingerprint {
  const _Fingerprint(this.byteLength, this.crc32);

  final int byteLength;
  final String crc32;
}

Future<_Fingerprint> _fingerprint(File file) async {
  var length = 0;
  var crc = 0;
  await for (final bytes in file.openRead()) {
    length += bytes.length;
    crc = getCrc32(bytes, crc);
  }
  return _Fingerprint(length, crc.toRadixString(16).padLeft(8, '0'));
}

Future<void> _copyBytes(File source, File destination) async {
  final output = destination.openWrite();
  try {
    await output.addStream(source.openRead());
    await output.flush();
  } finally {
    await output.close();
  }
}

Future<bool> _filesEqual(File a, File b) async {
  if (await a.length() != await b.length()) return false;
  final left = await a.open();
  final right = await b.open();
  try {
    while (true) {
      final l = await left.read(64 * 1024);
      final r = await right.read(64 * 1024);
      if (l.length != r.length) return false;
      if (l.isEmpty) return true;
      for (var i = 0; i < l.length; i++) {
        if (l[i] != r[i]) return false;
      }
    }
  } finally {
    await left.close();
    await right.close();
  }
}

Future<void> _deleteIfExists(File file) async {
  if (await file.exists()) await file.delete();
}

String _basename(String path) => path.split(Platform.pathSeparator).last;

class _SqliteDetails {
  const _SqliteDetails(this.schemaVersion);

  final int schemaVersion;
}

Future<_SqliteDetails> _inspectSqlite(File file) async {
  if (!await file.exists()) throw StateError('数据库文件不存在。');
  final executor = NativeDatabase(file, enableMigrations: false);
  try {
    await executor.ensureOpen(_InspectionUser());
    final result = await executor.runSelect('PRAGMA integrity_check', []);
    if (result.length != 1 || result.single.values.single != 'ok') {
      throw StateError('SQLite 完整性校验失败。');
    }
    final version = await executor.runSelect('PRAGMA user_version', []);
    final schemaVersion = version.single.values.single;
    if (schemaVersion is! int) throw StateError('无法读取数据库版本。');
    return _SqliteDetails(schemaVersion);
  } finally {
    await executor.close();
  }
}

class _InspectionUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
