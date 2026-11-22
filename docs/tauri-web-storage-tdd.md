# 课集（ClassSet）Web + Tauri 桌面双端数据存储架构 TDD（技术设计文档）

- **文档版本**：v1.0
- **状态**：已确认（阶段 2 核心交付物）
- **适用范围**：课集（ClassSet）Tauri v2 桌面端与 Web 浏览器端重构工程
- **关联 Schema 版本**：SQLite Schema v19（共 29 张核心业务表 + 7 个复合索引）

---

## 1. 背景与核心诉求

原 Flutter 桌面端（`drift` + `sqlite3_flutter_libs`）采用单个本机 SQLite 文件（`class_set/school.sqlite`）作为唯一数据源（Single Source of Truth）。重构为 **Tauri v2 + React + TypeScript + Tailwind CSS v3 + shadcn/ui** 并同时支持 **桌面端 + Web 端** 时，存储架构必须回答两个核心问题：
1. **Web 端采用哪种持久化模式**（纯浏览器本地 OPFS SQLite vs 局域网/云端服务端同步）？
2. **如何保证桌面端与 Web 端 100% 共享同一套 `SchoolRepository` 与 SQL 事务逻辑**，且能无缝打开、导入、导出老版本 Flutter 生成的 `school.sqlite`（Schema v19）？

---

## 2. Web 端数据存储模式深度对比与选型结论

针对学校排课与教务管理场景，我们对三种候选方案进行了全方位量化对比：

| 评估维度 | 方案 A：纯浏览器本地 SQLite (Wasm + OPFS / IndexedDB) | 方案 B：局域网 / 云端服务端同步 (REST / WebSocket + Server DB) | 方案 C：本地优先 + 二进制快照互通（推荐混合架构） |
| :--- | :--- | :--- | :--- |
| **部署成本与隐私合规** | **极佳**：零服务器成本，静态页面即可托管（Cloudflare Pages / 内网 Nginx），学校教务数据不出本机浏览器 | **较高**：需额外部署后端进程与数据库，涉及学校教师实名数据上云合规审查 | **极佳**：默认纯本地 OPFS/IndexedDB 零配置运行；支持一键导出/导入 `.sqlite` 原生文件或局域网主机挂载 |
| **与 Tauri 桌面端代码复用率** | **98%**：前后端均执行完全相同的 SQLite v19 SQL 语句 | **60%**：需额外维护一套 HTTP API、DTO 与多端并发冲突合并逻辑 | **100%**：通过 `SqlDatabaseAdapter` 统一抽象 `select` / `execute` / `transaction` / `importSqliteBytes` / `exportSqliteBytes` |
| **与老版 Flutter `school.sqlite` 兼容性** | **原生兼容**：可直接读取/写出标准 SQLite 二进制字节流 | **不兼容**：需编写 ETL 迁移脚本将 SQLite 转为 PostgreSQL/MySQL | **100% 二进制级双向兼容**：桌面端与 Web 端可直接互传同一个 `school.sqlite` 文件 |
| **排课求解器（Rust Wasm）协同效率** | **零网络延迟**：排课快照直接从浏览器内存/OPFS 喂给 Web Worker 中的 Wasm 求解器 | **受网络制约**：上千节课节与约束频繁请求接口有序列化开销 | **零网络延迟**：本地 SQLite 内存态直通 Wasm Worker，毫秒级读取 `SchedulingSnapshot` |
| **多设备/教务处协同能力** | 仅限单浏览器，清理高强度浏览器缓存存在丢失风险 | 原生支持多人实时在线查课与调代课 | **兼顾单机高可靠与协同**：教务排课员用桌面端或 Web 本地排课 + 自动备份 `.sqlite`；可选开启局域网只读/同步网关 |

### 最终架构选型结论
确定采用 **「方案 C：Local-First 双端同构 SQLite 引擎 + `.sqlite` 二进制快照无缝互通（预留可选局域网同步扩展点）」**：
1. **桌面端（Tauri v2）**：通过 `@tauri-apps/plugin-sql` 直连操作系统 Application Support 目录下的 `school.sqlite`，具备原生文件锁与事务性能。
2. **Web 端（Browser）**：通过 **SQLite Wasm (`sql.js` + OPFS / IndexedDB 二进制持久化)** 在浏览器内运行真正的 SQLite 关系型引擎，执行与桌面端一字不差的 Schema v19 DDL、外键级联（`PRAGMA foreign_keys = ON`）与 `UNIQUE` 约束。
3. **双端文件级互通**：在 `SqlDatabaseAdapter` 中内置 `exportDatabaseBytes(): Promise<Uint8Array>` 与 `importDatabaseBytes(bytes: Uint8Array): Promise<void>`。用户在 Web 端排完课可一键下载标准 `school.sqlite`，拖入 Tauri 桌面端（或原 Flutter 端）即可直接打开，反之亦然。

