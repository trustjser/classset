/// 本机外观偏好，不包含学校或学期数据。
enum AppPalette {
  sky('晴空蓝'),
  teal('海盐青'),
  cloud('云白墨灰');

  const AppPalette(this.label);
  final String label;
}

enum AppAppearanceMode {
  system('跟随系统'),
  light('浅色模式'),
  dark('深色模式');

  const AppAppearanceMode(this.label);
  final String label;
}

class AppAppearance {
  const AppAppearance({
    this.palette = AppPalette.sky,
    this.mode = AppAppearanceMode.system,
  });

  final AppPalette palette;
  final AppAppearanceMode mode;

  factory AppAppearance.fromJson(Map<String, Object?> json) => AppAppearance(
    palette: AppPalette.values
        .where((value) => value.name == json['palette'])
        .firstOrNull ?? AppPalette.sky,
    mode: AppAppearanceMode.values
        .where((value) => value.name == json['mode'])
        .firstOrNull ?? AppAppearanceMode.system,
  );

  Map<String, Object?> toJson() => {'palette': palette.name, 'mode': mode.name};

  AppAppearance copyWith({AppPalette? palette, AppAppearanceMode? mode}) =>
      AppAppearance(palette: palette ?? this.palette, mode: mode ?? this.mode);

  @override
  bool operator ==(Object other) =>
      other is AppAppearance && other.palette == palette && other.mode == mode;

  @override
  int get hashCode => Object.hash(palette, mode);
}
