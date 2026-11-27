use axum::{
    extract::Request,
    http::{header, HeaderMap, StatusCode},
    middleware::{self, Next},
    response::IntoResponse,
    Router,
};
use rmcp::{
    model::{
        CallToolRequestParams, CallToolResult, ListToolsResult, PaginatedRequestParams,
        ServerCapabilities, ServerInfo, Tool,
    },
    service::RequestContext,
    transport::streamable_http_server::{
        session::local::LocalSessionManager, StreamableHttpServerConfig, StreamableHttpService,
    },
    ErrorData, RoleServer, ServerHandler,
};
use serde::Serialize;
use serde_json::{json, Value};
use std::{
    collections::HashMap,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};
use tauri::{ipc::Channel, State, WebviewWindow};
use tokio::{net::TcpListener, sync::oneshot};
use tower_http::limit::RequestBodyLimitLayer;
use uuid::Uuid;

type Pending = Arc<Mutex<HashMap<Uuid, oneshot::Sender<Value>>>>;

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct AgentCall {
    request_id: String,
    name: String,
    arguments: Value,
}

#[derive(Clone)]
struct ClassSetMcp {
    window: WebviewWindow,
    channel: Channel<AgentCall>,
    tools: Arc<Vec<Tool>>,
    pending: Pending,
}

fn tool_error(code: &str, message: &str) -> CallToolResult {
    CallToolResult::structured_error(json!({ "status": "error", "code": code, "message": message }))
}

struct PendingCall {
    id: Uuid,
    pending: Pending,
}

impl Drop for PendingCall {
    fn drop(&mut self) {
        if let Ok(mut pending) = self.pending.lock() {
            pending.remove(&self.id);
        }
    }
}

impl ServerHandler for ClassSetMcp {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            ..Default::default()
        }
    }

    async fn list_tools(
        &self,
        _: Option<PaginatedRequestParams>,
        _: RequestContext<RoleServer>,
    ) -> Result<ListToolsResult, ErrorData> {
        Ok(ListToolsResult {
            tools: self.tools.as_ref().clone(),
            ..Default::default()
        })
    }

    async fn call_tool(
        &self,
        request: CallToolRequestParams,
        context: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        if !self.window.is_visible().unwrap_or(false) {
            return Ok(tool_error("NOT_READY", "请打开课集主窗口后重试"));
        }
        if !self.tools.iter().any(|tool| tool.name == request.name) {
            return Ok(tool_error("INVALID_ARGUMENT", "工具不可用"));
        }
        let id = Uuid::new_v4();
        let (sender, receiver) = oneshot::channel();
        {
            let mut pending = self
                .pending
                .lock()
                .map_err(|_| ErrorData::internal_error("课集暂不可用", None))?;
            if pending.len() >= 8 {
                return Ok(tool_error("BUSY", "课集正在处理其他查询，请稍后重试"));
            }
            pending.insert(id, sender);
        }
        let _call = PendingCall {
            id,
            pending: self.pending.clone(),
        };
        if self
            .channel
            .send(AgentCall {
                request_id: id.to_string(),
                name: request.name.into_owned(),
                arguments: Value::Object(request.arguments.unwrap_or_default()),
            })
            .is_err()
        {
            return Ok(tool_error("NOT_READY", "课集主窗口尚未连接"));
        }

        let response = tokio::select! {
            _ = context.ct.cancelled() => return Ok(tool_error("CANCELLED", "查询已取消")),
            response = tokio::time::timeout(Duration::from_secs(30), receiver) => response,
        };
        Ok(match response {
            Ok(Ok(value)) if value.get("status").and_then(Value::as_str) == Some("error") => {
                CallToolResult::structured_error(value)
            }
            Ok(Ok(value)) => CallToolResult::structured(value),
            _ => tool_error("NOT_READY", "未收到课集响应，请检查连接后重试"),
        })
    }
}

struct Running {
    task: tauri::async_runtime::JoinHandle<()>,
    pending: Pending,
    revoked: Arc<AtomicBool>,
}

