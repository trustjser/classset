/**
 * 课集 (ClassSet) AI Agent 统一工具 Schema 定义
 * 同时兼容：
 * 1. Tauri 桌面端 MCP (WorkBuddy / Claude Desktop / Cursor 等标准 Model Context Protocol)
 * 2. 浏览器/PWA 端 Chrome WebMCP (document.modelContext / navigator.modelContext)
 * 3. Chrome Built-in AI (Prompt API LanguageModel.prompt responseConstraint)
 */

export type ClassSetAgentToolName =
  | 'classset_get_context_and_gates'
  | 'classset_batch_configure_classes_and_stages'
  | 'classset_batch_configure_subjects_and_quotas'
  | 'classset_batch_configure_teachers_and_assignments'
  | 'classset_configure_schedule_rules'
  | 'classset_run_auto_schedule'
  | 'classset_move_or_swap_lesson'
  | 'classset_batch_create_supervision_posts'
  | 'classset_auto_allocate_supervision'
  | 'classset_publish_supervision_version'
  | 'classset_query_actual_timetable'
  | 'classset_apply_temporary_adjustment'
  | 'classset_cancel_temporary_adjustment';

export interface JsonSchemaProperty {
  type?: string | string[];
  description?: string;
  enum?: readonly string[];
  items?: JsonSchemaProperty | Record<string, unknown>;
  properties?: Record<string, JsonSchemaProperty | Record<string, unknown>>;
  required?: readonly string[];
  additionalProperties?: boolean;
  minimum?: number;
  maximum?: number;
  minItems?: number;
  pattern?: string;
  default?: unknown;
}

export interface JsonSchemaObject {
  type: 'object';
  description?: string;
  properties: Record<string, JsonSchemaProperty | Record<string, unknown>>;
  required?: readonly string[];
  additionalProperties: false;
}

export interface ClassSetAgentToolSchema {
  name: ClassSetAgentToolName;
  module:
    | 'context'
    | 'classes'
    | 'subjects'
    | 'teachers'
    | 'scheduling'
    | 'supervision'
    | 'temporaryAdjustments';
  readOnly: boolean;
  description: string;
  inputSchema: JsonSchemaObject;
}

/**
 * 公共基础 JSON Schema 片段（避免深层 $ref 在不同端 AI 引擎中的兼容性差异）
 */
export const AGENT_SCHEMA_DEFS = {
  WeekMode: {
    type: 'string',
    enum: ['weekly', 'odd', 'even'] as const,
    description: '周次模式：weekly(每周)、odd(单周)、even(双周)',
  },
  ScopeType: {
    type: 'string',
    enum: ['school', 'stage', 'grade', 'class'] as const,
    description: '作用范围层级：school(全校/学期)、stage(学段)、grade(年级)、class(班级)',
  },
  PresetValue: {
    type: 'string',
    enum: ['auto', 'prefer', 'must', 'forbid'] as const,
    description: '排课预设权重：auto(自动/清除预设)、prefer(优先排)、must(必排/固排)、forbid(禁排)',
  },
  SchedulePosition: {
    type: 'object' as const,
    description: '课表坐标位置（对齐 SchedulePosition 接口）',
    properties: {
      stageId: { type: 'string', description: '学段 ID' },
      weekday: {
        type: 'integer',
        minimum: 1,
        maximum: 7,
        description: '星期几（1=周一，7=周日）',
      },
      periodTypeId: {
        type: 'string',
        description: '作息时段 ID（如上午、下午、晚自习）',
      },
      lessonIndex: {
        type: 'integer',
        minimum: 1,
        maximum: 16,
        description: '该时段内的第几节课（从 1 开始）',
      },
    },
    required: ['stageId', 'weekday', 'periodTypeId', 'lessonIndex'] as const,
    additionalProperties: false as const,
  },
  NullableSchedulePosition: {
    type: ['object', 'null'] as const,
    description: '目标课位坐标；传 null 表示将该课节移入暂放区（未排课列表）',
    properties: {
      stageId: { type: 'string', description: '学段 ID' },
      weekday: {
        type: 'integer',
        minimum: 1,
        maximum: 7,
        description: '星期几（1=周一，7=周日）',
      },
      periodTypeId: {
        type: 'string',
        description: '作息时段 ID',
      },
      lessonIndex: {
        type: 'integer',
        minimum: 1,
        maximum: 16,
        description: '该时段内的第几节课（从 1 开始）',
      },
    },
    required: ['stageId', 'weekday', 'periodTypeId', 'lessonIndex'] as const,
    additionalProperties: false as const,
  },
} as const;

