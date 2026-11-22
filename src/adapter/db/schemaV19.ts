/**
 * 课集 (ClassSet) Schema v19 完整 SQL 建表定义
 * 供 Web 端 (SQLite Wasm) 与 Tauri 桌面端共同校验与初始化 29 张核心表与 7 个索引。
 */

export const SCHEMA_VERSION = 19;

export const SCHEMA_V19_TABLES = [
  'academic_terms',
  'app_settings',
  'school_stages',
  'grade_groups',
  'class_groups',
  'stage_teaching_days',
  'lesson_period_types',
  'daily_lesson_overrides',
  'lesson_times',
  'calendar_exceptions',
  'free_slots',
  'common_periods',
  'subjects',
  'subject_requirements',
  'subject_presets',
  'subject_pairings',
  'subject_lesson_constraints',
  'public_rooms',
  'subject_room_assignments',
  'subject_parallel_limits',
  'teachers',
  'teacher_subject_tags',
  'teacher_groups',
  'teacher_group_members',
  'teacher_assignments',
  'teacher_presets',
  'teacher_group_presets',
  'schedule_items',
  'schedule_locks',
  'schedule_conditions',
  'schedule_preferences',
  'schedule_run_reports',
  'schedule_reconciliation_baselines',
  'published_schedules',
  'temporary_course_adjustments',
  'supervision_drafts',
  'supervision_plan_versions',
] as const;

