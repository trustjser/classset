# 课集（ClassSet）

课集是一款面向学校的纯本地排课与课务工作台，基于 **Tauri v2 + React + TypeScript + Tailwind CSS + shadcn/ui + SQLite** 构建，同时支持 **桌面端（macOS / Windows / Linux）** 与 **浏览器端（Web / PWA）** 运行，所有课务数据均保存在本地，离线可随时查看与编排。

同时，课集内置 **MCP（桌面端 Streamable HTTP）** 与 **WebMCP（浏览器端）** 协议支持，可接入兼容工具调用的客户端辅助完成建班、科目节数配置、教师任课分配、自动排课、带班安排与临时调代课。

## 核心功能

- **基础设置**：学期与教学日历（单双周、停课与补课例外）、班级与学段（批量建班与排序）、作息设置（上课天、节次时间、公共时段与涂抹式免任课矩阵）、公共场室。
- **排课准备**：科目节数（单双周配对、科目预设/连堂限制/行课场室、Excel/TSV 导入导出与容量校验）、教师任课（合班上课、教师分组、教师预排矩阵）。
- **课表与课务**：自动排课求解与拖拽/互换微调、带班安排（周/班级/教师三视图、智能匹配、版本发布）、临时调代课（移课、正课代课、换课、带班替班及撤销）。
- **数据备份与迁移**：支持本地 `.sqlite` 备份导出与导入恢复，空库初始页即可一键导入备份或通过向导初始化。
- **MCP / WebMCP 集成**：桌面端开启连接后暴露本地 Streamable HTTP MCP 服务，Web 端支持 Chrome WebMCP，并提供待确认操作队列与自动写入开关。

## 本地开发与构建

环境要求：Node.js（参见 `.nvmrc`）、npm；如需构建桌面端，另需安装 Rust 工具链及对应平台的 Tauri v2 系统依赖。

```bash
# 安装前端依赖
npm install

# 启动 Web 端开发服务器
npm run dev

# 类型检查与单元测试
npx tsc --noEmit
npx vitest run

# 构建前端产物 / 官网与 Web PWA（输出至 websitedist/）
npm run build
npm run build:site

# 启动 Tauri 桌面端开发 / 构建桌面安装包
npm run tauri:dev
npm run tauri:build
```

完整测试命令（含 Web 测试、Vitest 与 Rust 单测）：

```bash
npm test
```

## 持续构建与发布（GitHub Actions）

构建工作流见 [.github/workflows/build.yml](.github/workflows/build.yml)。

| 触发方式 | 行为 |
| --- | --- |
| `workflow_dispatch` 手动触发 | 构建 macOS（arm64 / x64）、Windows（x64）与 Linux（x64）安装包，并上传为 Actions 产物（保留 30 天） |
| 推送 `v*` 标签 | 完成四平台矩阵构建后，自动创建或更新 GitHub Release 并上传全部安装包 |

发版示例：

```bash
git tag v0.2.1
git push origin v0.2.1
```

当前矩阵构建产物：

- **macOS (Apple Silicon / Intel)**：`*.dmg`
- **Windows (x64)**：`*.msi`
- **Linux (x64)**：`*.deb`、`*.AppImage`

> 产物为未签名构建：macOS 首次打开如遇 Gatekeeper 拦截，可右键选择「打开」或在「隐私与安全性」中允许；Windows SmartScreen 提示时可选择「更多信息 → 仍要运行」。

## 相关文档

- 开发规范与架构边界：[AGENTS.md](AGENTS.md)
- UI 视觉与交互规范：[design/DESIGN.md](design/DESIGN.md)
- 数据模型与迁移说明：[docs/data-schema.md](docs/data-schema.md)
