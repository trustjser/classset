use sqlx::{Pool, Sqlite};
use tauri::{ipc::Response, State};
use tauri_plugin_sql::{DbInstances, DbPool};

pub async fn export_snapshot(pool: &Pool<Sqlite>) -> Result<Vec<u8>, String> {
    let directory = tempfile::tempdir().map_err(|error| error.to_string())?;
    let path = directory.path().join("classset-backup.sqlite");
    let filename = path.to_str().ok_or("无法创建备份临时文件")?;

    // SQLite takes a consistent snapshot, including committed WAL contents.
    sqlx::query("VACUUM main INTO ?")
        .bind(filename)
        .execute(pool)
        .await
        .map_err(|error| error.to_string())?;
    std::fs::read(path).map_err(|error| error.to_string())
}

#[tauri::command]
pub async fn export_sqlite_snapshot(instances: State<'_, DbInstances>) -> Result<Response, String> {
    let pool = {
        let guard = instances.0.read().await;
        match guard.get("sqlite:school.sqlite") {
            Some(DbPool::Sqlite(pool)) => pool.clone(),
            _ => return Err("学校数据库尚未加载".into()),
        }
    };
    export_snapshot(&pool).await.map(Response::new)
}