export const SCHEMA_V19_DDL = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS academic_terms (
  id TEXT NOT NULL PRIMARY KEY,
  title TEXT NOT NULL,
  academic_year TEXT NOT NULL,
  semester_label TEXT NOT NULL,
  first_teaching_week_start TEXT,
  teaching_week_count INTEGER NOT NULL DEFAULT 20,
  cycle_mode TEXT NOT NULL DEFAULT 'alternating',
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS app_settings (
  id INTEGER NOT NULL PRIMARY KEY,
  school_name TEXT NOT NULL DEFAULT '',
  active_term_id TEXT REFERENCES academic_terms(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS school_stages (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS grade_groups (
  id TEXT NOT NULL PRIMARY KEY,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS class_groups (
  id TEXT NOT NULL PRIMARY KEY,
  grade_id TEXT NOT NULL REFERENCES grade_groups(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS stage_teaching_days (
  id TEXT NOT NULL PRIMARY KEY,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL,
  is_teaching_day INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS lesson_period_types (
  id TEXT NOT NULL PRIMARY KEY,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  default_lesson_count INTEGER NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS daily_lesson_overrides (
  id TEXT NOT NULL PRIMARY KEY,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  period_type_id TEXT NOT NULL REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL,
  lesson_count INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS lesson_times (
  id TEXT NOT NULL PRIMARY KEY,
  period_type_id TEXT NOT NULL REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  lesson_index INTEGER NOT NULL,
  label TEXT NOT NULL,
  start_minute INTEGER,
  end_minute INTEGER
);

CREATE TABLE IF NOT EXISTS calendar_exceptions (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  date TEXT NOT NULL,
  kind TEXT NOT NULL,
  makeup_weekday INTEGER,
  makeup_for_date TEXT,
  note TEXT NOT NULL DEFAULT ''
);

CREATE TABLE IF NOT EXISTS subjects (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT REFERENCES academic_terms(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  short_name TEXT NOT NULL,
  sort_order INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS subject_requirements (
  id TEXT NOT NULL PRIMARY KEY,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  grade_id TEXT NOT NULL REFERENCES grade_groups(id) ON DELETE CASCADE,
  class_id TEXT REFERENCES class_groups(id) ON DELETE CASCADE,
  week_mode TEXT NOT NULL DEFAULT 'weekly',
  lesson_count INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS subject_presets (
  id TEXT NOT NULL PRIMARY KEY,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL,
  period_type_id TEXT NOT NULL REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  lesson_index INTEGER NOT NULL,
  value TEXT NOT NULL DEFAULT 'auto'
);

CREATE TABLE IF NOT EXISTS subject_pairings (
  id TEXT NOT NULL PRIMARY KEY,
  class_id TEXT NOT NULL REFERENCES class_groups(id) ON DELETE CASCADE,
  odd_subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  even_subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS subject_lesson_constraints (
  id TEXT NOT NULL PRIMARY KEY,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  weekday INTEGER,
  minimum_daily_lessons INTEGER,
  maximum_daily_lessons INTEGER,
  minimum_daily_consecutive_pairs INTEGER,
  maximum_daily_consecutive_pairs INTEGER,
  minimum_weekly_consecutive_pairs INTEGER,
  maximum_weekly_consecutive_pairs INTEGER,
  UNIQUE (subject_id, scope_type, scope_id, stage_id, weekday)
);

CREATE TABLE IF NOT EXISTS free_slots (
  id TEXT NOT NULL PRIMARY KEY,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  period_type_id TEXT NOT NULL REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL,
  lesson_index INTEGER NOT NULL,
  label TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS common_periods (
  id TEXT NOT NULL PRIMARY KEY,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  insert_after_lesson_id TEXT,
  duration_minutes INTEGER NOT NULL DEFAULT 10,
  sort_order INTEGER NOT NULL DEFAULT 0,
  start_minute INTEGER,
  end_minute INTEGER
);

CREATE TABLE IF NOT EXISTS public_rooms (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  room_count INTEGER NOT NULL,
  capacity_per_room INTEGER NOT NULL,
  sort_order INTEGER NOT NULL,
  CHECK (room_count > 0),
  CHECK (capacity_per_room > 0)
);

CREATE TABLE IF NOT EXISTS subject_room_assignments (
  id TEXT NOT NULL PRIMARY KEY,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  room_id TEXT REFERENCES public_rooms(id) ON DELETE CASCADE,
  UNIQUE (subject_id, term_id, scope_type, scope_id)
);

CREATE TABLE IF NOT EXISTS subject_parallel_limits (
  id TEXT NOT NULL PRIMARY KEY,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  max_parallel_lessons INTEGER NOT NULL,
  CHECK (max_parallel_lessons > 0),
  UNIQUE (subject_id, term_id, scope_type, scope_id)
);

CREATE TABLE IF NOT EXISTS teachers (
  id TEXT NOT NULL PRIMARY KEY,
  name TEXT NOT NULL,
  short_name TEXT NOT NULL DEFAULT '',
  display_qualifier TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS teacher_subject_tags (
  teacher_id TEXT NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  PRIMARY KEY (teacher_id, subject_id)
);

CREATE TABLE IF NOT EXISTS teacher_groups (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT NOT NULL DEFAULT '',
  sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS teacher_group_members (
  group_id TEXT NOT NULL REFERENCES teacher_groups(id) ON DELETE CASCADE,
  teacher_id TEXT NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  PRIMARY KEY (group_id, teacher_id)
);

CREATE TABLE IF NOT EXISTS teacher_assignments (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  teacher_id TEXT REFERENCES teachers(id) ON DELETE SET NULL,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  class_id TEXT NOT NULL REFERENCES class_groups(id) ON DELETE CASCADE,
  week_mode TEXT NOT NULL DEFAULT 'weekly',
  lesson_count INTEGER NOT NULL DEFAULT 0,
  sort_order INTEGER NOT NULL DEFAULT 0,
  combined_lesson_group_id TEXT
);

CREATE TABLE IF NOT EXISTS teacher_presets (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  teacher_id TEXT NOT NULL REFERENCES teachers(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL,
  period_type_id TEXT NOT NULL REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  lesson_index INTEGER NOT NULL,
  week_mode TEXT NOT NULL DEFAULT 'weekly',
  value TEXT NOT NULL DEFAULT 'auto',
  UNIQUE (term_id, teacher_id, scope_type, scope_id, stage_id, weekday, period_type_id, lesson_index)
);

CREATE TABLE IF NOT EXISTS teacher_group_presets (
  id TEXT NOT NULL PRIMARY KEY,
  group_id TEXT NOT NULL REFERENCES teacher_groups(id) ON DELETE CASCADE,
  scope_type TEXT NOT NULL,
  scope_id TEXT NOT NULL,
  stage_id TEXT NOT NULL REFERENCES school_stages(id) ON DELETE CASCADE,
  weekday INTEGER NOT NULL,
  period_type_id TEXT NOT NULL REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  lesson_index INTEGER NOT NULL,
  week_mode TEXT NOT NULL DEFAULT 'weekly',
  value TEXT NOT NULL DEFAULT 'auto',
  UNIQUE (group_id, scope_type, scope_id, stage_id, weekday, period_type_id, lesson_index)
);

CREATE TABLE IF NOT EXISTS schedule_items (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  assignment_id TEXT NOT NULL REFERENCES teacher_assignments(id) ON DELETE CASCADE,
  class_id TEXT NOT NULL REFERENCES class_groups(id) ON DELETE CASCADE,
  teacher_id TEXT REFERENCES teachers(id) ON DELETE SET NULL,
  subject_id TEXT NOT NULL REFERENCES subjects(id) ON DELETE CASCADE,
  week_mode TEXT NOT NULL DEFAULT 'weekly',
  combined_group_id TEXT,
  meeting_id TEXT,
  stage_id TEXT REFERENCES school_stages(id) ON DELETE CASCADE,
  weekday INTEGER,
  period_type_id TEXT REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  lesson_index INTEGER
);

CREATE INDEX IF NOT EXISTS schedule_items_term ON schedule_items (term_id);
CREATE INDEX IF NOT EXISTS schedule_items_assignment ON schedule_items (assignment_id);
CREATE INDEX IF NOT EXISTS schedule_items_class_slot ON schedule_items (term_id, class_id, week_mode, weekday, period_type_id, lesson_index);
CREATE INDEX IF NOT EXISTS schedule_items_teacher_slot ON schedule_items (term_id, teacher_id, week_mode, weekday, period_type_id, lesson_index);

CREATE TABLE IF NOT EXISTS schedule_locks (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  scope TEXT NOT NULL,
  target_id TEXT NOT NULL
);

CREATE UNIQUE INDEX IF NOT EXISTS schedule_locks_target ON schedule_locks (term_id, scope, target_id);

CREATE TABLE IF NOT EXISTS schedule_conditions (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  name TEXT,
  target_kind TEXT,
  target_id TEXT,
  other_id TEXT,
  period_type_id TEXT REFERENCES lesson_period_types(id) ON DELETE CASCADE,
  weekday INTEGER,
  min_count INTEGER,
  max_count INTEGER,
  exact_count INTEGER
);

CREATE INDEX IF NOT EXISTS schedule_conditions_target ON schedule_conditions (term_id, target_kind, target_id);

CREATE TABLE IF NOT EXISTS schedule_preferences (
  term_id TEXT NOT NULL PRIMARY KEY REFERENCES academic_terms(id) ON DELETE CASCADE,
  strength TEXT NOT NULL,
  progress_consistency TEXT NOT NULL,
  teacher_distribution TEXT NOT NULL,
  lunch_protection INTEGER NOT NULL,
  consecutive_policy TEXT NOT NULL,
  detect_progress_consistency INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS schedule_run_reports (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  solver_version TEXT NOT NULL,
  seed INTEGER NOT NULL,
  strength TEXT NOT NULL,
  input_fingerprint TEXT NOT NULL,
  report_json TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS schedule_run_reports_term_created ON schedule_run_reports (term_id, created_at);

CREATE TABLE IF NOT EXISTS schedule_reconciliation_baselines (
  term_id TEXT NOT NULL PRIMARY KEY REFERENCES academic_terms(id) ON DELETE CASCADE,
  snapshot_json TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS published_schedules (
  term_id TEXT NOT NULL PRIMARY KEY REFERENCES academic_terms(id) ON DELETE CASCADE,
  data_json TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS temporary_course_adjustments (
  id TEXT NOT NULL PRIMARY KEY,
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  kind TEXT NOT NULL,
  changes_json TEXT NOT NULL,
  reason TEXT NOT NULL DEFAULT '',
  created_at INTEGER NOT NULL,
  cancelled_at INTEGER
);

CREATE TABLE IF NOT EXISTS supervision_drafts (
  term_id TEXT NOT NULL PRIMARY KEY REFERENCES academic_terms(id) ON DELETE CASCADE,
  payload TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS supervision_plan_versions (
  term_id TEXT NOT NULL REFERENCES academic_terms(id) ON DELETE CASCADE,
  effective_date TEXT NOT NULL,
  payload TEXT NOT NULL,
  PRIMARY KEY (term_id, effective_date)
);
`;
