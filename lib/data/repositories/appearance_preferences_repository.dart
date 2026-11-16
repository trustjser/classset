import 'dart:convert';
import 'dart:io';

import 'package:class_set/core/theme/app_appearance.dart';

/// 本机外观配置，独立于学校数据库及课表备份。
class AppearancePreferencesRepository {
  AppearancePreferencesRepository(this.file);

  final File file;
  Future<void> _pendingWrite = Future<void>.value();

  Future<AppAppearance> load() async {
    try {
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic>
          ? AppAppearance.fromJson(value)
          : const AppAppearance();
    } on FileSystemException {
      return const AppAppearance();
    } on FormatException {
      return const AppAppearance();
    }
  }

  Future<void> save(AppAppearance appearance) {
    final write = _pendingWrite.catchError((Object _) {}).then((_) async {
      await file.parent.create(recursive: true);
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(
        jsonEncode(appearance.toJson()),
        flush: true,
      );
      await temporary.rename(file.path);
    });
    _pendingWrite = write;
    return write;
  }
}
