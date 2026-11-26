use tauri::Manager;
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
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![
            get_schema_version,
            sqlite_transactions::begin_sqlite_transaction,
            sqlite_transactions::select_sqlite_transaction,
            sqlite_transactions::execute_sqlite_transaction,
            sqlite_transactions::commit_sqlite_transaction,
            sqlite_transactions::rollback_sqlite_transaction,
        ])
        .build(tauri::generate_context!())
        .expect("运行课集 Tauri 应用失败")
        .run(|app_handle, event| {
            #[cfg(target_os = "macos")]
            if let tauri::RunEvent::Reopen {
                has_visible_windows,
                ..
            } = event
            {
                if !has_visible_windows {
                    if let Some(window) = app_handle
                        .get_webview_window("main")
                        .or_else(|| app_handle.webview_windows().values().next().cloned())
                    {
                        let _ = window.show();
                        let _ = window.set_focus();
                    }
                }
            }
            #[cfg(not(target_os = "macos"))]
            let _ = (app_handle, event);
        });
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::sqlite::SqlitePoolOptions;

    #[test]
    fn schema_version_is_19_and_sql_initializes_cleanly() {
        assert_eq!(get_schema_version(), 19);
        assert!(!SCHEMA_V19_SQL.trim().is_empty());

        tauri::async_runtime::block_on(async {
            let pool = SqlitePoolOptions::new()
                .max_connections(1)
                .connect("sqlite::memory:")
                .await
                .unwrap();

            sqlx::raw_sql(SCHEMA_V19_SQL).execute(&pool).await.unwrap();

            let table_count: i64 = sqlx::query_scalar(
                "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('academic_terms', 'school_stages', 'grade_groups', 'class_groups', 'subjects', 'teachers')",
            )
            .fetch_one(&pool)
            .await
            .unwrap();
            assert_eq!(table_count, 6);
        });
    }
}
