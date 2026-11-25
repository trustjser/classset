use serde_json::{Map, Value};
use sqlx::{
    query::Query,
    sqlite::{SqliteArguments, SqliteRow},
    Column, Pool, Row, Sqlite, TypeInfo, ValueRef,
};
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicU64, Ordering},
        Arc,
    },
};
use tauri::State;
use tauri_plugin_sql::{DbInstances, DbPool};
use tokio::sync::Mutex;

type Session = Arc<Mutex<Option<sqlx::Transaction<'static, Sqlite>>>>;

#[derive(Default)]
pub struct SqliteTransactions {
    next_id: AtomicU64,
    sessions: Mutex<HashMap<u64, Session>>,
}

fn bind_query<'q>(
    sql: &'q str,
    values: Vec<Value>,
) -> Result<Query<'q, Sqlite, SqliteArguments<'q>>, String> {
    let mut query = sqlx::query(sql);
    for value in values {
        query = match value {
            Value::Null => query.bind(None::<String>),
            Value::Bool(value) => query.bind(value),
            Value::String(value) => query.bind(value),
            Value::Number(value) => {
                if let Some(integer) = value.as_i64() {
                    query.bind(integer)
                } else if let Some(decimal) = value.as_f64() {
                    query.bind(decimal)
                } else {
                    return Err("SQLite 数字参数超出范围".into());
                }
            }
            Value::Array(values) => {
                let bytes = values
                    .into_iter()
                    .map(|value| value.as_u64().and_then(|value| u8::try_from(value).ok()))
                    .collect::<Option<Vec<_>>>()
                    .ok_or("SQLite 二进制参数必须是字节数组")?;
                query.bind(bytes)
            }
            Value::Object(_) => return Err("SQLite 不支持对象参数".into()),
        };
    }
    Ok(query)
}

fn json_row(row: SqliteRow) -> Result<Map<String, Value>, String> {
    let mut result = Map::new();
    for (index, column) in row.columns().iter().enumerate() {
        let raw = row.try_get_raw(index).map_err(|error| error.to_string())?;
        let value = if raw.is_null() {
            Value::Null
        } else {
            match raw.type_info().name() {
                "TEXT" | "DATE" | "TIME" | "DATETIME" => row
                    .try_get::<String, _>(index)
                    .map(Value::String)
                    .map_err(|error| error.to_string())?,
                "INTEGER" | "NUMERIC" => row
                    .try_get::<i64, _>(index)
                    .map(Value::from)
                    .map_err(|error| error.to_string())?,
                "REAL" => row
                    .try_get::<f64, _>(index)
                    .map(Value::from)
                    .map_err(|error| error.to_string())?,
                "BOOLEAN" => row
                    .try_get::<bool, _>(index)
                    .map(Value::from)
                    .map_err(|error| error.to_string())?,
                "BLOB" => row
                    .try_get::<Vec<u8>, _>(index)
                    .map(|bytes| Value::Array(bytes.into_iter().map(Value::from).collect()))
                    .map_err(|error| error.to_string())?,
                kind => return Err(format!("不支持的 SQLite 字段类型：{kind}")),
            }
        };
        result.insert(column.name().to_owned(), value);
    }
    Ok(result)
}

impl SqliteTransactions {
    async fn begin(&self, pool: &Pool<Sqlite>) -> Result<u64, String> {
        let transaction = pool.begin().await.map_err(|error| error.to_string())?;
        let id = self.next_id.fetch_add(1, Ordering::Relaxed) + 1;
        self.sessions
            .lock()
            .await
            .insert(id, Arc::new(Mutex::new(Some(transaction))));
        Ok(id)
    }

    async fn session(&self, id: u64) -> Result<Session, String> {
        self.sessions
            .lock()
            .await
            .get(&id)
            .cloned()
            .ok_or_else(|| format!("SQLite 事务 {id} 已结束"))
    }

    async fn execute(
        &self,
        id: u64,
        sql: String,
        values: Vec<Value>,
    ) -> Result<Map<String, Value>, String> {
        let session = self.session(id).await?;
        let mut guard = session.lock().await;
        let transaction = guard.as_mut().ok_or("SQLite 事务已结束")?;
        let result = bind_query(&sql, values)?
            .execute(&mut **transaction)
            .await
            .map_err(|error| error.to_string())?;
        let mut output = Map::new();
        output.insert("rowsAffected".into(), Value::from(result.rows_affected()));
        output.insert(
            "lastInsertId".into(),
            Value::from(result.last_insert_rowid()),
        );
        Ok(output)
    }