/**
 * 课集 13 个核心 AI Agent 工具的标准 JSON Schema 定义
 */
export const CLASSSET_AGENT_TOOL_SCHEMAS: readonly ClassSetAgentToolSchema[] = [
  {
    name: 'classset_get_context_and_gates',
    module: 'context',
    readOnly: true,
    description:
      '读取课集当前激活学期的排课准备进度（步骤级联限制状态）、学段作息时段字典、班级列表、科目列表与教师列表。执行任何基础数据配置、排课、带班或调代课工具前应先调用此工具获取实体 ID。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，指定学期 ID；不传则默认读取当前激活学期',
        },
        includeDictionaries: {
          type: 'array',
          items: {
            type: 'string',
            enum: [
              'stages_and_routines',
              'grades_and_classes',
              'subjects',
              'teachers',
              'public_rooms',
              'locks',
            ],
          },
          description: '按需指定要返回的实体字典列表。省略时只返回学期和门控摘要。',
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_batch_configure_classes_and_stages',
    module: 'classes',
    readOnly: false,
    description:
      '批量创建、修改或删除学段、年级与班级（对应「班级与学段」模块）。支持按年级传入 classCount 一键批量建班（如为一年级生成 1班~6班），或逐条指定班级名称。',
    inputSchema: {
      type: 'object',
      properties: {
        dryRun: { type: 'boolean', description: '只生成预览，不创建待确认操作' },
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        stages: {
          type: 'array',
          description: '要新增或更新的学段列表（如小学部、初中部）；若不传 id 则按名称匹配已有学段或新建',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string', description: '可选，已有学段 ID' },
              name: { type: 'string', description: '学段名称（如：小学部、初中部）' },
              sortOrder: { type: 'integer', minimum: 0, description: '可选，排序序号' },
            },
            required: ['name'],
            additionalProperties: false,
          },
        },
        deletedStageIds: {
          type: 'array',
          items: { type: 'string' },
          description: '要删除的学段 ID 列表',
        },
        grades: {
          type: 'array',
          description:
            '要新增或更新的年级列表；可通过 stageId 或 stageName 指定所属学段（若仅有一个学段可省略），并可通过 classCount 一键生成 1班~N班',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string', description: '可选，已有年级 ID' },
              stageId: { type: 'string', description: '可选，所属学段 ID' },
              stageName: { type: 'string', description: '可选，所属学段名称（可关联本次同批新建的学段）' },
              name: { type: 'string', description: '年级名称（如：一年级、七年级）' },
              sortOrder: { type: 'integer', minimum: 0, description: '可选，排序序号' },
              classCount: {
                type: 'integer',
                minimum: 1,
                maximum: 50,
                description: '可选，为该年级自动补齐 1班 ~ N班 的班级数量',
              },
            },
            required: ['name'],
            additionalProperties: false,
          },
        },
        deletedGradeIds: {
          type: 'array',
          items: { type: 'string' },
          description: '要删除的年级 ID 列表（会级联清理下属班级及关联引用）',
        },
        classes: {
          type: 'array',
          description: '要新增或更新的具体班级列表；可通过 gradeId 或 gradeName 指定所属年级',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string', description: '可选，已有班级 ID' },
              gradeId: { type: 'string', description: '可选，所属年级 ID' },
              gradeName: { type: 'string', description: '可选，所属年级名称（可关联本次同批新建的年级）' },
              name: { type: 'string', description: '班级名称（如：1班、实验1班）' },
              sortOrder: { type: 'integer', minimum: 0, description: '可选，排序序号' },
            },
            required: ['name'],
            additionalProperties: false,
          },
        },
        deletedClassIds: {
          type: 'array',
          items: { type: 'string' },
          description: '要删除的班级 ID 列表',
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_batch_configure_subjects_and_quotas',
    module: 'subjects',
    readOnly: false,
    description:
      '批量创建、修改或删除科目，并批量配置各年级/班级的科目周课时节数需求、单双周配对及单日/每周连堂上限约束（对应「科目节数」模块，需先完成作息设置）。',
    inputSchema: {
      type: 'object',
      properties: {
        dryRun: { type: 'boolean', description: '只生成预览，不创建待确认操作' },
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        subjects: {
          type: 'array',
          description: '要新增或更新的科目列表；不传 id 时按科目名称匹配或新建，不传 shortName 时默认取首字',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string', description: '可选，已有科目 ID' },
              name: { type: 'string', description: '科目名称（如：语文、数学、人工智能）' },
              shortName: { type: 'string', description: '可选，科目简称（如：语、数）' },
              sortOrder: { type: 'integer', minimum: 0, description: '可选，排序序号' },
            },
            required: ['name'],
            additionalProperties: false,
          },
        },
        deletedSubjectIds: {
          type: 'array',
          items: { type: 'string' },
          description: '要删除的科目 ID 列表',
        },
        requirements: {
          type: 'array',
          description:
            '批量设置年级或班级的科目周课时节数；可通过 subjectId/subjectName 与 gradeId/gradeName 定位；lessonCount 设为 0 表示清除该配额',
          items: {
            type: 'object',
            properties: {
              subjectId: { type: 'string', description: '可选，科目 ID' },
              subjectName: { type: 'string', description: '可选，科目名称（支持匹配本次同批新增的科目）' },
              gradeId: { type: 'string', description: '可选，年级 ID' },
              gradeName: { type: 'string', description: '可选，年级名称（如：一年级）' },
              classId: {
                type: ['string', 'null'],
                description: '可选，特定班级 ID；不传或传 null 表示作为该年级的默认科目节数',
              },
              weekMode: AGENT_SCHEMA_DEFS.WeekMode,
              lessonCount: {
                type: 'integer',
                minimum: 0,
                maximum: 40,
                description: '每周（或单/双周）节数；传 0 表示移除该科目需求',
              },
            },
            required: ['lessonCount'],
            additionalProperties: false,
          },
        },
        lessonConstraints: {
          type: 'array',
          description: '可选，配置科目单日最少/最多节数、单日/每周连堂次数上下限（对齐 SubjectLessonConstraint）',
          items: {
            type: 'object',
            properties: {
              subjectId: { type: 'string' },
              subjectName: { type: 'string' },
              scopeType: AGENT_SCHEMA_DEFS.ScopeType,
              scopeId: { type: 'string' },
              stageId: { type: 'string' },
              weekday: { type: ['integer', 'null'], minimum: 1, maximum: 7 },
              minimumDailyLessons: { type: ['integer', 'null'], minimum: 0 },
              maximumDailyLessons: { type: ['integer', 'null'], minimum: 0 },
              minimumDailyConsecutivePairs: { type: ['integer', 'null'], minimum: 0 },
              maximumDailyConsecutivePairs: { type: ['integer', 'null'], minimum: 0 },
              minimumWeeklyConsecutivePairs: { type: ['integer', 'null'], minimum: 0 },
              maximumWeeklyConsecutivePairs: { type: ['integer', 'null'], minimum: 0 },
            },
            required: ['scopeType', 'scopeId', 'stageId'],
            additionalProperties: false,
          },
        },
        pairings: {
          type: 'array',
          description: '可选，配置班级单双周科目配对（对齐 SubjectPairing）',
          items: {
            type: 'object',
            properties: {
              classId: { type: 'string' },
              oddSubjectId: { type: 'string' },
              evenSubjectId: { type: 'string' },
            },
            required: ['classId', 'oddSubjectId', 'evenSubjectId'],
            additionalProperties: false,
          },
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_batch_configure_teachers_and_assignments',
    module: 'teachers',
    readOnly: false,
    description:
      '批量创建、修改或删除教师名册（含任教学科标签），并批量设置各班各科任课教师及合班上课关系（对应「教师任课」模块，需先完成科目节数设置）。',
    inputSchema: {
      type: 'object',
      properties: {
        dryRun: { type: 'boolean', description: '只生成预览，不创建待确认操作' },
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        teachers: {
          type: 'array',
          description:
            '要新增或更新的教师列表；支持按 id 或 (name, displayQualifier) 匹配已有教师，支持通过 subjectIds 或 subjectNames 绑定所教学科',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string', description: '可选，已有教师 ID' },
              name: { type: 'string', description: '教师姓名' },
              shortName: { type: 'string', description: '可选，教师简称（默认取首字）' },
              displayQualifier: {
                type: 'string',
                description: '可选，同名教师区分标识（如：大、小、初数）',
              },
              sortOrder: { type: 'integer', minimum: 0 },
              subjectIds: {
                type: 'array',
                items: { type: 'string' },
                description: '可选，教师可任教的科目 ID 列表',
              },
              subjectNames: {
                type: 'array',
                items: { type: 'string' },
                description: '可选，教师可任教的科目名称列表（自动映射为科目 ID）',
              },
            },
            required: ['name'],
            additionalProperties: false,
          },
        },
        deletedTeacherIds: {
          type: 'array',
          items: { type: 'string' },
          description: '要删除的教师 ID 列表',
        },
        assignments: {
          type: 'array',
          description:
            '批量配置班级科目任课；支持用 classId 或 (gradeName + className)、subjectId 或 subjectName、teacherId 或 teacherName 指定；省略 lessonCount 时自动按该班该科目的需求总节数全额分配；传 teacherId: null 且不传 teacherName 表示清空该班该科任课',
          items: {
            type: 'object',
            properties: {
              classId: { type: 'string', description: '可选，班级 ID' },
              gradeName: { type: 'string', description: '可选，辅助按名称匹配班级时的年级名称（如：一年级）' },
              className: { type: 'string', description: '可选，班级名称（如：1班 或 一年级1班）' },
              subjectId: { type: 'string', description: '可选，科目 ID' },
              subjectName: { type: 'string', description: '可选，科目名称（如：数学）' },
              teacherId: {
                type: ['string', 'null'],
                description: '可选，任课教师 ID；传 null 且不传 teacherName 时清除该班该科目的任课分配',
              },
              teacherName: {
                type: 'string',
                description: '可选，任课教师姓名（支持匹配本次同批新增的教师）',
              },
              weekMode: AGENT_SCHEMA_DEFS.WeekMode,
              lessonCount: {
                type: 'integer',
                minimum: 0,
                maximum: 40,
                description: '可选，分配给该教师的节数；省略时自动采用该班级该科目的需求节数',
              },
            },
            additionalProperties: false,
          },
        },
        combinedGroups: {
          type: 'array',
          description:
            '可选，批量设置或解除跨班合班上课（要求所选班级在同一科目、同一周模式、同一教师下课时数一致）',
          items: {
            type: 'object',
            properties: {
              classIds: {
                type: 'array',
                items: { type: 'string' },
                minItems: 2,
                description: '参与合班的班级 ID 列表（至少 2 个班级）',
              },
              subjectId: { type: 'string', description: '可选，合班科目 ID' },
              subjectName: { type: 'string', description: '可选，合班科目名称' },
              weekMode: AGENT_SCHEMA_DEFS.WeekMode,
              disband: {
                type: 'boolean',
                default: false,
                description: '若为 true 则解除这些班级在该科目的合班关系；默认 false 表示绑定为合班',
              },
            },
            required: ['classIds'],
            additionalProperties: false,
          },
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_configure_schedule_rules',
    module: 'scheduling',
    readOnly: false,
    description:
      '批量配置排课预设与硬条件，支持设置教师禁排/必排、科目禁排/必排、教师互斥、科目同日互斥、禁止相邻及全局排课偏好（午休保护、连堂策略、进度一致等）。',
    inputSchema: {
      type: 'object',
      properties: {
        dryRun: { type: 'boolean', description: '只生成预览，不创建待确认操作' },
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        teacherPresets: {
          type: 'array',
          description: '教师课位预设列表（如：张老师周三下午禁排）',
          items: {
            type: 'object',
            properties: {
              teacherId: { type: 'string' },
              scopeType: AGENT_SCHEMA_DEFS.ScopeType,
              scopeId: { type: 'string' },
              stageId: { type: 'string' },
              weekday: { type: 'integer', minimum: 1, maximum: 7 },
              periodTypeId: { type: 'string' },
              lessonIndex: { type: 'integer', minimum: 1 },
              weekMode: AGENT_SCHEMA_DEFS.WeekMode,
              value: AGENT_SCHEMA_DEFS.PresetValue,
            },
            required: [
              'teacherId',
              'scopeType',
              'scopeId',
              'stageId',
              'weekday',
              'periodTypeId',
              'lessonIndex',
              'weekMode',
              'value',
            ],
            additionalProperties: false,
          },
        },
        subjectPresets: {
          type: 'array',
          description: '科目课位预设列表（如：全校周一下午第3节必排班会）',
          items: {
            type: 'object',
            properties: {
              subjectId: { type: 'string' },
              scopeType: AGENT_SCHEMA_DEFS.ScopeType,
              scopeId: { type: 'string' },
              stageId: { type: 'string' },
              weekday: { type: 'integer', minimum: 1, maximum: 7 },
              periodTypeId: { type: 'string' },
              lessonIndex: { type: 'integer', minimum: 1 },
              value: AGENT_SCHEMA_DEFS.PresetValue,
            },
            required: [
              'subjectId',
              'scopeType',
              'scopeId',
              'stageId',
              'weekday',
              'periodTypeId',
              'lessonIndex',
              'value',
            ],
            additionalProperties: false,
          },
        },
        conditions: {
          type: 'array',
          description: '自定义硬性排课条件（对齐 ScheduleCondition）',
          items: {
            type: 'object',
            properties: {
              id: { type: 'string' },
              kind: {
                type: 'string',
                enum: [
                  'dailyLimit',
                  'periodLimit',
                  'teacherMutualExclusion',
                  'subjectMutualExclusion',
                  'forbiddenAdjacency',
                ],
                description:
                  '条件类型：单日节数限制、时段节数限制、教师互斥、科目同日互斥、禁止科目相邻',
              },
              name: { type: ['string', 'null'], description: '规则名称说明' },
              targetKind: { type: 'string', enum: ['teacher', 'subject'] },
              targetId: { type: 'string', description: '主目标教师 ID 或科目 ID' },
              otherId: {
                type: ['string', 'null'],
                description: '互斥或相邻的另一教师 ID 或科目 ID',
              },
              periodTypeId: { type: ['string', 'null'] },
              weekday: { type: ['integer', 'null'], minimum: 1, maximum: 7 },
              minCount: { type: ['integer', 'null'], minimum: 0 },
              maxCount: { type: ['integer', 'null'], minimum: 0 },
              exactCount: { type: ['integer', 'null'], minimum: 0 },
            },
            required: ['kind', 'targetKind', 'targetId'],
            additionalProperties: false,
          },
        },
        replaceAllConditions: {
          type: 'boolean',
          default: false,
          description: '若为 true，则使用 conditions 整体替换现有自定义条件；默认增量追加/按 id 更新',
        },
        preferences: {
          type: 'object',
          description: '全局排课偏好（对齐 SchedulePreferences）',
          properties: {
            strength: {
              type: 'string',
              enum: ['fast', 'normal', 'high'],
              description: '求解强度（对应 3000 / 12000 / 30000 次回溯搜索）',
            },
            progressConsistency: {
              type: 'string',
              enum: ['indifferent', 'prefer', 'require'],
              description: '同级同科进度一致性',
            },
            teacherDistribution: {
              type: 'string',
              enum: ['indifferent', 'spread', 'concentrate'],
              description: '教师课时分布（分散或集中）',
            },
            lunchProtection: {
              type: 'boolean',
              description: '午间休息保护（避免上午末节与下午首节连续上课）',
            },
            consecutivePolicy: {
              type: 'string',
              enum: ['preferSeparate', 'requireSeparate', 'preferTogether'],
              description: '同科连堂策略',
            },
            detectProgressConsistency: { type: 'boolean' },
          },
          additionalProperties: false,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_run_auto_schedule',
    module: 'scheduling',
    readOnly: false,
    description:
      '运行任课配额预检与自动排课求解器，生成草稿课表。支持选择班级、保留现有课位和预览结果。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        classIds: {
          type: 'array',
          items: { type: 'string' },
          description:
            '参与本次排课的班级 ID 列表；不传或为空数组时默认排当前学期全部班级（关联的合班课班级会自动纳入）',
        },
        retainPlacements: {
          type: 'boolean',
          default: true,
          description:
            '是否保留未锁定课节的现有落位（仅对未落位课节排课）；若为 false 则重排所选班级内未锁定的课节',
        },
        allowRearrangement: {
          type: 'boolean',
          default: true,
          description:
            '当存在未排入课节时，是否允许回溯挪动范围内未锁定且非必排的已落位课节（repairUnplaced）',
        },
        seed: {
          type: 'integer',
          default: 0,
          description: '随机扰动种子，用于生成不同风格的候选课表',
        },
        dryRun: {
          type: 'boolean',
          default: false,
          description:
            '若为 true，仅返回排课完成率、未排入课节的阻断原因(blockers)与规则诊断(issues)，不写入数据库',
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_move_or_swap_lesson',
    module: 'scheduling',
    readOnly: false,
    description:
      '移动、互换单个课节或将其移入暂放区（底层调用 previewPlacement 校验所有硬约束、合班同步与单双周配对）。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        sourceItemId: {
          type: 'string',
          description: '要移动的课节 ScheduleItem ID',
        },
        targetSlot: AGENT_SCHEMA_DEFS.NullableSchedulePosition,
        allowSwap: {
          type: 'boolean',
          default: true,
          description: '当目标位置已有课时，是否允许自动与目标位置的课程互换',
        },
        swapWithItemId: {
          type: 'string',
          description: '可选，显式指定要互换的目标 ScheduleItem ID',
        },
        dryRun: {
          type: 'boolean',
          default: false,
          description:
            '若为 true，仅返回 PlacementPreview (available / swap / caution / blocked) 及原因，不落库',
        },
      },
      required: ['sourceItemId', 'targetSlot'],
      additionalProperties: false,
    },
  },
  {
    name: 'classset_batch_create_supervision_posts',
    module: 'supervision',
    readOnly: false,
    description:
      '在带班安排草稿中批量创建带班岗位（支持早自习、课后服务、晚自习、自定义，支持多节次连续带班或跨班合班带班），并自动校验是否与正课或免任课冲突。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        kind: {
          type: 'string',
          enum: ['afterSchool', 'morningStudy', 'eveningStudy', 'custom'],
          description:
            '岗位类型：afterSchool(课后服务)、morningStudy(早自习)、eveningStudy(晚自习)、custom(自定义)',
        },
        name: {
          type: 'string',
          description: '活动名称（如：课后托管、早读看班）',
        },
        stageId: {
          type: 'string',
          description: '所属学段 ID（所选班级必须属于同一学段）',
        },
        classIds: {
          type: 'array',
          items: { type: 'string' },
          minItems: 1,
          description: '目标班级 ID 列表',
        },
        combineClasses: {
          type: 'boolean',
          default: false,
          description:
            '是否合班带班：false 为每个班级独立生成一个岗位；true 为所选班级合并为同一个合班岗位（须必填 groupName 和 location）',
        },
        groupName: {
          type: 'string',
          description: '合班带班时的组名（combineClasses=true 时必填）',
        },
        location: {
          type: 'string',
          description: '带班地点（combineClasses=true 时必填，如：阶梯教室）',
        },
        weekdays: {
          type: 'array',
          items: { type: 'integer', minimum: 1, maximum: 7 },
          minItems: 1,
          description: '适用星期列表（1~7）',
        },
        periodTypeId: {
          type: 'string',
          description: '作息时段 ID',
        },
        lessonIndices: {
          type: 'array',
          items: { type: 'integer', minimum: 1 },
          minItems: 1,
          description: '节次序号列表（如 [1, 2]）',
        },
        consecutiveLessons: {
          type: 'boolean',
          default: false,
          description:
            '是否连续带班：true 时将相邻的 lessonIndices 合并为同一岗位由同一位教师连带；false 时每节课拆分为独立岗位',
        },
        teacherPoolId: {
          type: ['string', 'null'],
          description: "指定候选教师池 ID；传 null 或 '__default__' 使用基础候选池",
        },
        targetSubjectIds: {
          type: 'array',
          items: { type: 'string' },
          description: '当匹配偏好启用 subjectTeacher（指定学科优先）时的目标学科 ID 列表',
        },
        dryRun: {
          type: 'boolean',
          default: false,
          description: '若为 true，仅返回将生成的岗位列表与 postErrors 校验结果，不保存草稿',
        },
      },
      required: [
        'kind',
        'name',
        'stageId',
        'classIds',
        'weekdays',
        'periodTypeId',
        'lessonIndices',
      ],
      additionalProperties: false,
    },
  },
  {
    name: 'classset_auto_allocate_supervision',
    module: 'supervision',
    readOnly: false,
    description:
      '对带班草稿执行自动分配教师（调用 SupervisionAllocator.fill），遵循任教班级优先/本年级优先/指定学科优先、匹配优先或均衡优先策略，并避开教师正课与禁排时段。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        matchingPreferences: {
          type: 'object',
          description: '可选，覆盖全局带班匹配偏好设置',
          properties: {
            order: {
              type: 'array',
              items: {
                type: 'string',
                enum: ['classTeacher', 'gradeTeacher', 'subjectTeacher'],
              },
              description: '优先级顺序',
            },
            enabled: {
              type: 'array',
              items: {
                type: 'string',
                enum: ['classTeacher', 'gradeTeacher', 'subjectTeacher'],
              },
              description: '启用的偏好项',
            },
            mode: {
              type: 'string',
              enum: ['matchFirst', 'balanceFirst'],
              description: 'matchFirst(匹配度优先) 或 balanceFirst(课时均衡优先)',
            },
            requirement: {
              type: 'string',
              enum: ['none', 'any', 'all'],
              description:
                '硬性符合要求：none(不强制)、any(符合任一启用项)、all(符合全部启用项)',
            },
          },
          additionalProperties: false,
        },
        teacherRules: {
          type: 'array',
          description: '可选，更新特定教师的每周带班上限或禁排时段',
          items: {
            type: 'object',
            properties: {
              teacherId: { type: 'string' },
              maxLessons: {
                type: ['integer', 'null'],
                minimum: 0,
                description: '每周最多带班节数',
              },
              maxDays: {
                type: ['integer', 'null'],
                minimum: 0,
                maximum: 7,
                description: '每周最多带班天数',
              },
              unavailable: {
                type: 'array',
                items: AGENT_SCHEMA_DEFS.SchedulePosition,
                description: '该教师禁排带班的节次坐标列表',
              },
            },
            required: ['teacherId'],
            additionalProperties: false,
          },
        },
        retainManualAssignments: {
          type: 'boolean',
          default: true,
          description: '是否保留已手动指定的岗位分配（manualPostIds）',
        },
        dryRun: {
          type: 'boolean',
          default: false,
          description: '若为 true，仅返回分配结果预览与未分配岗位列表，不落库',
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: 'classset_publish_supervision_version',
    module: 'supervision',
    readOnly: false,
    description:
      '校验当前带班草稿并按指定生效日期（YYYY-MM-DD）发布为正式带班方案版本（SupervisionVersion）。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        effectiveDate: {
          type: 'string',
          pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          description:
            '方案生效日期（YYYY-MM-DD），从该日起的实际日历带班将采用此版本',
        },
        dryRun: {
          type: 'boolean',
          default: false,
          description:
            '若为 true，仅返回 SupervisionPreview（包含 errors、未分配岗位 missingPostIds、变更摘要 scheduleChanges 与 canPublish），不正式发布',
        },
      },
      required: ['effectiveDate'],
      additionalProperties: false,
    },
  },
  {
    name: 'classset_query_actual_timetable',
    module: 'temporaryAdjustments',
    readOnly: true,
    description:
      '查询指定日期范围、班级或教师的实际日历课表与带班安排（已融合节假日调休、单双周及历史调代课记录），返回每个课次的唯一 sourceKey（格式为 `${itemId}:${originDate}`）及可选无冲突的代课教师/可对调课位。',
    inputSchema: {
      type: 'object',
      properties: {
        cursor: { type: 'string', description: '下一页游标。使用前一页返回的 nextCursor。' },
        pageSize: { type: 'integer', minimum: 1, maximum: 200, description: '每页条目数，默认 100。' },
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        startDate: {
          type: 'string',
          pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          description: '查询起始日期（YYYY-MM-DD，周一为每周起始）',
        },
        endDate: {
          type: 'string',
          pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          description: '查询结束日期（YYYY-MM-DD）',
        },
        classId: { type: 'string', description: '可选，按班级 ID 过滤' },
        teacherId: { type: 'string', description: '可选，按教师 ID 过滤' },
        findCandidatesForSourceKey: {
          type: 'string',
          description:
            '可选，传入某个具体课次的 key（`${itemId}:${originDate}`），引擎将自动计算并返回该课次在查询日期范围内所有无冲突的可移动空课位、可互换课次及可代课教师列表',
        },
      },
      required: ['startDate', 'endDate'],
      additionalProperties: false,
    },
  },
  {
    name: 'classset_apply_temporary_adjustment',
    module: 'temporaryAdjustments',
    readOnly: false,
    description:
      '执行或预览临时调代课操作，支持：1. 移课(move)；2. 正课代课(substitute)；3. 同班两节课互换(swap)；4. 带班临时替班(supervision-substitute)。支持单日或按日期区间(rangeStart~rangeEnd)批量调整。',
    inputSchema: {
      type: 'object',
      properties: {
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        kind: {
          type: 'string',
          enum: ['move', 'substitute', 'swap', 'supervision-substitute'],
          description:
            '调代课类型：move(移到空课位)、substitute(找老师代课/改科目)、swap(两节课互换)、supervision-substitute(带班替班)',
        },
        sourceKey: {
          type: 'string',
          description:
            '原课次唯一标识（格式 `${itemId}:${originDate}`，由 classset_query_actual_timetable 返回；kind 为 move / substitute / swap 时必填）',
        },
        targetDate: {
          type: 'string',
          pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          description:
            'kind=move 时的目标自然日（YYYY-MM-DD），或 kind=supervision-substitute 时的带班日期',
        },
        targetPosition: AGENT_SCHEMA_DEFS.SchedulePosition,
        substituteTeacherId: {
          type: 'string',
          description:
            'kind=substitute 或 supervision-substitute 时的代课/替班教师 ID',
        },
        substituteSubjectId: {
          type: ['string', 'null'],
          description: 'kind=substitute 时可选改上的科目 ID；不传则保持原科目不变',
        },
        secondKey: {
          type: 'string',
          description:
            'kind=swap 时要与之互换的同一班级另一课次 key（`${itemId}:${originDate}`）',
        },
        supervisionPostId: {
          type: 'string',
          description: 'kind=supervision-substitute 时的带班岗位 ID',
        },
        supervisionPositions: {
          type: 'array',
          items: AGENT_SCHEMA_DEFS.SchedulePosition,
          description: 'kind=supervision-substitute 时可选指定只替班其中部分节次',
        },
        rangeStart: {
          type: ['string', 'null'],
          pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          description: '可选，按周期批量调代课的起始日期（YYYY-MM-DD）',
        },
        rangeEnd: {
          type: ['string', 'null'],
          pattern: '^\\d{4}-\\d{2}-\\d{2}$',
          description: '可选，按周期批量调代课的结束日期（YYYY-MM-DD）',
        },
        excludedDates: {
          type: 'array',
          items: { type: 'string', pattern: '^\\d{4}-\\d{2}-\\d{2}$' },
          description: '批量调代课时需要跳过排除的自然日列表',
        },
        reason: {
          type: 'string',
          description: '调代课原因备注（如：张老师外出教研、运动会调课）',
        },
        dryRun: {
          type: 'boolean',
          default: false,
          description:
            '若为 true，仅调用 previewMove/previewSubstitute/previewSwap/previewSupervisionSubstitute 返回变更预览与冲突错误，不写入 temporary_course_adjustments 表',
        },
      },
      required: ['kind'],
      additionalProperties: false,
    },
  },
  {
    name: 'classset_cancel_temporary_adjustment',
    module: 'temporaryAdjustments',
    readOnly: false,
    description:
      '撤销一条已生效的调代课或带班替班记录（自动调用 validateTemporaryCancellation 校验是否存在后续依赖调整或恢复冲突）。',
    inputSchema: {
      type: 'object',
      properties: {
        dryRun: { type: 'boolean', description: '只生成预览，不创建待确认操作' },
        termId: {
          type: 'string',
          description: '可选，目标学期 ID；不传默认使用当前激活学期',
        },
        recordId: {
          type: 'string',
          description: '要撤销的调代课记录 ID（TemporaryCourseAdjustment.id）',
        },
      },
      required: ['recordId'],
      additionalProperties: false,
    },
  },
] as const;

export function getAgentToolSchema(
  name: ClassSetAgentToolName
): ClassSetAgentToolSchema {
  const found = CLASSSET_AGENT_TOOL_SCHEMAS.find((tool) => tool.name === name);
  if (!found) {
    throw new Error(`未知的课集 AI Agent 工具：${name}`);
  }
  return found;
}
