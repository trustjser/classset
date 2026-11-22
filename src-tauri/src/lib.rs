use tauri_plugin_sql::{Migration, MigrationKind};

mod sqlite_transactions;

/// Schema v19 完整建表与索引 SQL，100% 兼容原 Flutter Drift school.sqlite。
pub const SCHEMA_V19_SQL: &str = include_str!("../migrations/001_schema_v19.sql");

#[tauri::command]
fn get_schema_version() -> u32 {
    19
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let migrations = vec![Migration {
        version: 19,
        description: "init_classset_schema_v19",
        sql: SCHEMA_V19_SQL,
        kind: MigrationKind::Up,
    }];

    tauri::Builder::default()
        .manage(sqlite_transactions::SqliteTransactions::default())
        .plugin(
            tauri_plugin_sql::Builder::default()
                .add_migrations("sqlite:school.sqlite", migrations)
                .build(),
        )
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .invoke_handler(tauri::generate_handler![
            get_schema_version,
            sqlite_transactions::begin_sqlite_transaction,
            sqlite_transactions::select_sqlite_transaction,
            sqlite_transactions::execute_sqlite_transaction,
            sqlite_transactions::commit_sqlite_transaction,
            sqlite_transactions::rollback_sqlite_transaction,
        ])
        .run(tauri::generate_context!())
        .expect("运行课集 Tauri 应用失败");
}