    async fn select(
        &self,
        id: u64,
        sql: String,
        values: Vec<Value>,
    ) -> Result<Vec<Map<String, Value>>, String> {
        let session = self.session(id).await?;
        let mut guard = session.lock().await;
        let transaction = guard.as_mut().ok_or("SQLite 事务已结束")?;
        bind_query(&sql, values)?
            .fetch_all(&mut **transaction)
            .await
            .map_err(|error| error.to_string())?
            .into_iter()
            .map(json_row)
            .collect()
    }

    async fn finish(&self, id: u64, commit: bool) -> Result<(), String> {
        let session = self
            .sessions
            .lock()
            .await
            .remove(&id)
            .ok_or_else(|| format!("SQLite 事务 {id} 已结束"))?;
        let transaction = session.lock().await.take().ok_or("SQLite 事务已结束")?;
        if commit {
            transaction.commit().await
        } else {
            transaction.rollback().await
        }
        .map_err(|error| error.to_string())
    }
}

#[tauri::command]
pub async fn begin_sqlite_transaction(
    instances: State<'_, DbInstances>,
    transactions: State<'_, SqliteTransactions>,
) -> Result<u64, String> {
    let pool = {
        let guard = instances.0.read().await;
        match guard.get("sqlite:school.sqlite") {
            Some(DbPool::Sqlite(pool)) => pool.clone(),
            _ => return Err("学校数据库尚未加载".into()),
        }
    };
    transactions.begin(&pool).await
}

#[tauri::command]
pub async fn select_sqlite_transaction(
    transactions: State<'_, SqliteTransactions>,
    id: u64,
    sql: String,
    values: Vec<Value>,
) -> Result<Vec<Map<String, Value>>, String> {
    transactions.select(id, sql, values).await
}

#[tauri::command]
pub async fn execute_sqlite_transaction(
    transactions: State<'_, SqliteTransactions>,
    id: u64,
    sql: String,
    values: Vec<Value>,
) -> Result<Map<String, Value>, String> {
    transactions.execute(id, sql, values).await
}

#[tauri::command]
pub async fn commit_sqlite_transaction(
    transactions: State<'_, SqliteTransactions>,
    id: u64,
) -> Result<(), String> {
    transactions.finish(id, true).await
}

#[tauri::command]
pub async fn rollback_sqlite_transaction(
    transactions: State<'_, SqliteTransactions>,
    id: u64,
) -> Result<(), String> {
    transactions.finish(id, false).await
}

#[cfg(test)]
mod tests {
    use super::*;
    use sqlx::sqlite::SqlitePoolOptions;

    #[test]
    fn grade_reorder_commits_on_one_connection_and_rollback_discards_changes() {
        tauri::async_runtime::block_on(async {
            let pool = SqlitePoolOptions::new()
                .max_connections(2)
                .connect("sqlite::memory:")
                .await
                .unwrap();
            sqlx::query(
                "CREATE TABLE grade_groups (id TEXT PRIMARY KEY, sort_order INTEGER NOT NULL)",
            )
            .execute(&pool)
            .await
            .unwrap();
            sqlx::query("INSERT INTO grade_groups VALUES ('a', 0), ('b', 1)")
                .execute(&pool)
                .await
                .unwrap();
            let transactions = SqliteTransactions::default();
            let id = transactions.begin(&pool).await.unwrap();
            transactions
                .execute(
                    id,
                    "UPDATE grade_groups SET sort_order = ? WHERE id = ?".into(),
                    vec![Value::from(1), Value::from("a")],
                )
                .await
                .unwrap();
            transactions
                .execute(
                    id,
                    "UPDATE grade_groups SET sort_order = ? WHERE id = ?".into(),
                    vec![Value::from(0), Value::from("b")],
                )
                .await
                .unwrap();
            let rows = transactions
                .select(
                    id,
                    "SELECT id, sort_order FROM grade_groups ORDER BY sort_order".into(),
                    vec![],
                )
                .await
                .unwrap();
            assert_eq!(rows[0].get("id"), Some(&Value::from("b")));
            transactions.finish(id, true).await.unwrap();
            let order: Vec<String> =
                sqlx::query_scalar("SELECT id FROM grade_groups ORDER BY sort_order")
                    .fetch_all(&pool)
                    .await
                    .unwrap();
            assert_eq!(order, vec!["b", "a"]);

            let id = transactions.begin(&pool).await.unwrap();
            transactions
                .execute(
                    id,
                    "UPDATE grade_groups SET sort_order = 9 WHERE id = 'a'".into(),
                    vec![],
                )
                .await
                .unwrap();
            transactions.finish(id, false).await.unwrap();
            let order: Vec<i64> =
                sqlx::query_scalar("SELECT sort_order FROM grade_groups ORDER BY id")
                    .fetch_all(&pool)
                    .await
                    .unwrap();
            assert_eq!(order, vec![1, 0]);
        });
    }

