import 'dart:io';

import 'package:class_set/app.dart';
import 'package:class_set/data/repositories/appearance_preferences_repository.dart';
import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/data/providers/database_provider.dart';
import 'package:class_set/data/repositories/drift_school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory('${supportDirectory.path}/class_set');
  await databaseDirectory.create(recursive: true);

  final appearanceRepository = AppearancePreferencesRepository(
    File.fromUri(databaseDirectory.uri.resolve('appearance.json')),
  );
  final appearance = await appearanceRepository.load();

  final databaseFile = File('${databaseDirectory.path}/school.sqlite');
  final lastPersistedAt = await _lastDatabaseWriteAt(databaseFile);
  final database = AppDatabase.open(databaseFile);
  final activeTermId = await DriftSchoolRepository(database).loadActiveTermId();
  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(database),
        databasePathProvider.overrideWithValue(databaseFile.path),
        activeTermIdProvider.overrideWith((ref) => activeTermId),
        lastPersistedAtProvider.overrideWith((ref) => lastPersistedAt),
      ],
      child: ClassSetApp(
        databasePath: databaseFile.path,
        initialAppearance: appearance,
        onAppearanceChanged: appearanceRepository.save,
      ),
    ),
  );
}

Future<DateTime?> _lastDatabaseWriteAt(File databaseFile) async {
  DateTime? latest;
  final candidates = [databaseFile, File('${databaseFile.path}-wal')];
  for (final file in candidates) {
    if (!await file.exists()) continue;
    final modified = await file.lastModified();
    if (latest == null || modified.isAfter(latest)) latest = modified;
  }
  return latest;
}
