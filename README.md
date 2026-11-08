# 课集（ClassSet）

课集是一个纯本地 Flutter 桌面应用，按 PRD v0.5 与 Ardot 设计稿（fileId 735702770970447）实现。目前提供学期与日历、班级与学段、作息设置三个主流程页面的资料录入，数据保存在本机 SQLite 文件中。

## 运行

```bash
flutter pub get
flutter run -d macos
```

Windows 和 Linux 可分别使用 `flutter run -d windows` 与 `flutter run -d linux`。

应用首次启动会在平台的 Application Support 目录下创建 `class_set/school.sqlite`。新建学期时会自动创建一个小学部，并初始化周一至周五、上午 4 节、下午 4 节、晚上 2 节的示例作息；这些资料之后都可以编辑。

## 功能概览

### 学期与日历

- 学期管理：新建 / 编辑 / 删除，设置学年、学期、第 1 教学周起始日（定义为单周）与教学周数；单双周此后自动交替。
- 教学日历表：逐周展示周次、单双周徽章、日期范围与例外安排；超过 6 周可展开。
- 例外安排：按周设置停课 / 节假日与补课；补课明确映射「采用哪一天、哪一周的课表」（含原课日期与单双周）。

### 班级与学段

- 学段管理：预置小学部 / 初中部 / 高中部，可改名、新增（如国际部）；每个学期至少保留一个学段。
- 年级与班级：按学段批量新增年级（多种命名模板），班级支持逐个添加与批量填充名称（模板 + 范围 + 预览 + 撤销上次填充）；年级、班级顺序可调。
- 删除时二次确认并列出连带删除的资料。

### 作息设置

- 范围树：全校 / 学段 / 年级 / 班级四级范围（年级、班级可展开），免任课按范围独立保存。
- 上课天与每天节数：按学段独立设置；时段类型支持自定义（早读、晚自习等），每类型默认 0–9 节。
- 免任课矩阵：按「星期 × 节次」逐格设置，单击标记 / 再击取消，右键选类型（无课 / 自习 / 劳动 / 教研活动 / 党团活动 / 自定义）；「无课」打印空白，其他类型打印该文字。
- 按天差异：单独调整某一天某时段的节数（如周五晚上 = 0），并实时显示每周容量。
- 节次与时间：按时段分组填写每节起止时间；公共时段（大课间、眼保健操等）可插入任意两节之间，不排正课、仅显示于课表与打印。
- 跨学段提示：存在多个学段且节次时间未填全时，提示按钟点重叠判定冲突。

数据模型与迁移见 [docs/data-schema.md](docs/data-schema.md)。领域逻辑与仓储层测试：

```bash
flutter test
```

## 持续构建（GitHub Actions）

工作流见 [.github/workflows/build.yml](.github/workflows/build.yml)，固定 Flutter 3.47.2，不需要开发者 ID、证书或任何额外 Secrets。

| 触发方式 | 行为 |
| --- | --- |
| PR 到 main | 静态分析 + 测试观测，不构建安装包 |
| push 到 main / 手动触发 | 上述校验 + 构建 macOS / Windows / Linux 三平台 Release，产物上传为 Actions 附件（保留 30 天） |
| 打 `v*` 标签 | 上述构建 + 自动创建 GitHub Release 并附上三个包 |

发版示例：

```bash
git tag v0.1.0
git push origin v0.1.0
```

产物均为**未签名**构建（macOS 使用工程里既有的 ad-hoc 签名，未公证），分发时需注意：

- macOS：解压 `class_set-macos.zip` 得到「课集.app」。首次打开若被 Gatekeeper 拦截，执行 `xattr -dr com.apple.quarantine /path/to/课集.app`，或右键选择「打开」。CI 使用 `macos-latest`（当前为 macOS 26 / arm64），因此该包**仅支持 Apple Silicon**；需要 Intel Mac 版本时，把 `build.yml` 中 macOS 的 `os` 改为 `macos-26-intel` 再构建，或在 matrix 中增加一个条目。
- Windows：SmartScreen 会提示「未知发布者」，选择「更多信息 → 仍要运行」。
- Linux：解压 `class_set-linux-x64.tar.gz` 后运行 `./bundle/class_set`。

> 当前仓库有 39 个既有 analyze warning 和 62 个失败测试。CI 中分析器忽略 warning（error 仍会阻塞），测试为非阻塞观测步骤；修复完成后请移除 `build.yml` 里的这两处降级。

## 开发辅助

- `tools/capture_window.sh [应用进程名] [输出路径]`：只截取应用主窗口，不截取屏幕上其他内容（默认截取 class_set 窗口）。
