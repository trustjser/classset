import 'dart:io';

import 'package:class_set/app.dart';
import 'package:class_set/data/database/app_database.dart';
import 'package:class_set/data/providers/database_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final supportDirectory = await getApplicationSupportDirectory();
  final databaseDirectory = Directory('${supportDirectory.path}/class_set');
  await databaseDirectory.create(recursive: true);

  final databaseFile = File('${databaseDirectory.path}/school.sqlite');
  final database = AppDatabase.open(databaseFile);
  runApp(
    ProviderScope(
      overrides: [appDatabaseProvider.overrideWithValue(database)],
      child: ClassSetApp(databasePath: databaseFile.path),
    ),
  );
}