impl Drop for Running {
    fn drop(&mut self) {
        self.revoked.store(true, Ordering::Release);
        self.task.abort();
        if let Ok(mut pending) = self.pending.lock() {
            pending.clear();
        }
    }
}

#[derive(Default)]
pub struct AgentMcpState(Mutex<Option<Running>>);

#[derive(Serialize)]
pub struct Connection {
    url: String,
    token: String,
}

fn require_main(window: &WebviewWindow) -> Result<(), String> {
    if window.label() == "main" {
        Ok(())
    } else {
        Err("只能从课集主窗口配置 Agent".into())
    }
}

fn verify_request(
    headers: &HeaderMap,
    authority: &str,
    authorization: &str,
) -> Result<(), StatusCode> {
    if headers
        .get(header::HOST)
        .and_then(|value| value.to_str().ok())
        != Some(authority)
        || headers.contains_key(header::ORIGIN)
    {
        return Err(StatusCode::FORBIDDEN);
    }
    if headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        != Some(authorization)
    {
        return Err(StatusCode::UNAUTHORIZED);
    }
    Ok(())
}

fn mcp_router<H>(
    handler: H,
    authority: String,
    authorization: String,
    revoked: Arc<AtomicBool>,
) -> Router
where
    H: ServerHandler + Clone + 'static,
{
    let sdk = StreamableHttpService::new(
        move || Ok(handler.clone()),
        Arc::new(LocalSessionManager::default()),
        StreamableHttpServerConfig {
            stateful_mode: false,
            ..Default::default()
        },
    );
    Router::new()
        .route_service("/mcp", sdk)
        .layer(RequestBodyLimitLayer::new(32_768))
        .layer(middleware::from_fn(move |request: Request, next: Next| {
            let authority = authority.clone();
            let authorization = authorization.clone();
            let revoked = revoked.clone();
            async move {
                if revoked.load(Ordering::Acquire) {
                    return StatusCode::UNAUTHORIZED.into_response();
                }
                match verify_request(request.headers(), &authority, &authorization) {
                    Ok(()) => next.run(request).await,
                    Err(status) => status.into_response(),
                }
            }
        }))
}

#[tauri::command]
pub async fn start_agent_mcp(
    window: WebviewWindow,
    state: State<'_, AgentMcpState>,
    channel: Channel<AgentCall>,
    tools: Vec<Tool>,
) -> Result<Connection, String> {
    require_main(&window)?;
    let listener = TcpListener::bind((std::net::Ipv4Addr::LOCALHOST, 0))
        .await
        .map_err(|_| "无法绑定本机 MCP 地址".to_owned())?;
    let authority = listener
        .local_addr()
        .map_err(|_| "MCP 地址不可用".to_owned())?
        .to_string();
    let token = Uuid::new_v4().to_string();
    let authorization = format!("Bearer {token}");
    let url = format!("http://{authority}/mcp");
    let pending = Pending::default();
    let revoked = Arc::new(AtomicBool::new(false));
    let revoked_for_requests = revoked.clone();
    let handler = ClassSetMcp {
        window,
        channel,
        tools: Arc::new(tools),
        pending: pending.clone(),
    };
    let router = mcp_router(handler, authority, authorization, revoked_for_requests);
    let mut current = state.0.lock().map_err(|_| "MCP 状态不可用")?;
    let task = tauri::async_runtime::spawn(async move {
        let _ = axum::serve(listener, router).await;
    });
    *current = Some(Running {
        task,
        pending,
        revoked,
    });
    Ok(Connection { url, token })
}

#[tauri::command]
pub fn stop_agent_mcp(
    window: WebviewWindow,
    state: State<'_, AgentMcpState>,
) -> Result<(), String> {
    require_main(&window)?;
    state.0.lock().map_err(|_| "MCP 状态不可用")?.take();
    Ok(())
}

