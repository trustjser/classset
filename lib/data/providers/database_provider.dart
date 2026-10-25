import 'package:class_set/data/database/app_database.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appDatabaseProvider = Provider<AppDatabase>(
  (ref) => throw UnimplementedError('AppDatabase 未初始化'),
);

/// The SQLite file path; absent for in-memory repository consumers.
final databasePathProvider = Provider<String?>((ref) => null);
