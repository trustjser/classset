# Agent 指南

本文件是本仓库 AI 编码代理的项目入口。Flutter 和 Dart 的通用任务规范来自 Flutter 团队维护的官方 Skills，见 [`.agents/skills/`](.agents/skills/)；适用时先读取对应 Skill，再修改代码。

## 项目结构与边界

- `lib/app.dart`：应用组装、页面框架与导航入口。
- `lib/features/`：按业务功能组织页面和交互。页面通过 Riverpod Provider 读取状态并发起操作。
- `lib/domain/models/`：学期、学校结构和作息等领域模型；不依赖 Flutter UI 或 Drift 数据库实现。
- `lib/data/repositories/school_repository.dart`：仓库抽象；`drift_school_repository.dart`：Drift/SQLite 实现与数据读写逻辑。
- `lib/data/database/`：Drift 数据库定义及生成文件。
- `lib/data/providers/`：数据库、仓库和流状态的 Riverpod Provider。
- `lib/core/`：跨功能共享代码，例如主题。

## 实现约定

- 延续现有分层和依赖方向：页面使用 Provider 与 `SchoolRepository`，不要在 Widget 中直接操作 Drift 表或数据库。
- 状态管理沿用 `flutter_riverpod`；数据库访问沿用 Drift 和本地 SQLite。新增依赖或替换框架前先确认需求。
- 保持领域模型独立于 UI 和持久化实现；持久化转换与查询放在 `data` 层。
- `*.g.dart` 等生成文件不要手工修改。修改 Drift schema 后运行 `dart run build_runner build --delete-conflicting-outputs`。
- 延续 `analysis_options.yaml` 的 Flutter lint、Dart 格式和现有命名风格；用户界面文本默认使用简体中文。
- Flutter 页面需兼顾桌面窗口尺寸变化，避免固定尺寸导致溢出；复用现有主题和组件风格。
- 新增或修改行为时，按改动范围补充或更新测试；不要为了无关改动大规模重构。

## 常用命令

```bash
flutter pub get
dart format lib
flutter analyze
flutter test
flutter run -d macos
```

若本地没有测试目录或测试当前无法运行，应在结果中说明；不要把未执行的检查描述为已通过。

## Flutter 官方规则

`.agent/rules/` 中的规则原样来自 Flutter 官方 [`flutter/agent-plugins`](https://github.com/flutter/agent-plugins/tree/main/rules) 仓库。编辑 `lib/**/*.dart` 时遵循 [Flutter 热重载规则](.agent/rules/flutter-hot-reload.md)；仅当相应 Dart/Flutter MCP 工具已连接时调用工具，并如实报告未连接或未运行的情况。官方 Codex 安装说明见 [Flutter AI 开发指南](https://docs.flutter.dev/ai/get-started)。


## 项目UI规范
规范文件 `design/DESIGN.md`