#[tauri::command]
pub fn complete_agent_mcp_call(
    window: WebviewWindow,
    state: State<'_, AgentMcpState>,
    request_id: String,
    response: Value,
) -> Result<(), String> {
    require_main(&window)?;
    let id = Uuid::parse_str(&request_id).map_err(|_| "请求标识无效")?;
    let current = state.0.lock().map_err(|_| "MCP 状态不可用")?;
    if let Some(current) = current.as_ref() {
        if let Some(sender) = current
            .pending
            .lock()
            .map_err(|_| "MCP 状态不可用")?
            .remove(&id)
        {
            let _ = sender.send(response);
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[derive(Clone)]
    struct DemoTool;

    impl ServerHandler for DemoTool {
        fn get_info(&self) -> ServerInfo {
            ServerInfo {
                capabilities: ServerCapabilities::builder().enable_tools().build(),
                ..Default::default()
            }
        }

        async fn list_tools(
            &self,
            _: Option<PaginatedRequestParams>,
            _: RequestContext<RoleServer>,
        ) -> Result<ListToolsResult, ErrorData> {
            Ok(ListToolsResult {
                tools: vec![Tool::new(
                    "classset_smoke",
                    "Demo",
                    Arc::new(serde_json::Map::new()),
                )],
                ..Default::default()
            })
        }

        async fn call_tool(
            &self,
            _: CallToolRequestParams,
            _: RequestContext<RoleServer>,
        ) -> Result<CallToolResult, ErrorData> {
            Ok(CallToolResult::structured(json!({ "demo": true })))
        }
    }

    #[tokio::test]
    async fn streamable_http_initializes_lists_calls_and_revokes() {
        use axum::body::{to_bytes, Body};
        use tower::ServiceExt;

        let revoked = Arc::new(AtomicBool::new(false));
        let router = mcp_router(
            DemoTool,
            "127.0.0.1:41234".into(),
            "Bearer test-token".into(),
            revoked.clone(),
        );
        let request = |method: &str, params: Value| {
            Request::post("/mcp")
                .header(header::HOST, "127.0.0.1:41234")
                .header(header::AUTHORIZATION, "Bearer test-token")
                .header(header::ACCEPT, "application/json, text/event-stream")
                .header(header::CONTENT_TYPE, "application/json")
                .header("MCP-Protocol-Version", "2025-11-25")
                .body(Body::from(
                    json!({"jsonrpc":"2.0","id":1,"method":method,"params":params}).to_string(),
                ))
                .unwrap()
        };
        for (method, params, expected) in [
            (
                "initialize",
                json!({"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"test","version":"1"}}),
                "protocolVersion",
            ),
            ("tools/list", json!({}), "classset_smoke"),
            (
                "tools/call",
                json!({"name":"classset_smoke","arguments":{}}),
                "structuredContent",
            ),
        ] {
            let response = router
                .clone()
                .oneshot(request(method, params))
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            let bytes = to_bytes(response.into_body(), 16_384).await.unwrap();
            assert!(
                String::from_utf8_lossy(&bytes).contains(expected),
                "{method}"
            );
        }
        revoked.store(true, Ordering::Release);
        let response = router
            .oneshot(request("tools/list", json!({})))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    }

    #[test]
    fn mcp_requires_matching_loopback_host_and_token_and_rejects_browser_origins() {
        let host = "127.0.0.1:41234";
        let token = "Bearer smoke-token";
        let mut headers = HeaderMap::new();
        headers.insert(header::HOST, "example.test".parse().unwrap());
        assert_eq!(
            verify_request(&headers, host, token),
            Err(StatusCode::FORBIDDEN)
        );
        headers.insert(header::HOST, host.parse().unwrap());
        assert_eq!(
            verify_request(&headers, host, token),
            Err(StatusCode::UNAUTHORIZED)
        );
        headers.insert(header::AUTHORIZATION, token.parse().unwrap());
        assert_eq!(verify_request(&headers, host, token), Ok(()));
        headers.insert(header::ORIGIN, "null".parse().unwrap());
        assert_eq!(
            verify_request(&headers, host, token),
            Err(StatusCode::FORBIDDEN)
        );
    }
}
