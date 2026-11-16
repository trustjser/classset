import 'dart:io';

import 'package:class_set/core/theme/app_appearance.dart';
import 'package:class_set/data/repositories/appearance_preferences_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('classset-appearance-');
    file = File.fromUri(directory.uri.resolve('appearance.json'));
  });
  tearDown(() => directory.delete(recursive: true));

  test('首次启动、损坏配置和未知值安全回退', () async {
    final repository = AppearancePreferencesRepository(file);
    expect(await repository.load(), const AppAppearance());
    for (final contents in [
      '{broken',
      '[]',
      '{"palette":"future","mode":42}',
    ]) {
      await file.writeAsString(contents);
      expect(await repository.load(), const AppAppearance());
    }
    await file.writeAsString('{"palette":"teal","mode":"future"}');
    expect(
      await repository.load(),
      const AppAppearance(palette: AppPalette.teal),
    );
  });

  test('重新创建仓库后恢复配色和独立明暗选择', () async {
    await AppearancePreferencesRepository(file).save(
      const AppAppearance(
        palette: AppPalette.cloud,
        mode: AppAppearanceMode.dark,
      ),
    );
    expect(
      await AppearancePreferencesRepository(file).load(),
      const AppAppearance(
        palette: AppPalette.cloud,
        mode: AppAppearanceMode.dark,
      ),
    );
    expect(await File('${file.path}.tmp').exists(), isFalse);
  });

  test('快速连续切换最终保存最后一次选择', () async {
    final repository = AppearancePreferencesRepository(file);
    await Future.wait([
      repository.save(const AppAppearance(palette: AppPalette.teal)),
      repository.save(
        const AppAppearance(
          palette: AppPalette.cloud,
          mode: AppAppearanceMode.dark,
        ),
      ),
      repository.save(
        const AppAppearance(
          palette: AppPalette.sky,
          mode: AppAppearanceMode.light,
        ),
      ),
    ]);
    expect(
      await AppearancePreferencesRepository(file).load(),
      const AppAppearance(
        palette: AppPalette.sky,
        mode: AppAppearanceMode.light,
      ),
    );
  });

  test('一次写入失败后仍可重试保存', () async {
    final blocker = File.fromUri(directory.uri.resolve('blocked'));
    await blocker.writeAsString('file blocks directory');
    final target = File.fromUri(
      Directory(blocker.path).uri.resolve('appearance.json'),
    );
    final repository = AppearancePreferencesRepository(target);
    await expectLater(
      repository.save(const AppAppearance()),
      throwsA(isA<FileSystemException>()),
    );
    await blocker.delete();
    await repository.save(const AppAppearance(palette: AppPalette.teal));
    expect(
      await repository.load(),
      const AppAppearance(palette: AppPalette.teal),
    );
  });
}