---

## 3. 双端存储分层与接口契约设计

### 3.1 `SqlDatabaseAdapter` 底层驱动接口 (`src/adapter/db/databaseAdapter.ts`)

```typescript
export interface QueryResult {
  rowsAffected: number;
  lastInsertId?: number;
}

export interface SqlDatabaseAdapter {
  readonly runtimeMode: 'tauri-desktop' | 'web-browser';
  readonly schemaVersion: number;
  readonly engineStatus: 'native-sqlite' | 'wasm-sqlite' | 'memory-fallback';

  /** 初始化数据库连接、开启 PRAGMA foreign_keys = ON 并执行 Schema v19 迁移 */
  init(): Promise<void>;

  /** 参数化查询（自动返回强类型行对象数组） */
  select<T = Record<string, unknown>>(sql: string, bindValues?: unknown[]): Promise<T[]>;

  /** 参数化写操作（INSERT / UPDATE / DELETE） */
  execute(sql: string, bindValues?: unknown[]): Promise<QueryResult>;

  /** 原子事务执行：任一步骤抛错自动 ROLLBACK，全部成功则 COMMIT 并落盘 */
  transaction<T>(fn: (tx: Pick<SqlDatabaseAdapter, 'select' | 'execute'>) => Promise<T>): Promise<T>;

  /** 导出当前数据库为标准 SQLite3 二进制字节流 (兼容桌面端 school.sqlite) */
  exportSqliteBytes(): Promise<Uint8Array | null>;

  /** 从外部 .sqlite 文件字节流恢复/替换当前数据库 */
  importSqliteBytes(bytes: Uint8Array): Promise<void>;
}
```

### 3.2 Web 端持久化策略（IndexedDB 大容量存储 + LocalStorage 双保险）
- **为什么不用单一 `localStorage`？** `localStorage` 仅有 5MB 上限，当 `schedule_run_reports`（排课诊断报告 JSON）、`published_schedules`（正式课表快照）和 `supervision_plan_versions`（带班历史版本）累积后容易触及配额上限。
- **IndexedDB 二进制块存储**：Web 适配器将 SQLite Wasm 导出的 `Uint8Array` 二进制镜像存储在 IndexedDB 的 `classset_sqlite_store` 对象仓库（Key: `school.sqlite.v19`）中，支持数百 MB 的排课快照与历史版本；同时在 `localStorage` 保留轻量级元数据快照，确保即使在无 Wasm CDN 的受限内网环境下也能平滑降级运行。

---

## 4. Schema v19 全量 29 张表与事务级联规范

在 `src-tauri/migrations/001_schema_v19.sql` 与 `src/adapter/db/schemaV19.ts` 中，完整映射原 Flutter Drift 的 29 张物理表，按业务领域划分为 6 大表簇：