    #[test]
    fn bind_and_select_support_all_sqlite_types_and_reject_invalid_params() {
        tauri::async_runtime::block_on(async {
            let pool = SqlitePoolOptions::new()
                .max_connections(1)
                .connect("sqlite::memory:")
                .await
                .unwrap();
            sqlx::query(
                "CREATE TABLE typed_rows (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    txt TEXT,
                    num INTEGER,
                    flt REAL,
                    flag BOOLEAN,
                    raw BLOB
                )",
            )
            .execute(&pool)
            .await
            .unwrap();

            let transactions = SqliteTransactions::default();
            let id = transactions.begin(&pool).await.unwrap();

            let insert_res = transactions
                .execute(
                    id,
                    "INSERT INTO typed_rows (txt, num, flt, flag, raw) VALUES (?, ?, ?, ?, ?)"
                        .into(),
                    vec![
                        Value::from("课集"),
                        Value::from(42),
                        Value::from(3.5),
                        Value::from(true),
                        Value::Array(vec![Value::from(1), Value::from(255)]),
                    ],
                )
                .await
                .unwrap();
            assert_eq!(insert_res.get("rowsAffected"), Some(&Value::from(1)));
            assert_eq!(insert_res.get("lastInsertId"), Some(&Value::from(1)));

            transactions
                .execute(
                    id,
                    "INSERT INTO typed_rows (txt, num, flt, flag, raw) VALUES (?, ?, ?, ?, ?)"
                        .into(),
                    vec![Value::Null, Value::Null, Value::Null, Value::Null, Value::Null],
                )
                .await
                .unwrap();

            let rows = transactions
                .select(
                    id,
                    "SELECT txt, num, flt, flag, raw FROM typed_rows ORDER BY id".into(),
                    vec![],
                )
                .await
                .unwrap();
            assert_eq!(rows.len(), 2);
            assert_eq!(rows[0].get("txt"), Some(&Value::from("课集")));
            assert_eq!(rows[0].get("num"), Some(&Value::from(42)));
            assert_eq!(rows[0].get("flt"), Some(&Value::from(3.5)));
            assert_eq!(rows[0].get("flag"), Some(&Value::from(1)));
            assert_eq!(
                rows[0].get("raw"),
                Some(&Value::Array(vec![Value::from(1), Value::from(255)]))
            );
            assert_eq!(rows[1].get("txt"), Some(&Value::Null));

            let obj_err = transactions
                .execute(id, "SELECT ?".into(), vec![Value::Object(Map::new())])
                .await
                .unwrap_err();
            assert_eq!(obj_err, "SQLite 不支持对象参数");

            let blob_err = transactions
                .execute(
                    id,
                    "SELECT ?".into(),
                    vec![Value::Array(vec![Value::from(256)])],
                )
                .await
                .unwrap_err();
            assert_eq!(blob_err, "SQLite 二进制参数必须是字节数组");

            transactions.finish(id, true).await.unwrap();
        });
    }

    #[test]
    fn ended_or_missing_transaction_returns_error() {
        tauri::async_runtime::block_on(async {
            let pool = SqlitePoolOptions::new()
                .max_connections(1)
                .connect("sqlite::memory:")
                .await
                .unwrap();
            let transactions = SqliteTransactions::default();

            let missing_err = transactions
                .select(999, "SELECT 1".into(), vec![])
                .await
                .unwrap_err();
            assert!(missing_err.contains("已结束"));

            let id = transactions.begin(&pool).await.unwrap();
            transactions.finish(id, false).await.unwrap();

            let after_rollback = transactions
                .execute(id, "SELECT 1".into(), vec![])
                .await
                .unwrap_err();
            assert!(after_rollback.contains("已结束"));

            let double_finish = transactions.finish(id, true).await.unwrap_err();
            assert!(double_finish.contains("已结束"));
        });
    }
}
