use crate::error::Result;
use rmcp::{
    model::{CallToolResult, Content},
    schemars, ErrorData,
};
use rmpv::Value as MsgpackValue;
use serde::{Deserialize, Serialize};
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

impl StudioConnection {
    pub fn to_info(&self, studio_id: Uuid) -> StudioInfo {
        StudioInfo {
            studio_id: studio_id.to_string(),
            place_id: self.place_id,
            place_name: self.place_name.clone(),
            game_id: self.game_id,
            job_id: self.job_id.clone(),
            place_version: self.place_version,
            creator_id: self.creator_id,
            creator_type: self.creator_type.clone(),
            connected_at: self.connected_at.to_rfc3339(),
        }
    }
}

#[derive(Serialize, schemars::JsonSchema)]
pub struct StudioInfo {
    #[schemars(description = "Unique studio connection identifier")]
    pub studio_id: String,
    #[schemars(description = "Numeric place identifier")]
    pub place_id: u64,
    #[schemars(description = "Name of the Roblox place")]
    pub place_name: String,
    #[schemars(description = "Numeric game/universe identifier")]
    pub game_id: u64,
    #[schemars(description = "Job identifier for this Studio session")]
    pub job_id: String,
    #[schemars(description = "Current place version number")]
    pub place_version: u64,
    #[schemars(description = "Creator account identifier")]
    pub creator_id: u64,
    #[schemars(description = "Creator account type")]
    pub creator_type: String,
    #[schemars(description = "ISO 8601 timestamp of when the studio connected")]
    pub connected_at: String,
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

#[derive(Serialize)]
struct WireMessage<'a, T: Serialize> {
    tool: &'a str,
    args: &'a T,
    id: Uuid,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct RunCommandResponse {
    pub success: bool,
    pub response: MsgpackValue,
    pub id: Uuid,
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
) -> std::result::Result<Uuid, CallToolResult> {
    if let Some(studio_id) = session.selected_studio_id {
        if state.connections.contains_key(&studio_id) {
            return Ok(studio_id);
        }
        return Err(CallToolResult::error(vec![Content::text(format!(
            "Selected studio {} is no longer connected. Call `list_studios` to see available studios, then `set_studio` to select one.",
            studio_id
        ))]));
    }

    match state.connections.len() {
        0 => Err(CallToolResult::error(vec![Content::text(
            "No Studio instances connected. Open Roblox Studio with the MCP plugin enabled.",
        )])),
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
            Err(CallToolResult::error(vec![Content::text(format!(
                "Multiple studios connected. Call `set_studio` with one of these studio_ids first:\n{}",
                studios.join("\n")
            ))]))
        }
    }
}

pub async fn dispatch<T: Serialize>(
    state: &PackedState,
    session: &SessionState,
    tool: &str,
    args: &T,
) -> std::result::Result<CallToolResult, ErrorData> {
    let id = Uuid::new_v4();
    let command = WireMessage { tool, args, id };
    tracing::debug!("Running command: {tool} (id={id})");

    let b64_text = crate::rbx_studio_server::ws_encode(&command)
        .map_err(|e| ErrorData::internal_error(format!("ws_encode error: {e}"), None))?;

    let (tx, mut rx) = mpsc::unbounded_channel::<Result<String>>();

    let sender = {
        let mut s = state.lock().await;
        let studio_id = match resolve_studio_id(&s, session) {
            Ok(id) => id,
            Err(error_result) => return Ok(error_result),
        };
        let conn = match s.connections.get(&studio_id) {
            Some(conn) => conn,
            None => {
                return Ok(CallToolResult::error(vec![Content::text(
                    "Studio disconnected during dispatch. Call `list_studios` to see available studios.",
                )]));
            }
        };
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
        return Ok(CallToolResult::error(vec![Content::text(format!(
            "Studio disconnected: {e}. Call `list_studios` to see available studios.",
        ))]));
    }

    let result = rx.recv().await;

    {
        let mut s = state.lock().await;
        s.output_map.remove(&id);
    }

    let result = match result {
        Some(r) => r,
        None => {
            return Ok(CallToolResult::error(vec![Content::text(
                "Studio disconnected while waiting for response. Call `list_studios` to see available studios.",
            )]));
        }
    };

    tracing::debug!("Sending to MCP: {result:?}");
    match result {
        Ok(r) => Ok(CallToolResult::success(vec![Content::text(r)])),
        Err(err) => Ok(CallToolResult::error(vec![Content::text(err.to_string())])),
    }
}