| 业务领域 | 包含物理表（Schema v19） | 核心外键级联与事务边界 |
| :--- | :--- | :--- |
| **1. 全局设置与学期日历** | `app_settings`, `academic_terms`, `calendar_exceptions` | 删除 `academic_terms` 时，`ON DELETE CASCADE` 自动清理该学期下所有学段、科目、任课、课表及调代记录；`app_settings.active_term_id` 设为 `ON DELETE SET NULL`。 |
| **2. 学段、年级、班级与作息** | `school_stages`, `grade_groups`, `class_groups`, `stage_teaching_days`, `lesson_period_types`, `daily_lesson_overrides`, `lesson_times`, `free_slots`, `common_periods` | `saveRoutine` 在单个事务中更新上课天、时段类型、按天差异与节次时间，并自动修复 `common_periods` 漂移的 `insert_after_lesson_id` 挂载点、清理越界的 `free_slots`。 |
| **3. 科目、节数需求、预设与配对** | `subjects`, `subject_requirements`, `subject_presets`, `subject_pairings`, `subject_lesson_constraints` | `replaceGradeRequirements` 在单事务内按年级整体替换（`DELETE` + 批量 `INSERT`）；`replaceSubjectPresets` 在「全校」范围保存时按时段名称匹配自动展开到所有学段。 |
| **4. 公共场室与并发控制** | `public_rooms`, `subject_room_assignments`, `subject_parallel_limits` | 带 `CHECK (room_count > 0)`、`CHECK (capacity_per_room > 0)` 及 `UNIQUE (subject_id, term_id, scope_type, scope_id)` 约束。 |
| **5. 教师、分组、任课与教师预排** | `teachers`, `teacher_subject_tags`, `teacher_groups`, `teacher_group_members`, `teacher_assignments`, `teacher_presets`, `teacher_group_presets` | `teachers` 跨学期全局复用；删除教师时 `teacher_assignments.teacher_id` 触发 `ON DELETE SET NULL`（保留任课坑位待重新指派）。 |
| **6. 自动排课、带班与临时调代** | `schedule_items`, `schedule_locks`, `schedule_conditions`, `schedule_preferences`, `schedule_run_reports`, `schedule_reconciliation_baselines`, `published_schedules`, `temporary_course_adjustments`, `supervision_drafts`, `supervision_plan_versions` | 包含 7 个高频查询索引（如 `schedule_items_class_slot`、`schedule_items_teacher_slot`）；草稿与正式发布表严格分离，乐观锁校验 `expectedRevision` / `expectedFingerprint`。 |

---

## 5. `SchoolRepository` 阶段 2 完成度核对清单

为了确保阶段 3（基础设置 UI）、阶段 4（排课工作台）和阶段 5（带班与调代课）可以直接调用数据层，阶段 2 的 `SchoolRepository` (`src/repository/schoolRepository.ts`) 现已完整覆盖以下能力：

- [x] **应用与学期管理**：`loadSchoolName` / `saveSchoolName`、`loadActiveTermId` / `saveActiveTermId`、`loadTerms`、`saveTerm`（新建学期自动初始化小学部 + 周一至周五 4+4+2 默认作息）、`cloneTerm`（按新旧第 1 教学周起始日自动平移日历例外与补课日期）、`deleteTerm`。
- [x] **学段、年级与班级结构**：`loadStages` / `saveStage` / `deleteStage`（新建学段自动继承全校范围免任课）、`loadGrades` / `saveGrades` / `deleteGrade`、`loadClasses` / `saveClasses` / `deleteClass`。
- [x] **分学段作息、免任课、公共时段与日历例外**：`loadStageRoutine` / `saveStageRoutine`（含漂移修复与越界免任课清理）、`loadFreeSlots` / `saveFreeSlot` / `deleteFreeSlot`、`loadCommonPeriods` / `saveCommonPeriod` / `deleteCommonPeriod`、`loadCalendarExceptions` / `saveCalendarExceptions`。
- [x] **科目、节数需求、预设、配对、课节限制与公共场室**：`loadSubjects` / `saveSubjects` / `deleteSubject`、`loadSubjectRequirements` / `replaceGradeRequirements`、`loadSubjectPresets` / `replaceSubjectPresets`、`loadSubjectPairings` / `replaceClassPairings`、`loadSubjectLessonConstraints` / `replaceSubjectLessonConstraints`、`loadPublicRooms` / `savePublicRooms` / `deletePublicRoom`、`replaceSubjectRoomSettings`。
- [x] **教师、分组、任课与预排**：`loadTeachers` / `saveTeachers` / `deleteTeacher`、`loadTeacherGroups` / `saveTeacherGroupsWithMembers`、`loadTeacherAssignments` / `replaceTeacherAssignments` / `combineTeacherAssignments` / `separateTeacherAssignments`、`loadTeacherPresets` / `replaceTeacherPresets`。
- [x] **排课快照、带班草稿/版本与临时调代课**：`loadScheduleItems` / `commitManualScheduleEdit` / `publishSchedule`、`loadSupervisionDraft` / `saveSupervisionDraft` / `publishSupervision`、`loadTemporaryAdjustments` / `commitTemporaryAdjustment` / `cancelTemporaryAdjustment`。
- [x] **跨端 `.sqlite` 备份导入与导出**：`exportSqliteFile` / `importSqliteFile`（支持 Web 端与 Tauri 桌面端互传 `school.sqlite`）。
