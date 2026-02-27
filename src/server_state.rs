use crate::error::Result;
use rmcp::{
    model::{CallToolResult, Content},
    ErrorData,
};
use rmpv::Value as MsgpackValue;
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{mpsc, Mutex};
use uuid::Uuid;

#[derive(Clone, Debug, Serialize)]
pub struct StudioConnection {
    #[serde(skip)]
    pub sender: mpsc::UnboundedSender<String>,
    pub place_id: u64,
    pub place_name: String,
    pub game_id: u64,
    pub job_id: String,
    pub place_version: u64,
    pub creator_id: u64,
    pub creator_type: String,
    pub connected_at: chrono::DateTime<chrono::Utc>,
}

#[derive(Deserialize, Debug)]
pub struct RegistrationMessage {
    // Discriminator for future message types (e.g. "register", "heartbeat")
    #[serde(rename = "type")]
    #[allow(dead_code)]
    pub msg_type: String,
    pub place_id: u64,
    pub place_name: String,
    pub game_id: u64,
    pub job_id: String,
    pub place_version: u64,
    pub creator_id: u64,
    pub creator_type: String,
}

#[derive(Clone)]
pub struct SessionState {
    pub selected_studio_id: Option<Uuid>,
    // Future: clipboard field for cross-studio copy/paste
    #[allow(dead_code)]
    pub created_at: chrono::DateTime<chrono::Utc>,
}

impl SessionState {
    pub fn new() -> Self {
        Self {
            selected_studio_id: None,
            created_at: chrono::Utc::now(),
        }
    }
}

pub struct PendingRequest {
    pub sender: mpsc::UnboundedSender<Result<String>>,
    pub connection_id: Uuid,
}

pub struct AppState {
    pub connections: HashMap<Uuid, StudioConnection>,
    pub sessions: HashMap<String, SessionState>,
    pub output_map: HashMap<Uuid, PendingRequest>,
}

pub type PackedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        Self {
            connections: HashMap::new(),
            sessions: HashMap::new(),
            output_map: HashMap::new(),
        }
    }
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct ToolArguments {
    pub tool: String,
    pub args: Value,
    pub id: Option<Uuid>,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct RunCommandResponse {
    pub success: bool,
    pub response: MsgpackValue,
    pub id: Uuid,
}

impl ToolArguments {
    pub fn new_with_id(tool: impl Into<String>, args: Value) -> (Self, Uuid) {
        let id = Uuid::new_v4();
        (
            Self {
                tool: tool.into(),
                args,
                id: Some(id),
            },
            id,
        )
    }
}

pub fn value_to_mcp_string(value: MsgpackValue) -> String {
    match value {
        MsgpackValue::Nil => "null".to_string(),
        MsgpackValue::Boolean(b) => b.to_string(),
        MsgpackValue::Integer(i) => i.to_string(),
        MsgpackValue::F32(f) => float_to_string(f as f64),
        MsgpackValue::F64(f) => float_to_string(f),
        MsgpackValue::String(s) => s.into_str().unwrap_or_default(),
        MsgpackValue::Binary(b) => b
            .iter()
            .map(|byte| format!("{byte:02x}"))
            .collect::<Vec<_>>()
            .join(""),
        MsgpackValue::Array(arr) => {
            let items: Vec<String> = arr.into_iter().map(value_to_mcp_string).collect();
            format!("[{}]", items.join(", "))
        }
        MsgpackValue::Map(pairs) => {
            let entries: Vec<String> = pairs
                .into_iter()
                .map(|(k, v)| format!("{}: {}", value_to_mcp_string(k), value_to_mcp_string(v)))
                .collect();
            format!("{{{}}}", entries.join(", "))
        }
        MsgpackValue::Ext(_, _) => "<ext>".to_string(),
    }
}

fn float_to_string(f: f64) -> String {
    if f.is_nan() {
        "NaN".to_string()
    } else if f == f64::INFINITY {
        "Infinity".to_string()
    } else if f == f64::NEG_INFINITY {
        "-Infinity".to_string()
    } else {
        f.to_string()
    }
}

pub fn get_or_create_session(state: &mut AppState, mcp_session_id: &str) -> SessionState {
    state
        .sessions
        .entry(mcp_session_id.to_string())
        .or_insert_with(SessionState::new)
        .clone()
}

fn resolve_studio_id(
    state: &AppState,
    session: &SessionState,
) -> std::result::Result<Uuid, ErrorData> {
    if let Some(studio_id) = session.selected_studio_id {
        if state.connections.contains_key(&studio_id) {
            return Ok(studio_id);
        }
        return Err(ErrorData::internal_error(
            format!(
                "Selected studio {} is no longer connected. Use list_studios and set_studio to pick a new one.",
                studio_id
            ),
            None,
        ));
    }

    match state.connections.len() {
        0 => Err(ErrorData::internal_error(
            "No Studio instances connected. Open Roblox Studio with the MCP plugin enabled.",
            None,
        )),
        1 => {
            let studio_id = *state.connections.keys().next().unwrap();
            Ok(studio_id)
        }
        _ => {
            let studios: Vec<String> = state
                .connections
                .iter()
                .map(|(id, conn)| format!("  {} - {}", id, conn.place_name))
                .collect();
            Err(ErrorData::internal_error(
                format!(
                    "Multiple studios connected. Call set_studio(studio_id=X) first.\nConnected studios:\n{}",
                    studios.join("\n")
                ),
                None,
            ))
        }
    }
}

pub async fn dispatch(
    state: &PackedState,
    session: &SessionState,
    tool: &str,
    args: Value,
) -> std::result::Result<CallToolResult, ErrorData> {
    let (command, id) = ToolArguments::new_with_id(tool, args);
    tracing::debug!("Running command: {:?}", command);

    let b64_text = crate::rbx_studio_server::ws_encode(&command)
        .map_err(|e| ErrorData::internal_error(format!("ws_encode error: {e}"), None))?;

    let (tx, mut rx) = mpsc::unbounded_channel::<Result<String>>();

    let sender = {
        let mut s = state.lock().await;
        let studio_id = resolve_studio_id(&s, session)?;
        let conn = s.connections.get(&studio_id).ok_or_else(|| {
            ErrorData::internal_error("Studio disconnected during dispatch", None)
        })?;
        let sender = conn.sender.clone();
        s.output_map.insert(
            id,
            PendingRequest {
                sender: tx,
                connection_id: studio_id,
            },
        );
        sender
    };

    if let Err(e) = sender.send(b64_text) {
        let mut s = state.lock().await;
        s.output_map.remove(&id);
        return Err(ErrorData::internal_error(
            format!("Failed to send to studio (disconnected): {e}"),
            None,
        ));
    }

    let result = rx
        .recv()
        .await
        .ok_or(ErrorData::internal_error("Studio disconnected", None))?;

    {
        let mut s = state.lock().await;
        s.output_map.remove(&id);
    }

    tracing::debug!("Sending to MCP: {result:?}");
    match result {
        Ok(r) => Ok(CallToolResult::success(vec![Content::text(r)])),
        Err(err) => Ok(CallToolResult::error(vec![Content::text(err.to_string())])),
    }
}
