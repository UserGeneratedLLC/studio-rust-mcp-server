use crate::error::Result;
use rmcp::{
    model::{CallToolResult, Content},
    ErrorData,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::collections::{HashMap, VecDeque};
use std::sync::Arc;
use tokio::sync::{mpsc, watch, Mutex};
use uuid::Uuid;

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct ToolArguments {
    pub tool: String,
    pub args: Value,
    pub id: Option<Uuid>,
}

#[derive(Deserialize, Serialize, Clone, Debug)]
pub struct RunCommandResponse {
    pub success: bool,
    pub response: String,
    pub id: Uuid,
}

pub struct AppState {
    pub process_queue: VecDeque<ToolArguments>,
    pub output_map: HashMap<Uuid, mpsc::UnboundedSender<Result<String>>>,
    pub waiter: watch::Receiver<()>,
    pub trigger: watch::Sender<()>,
}

pub type PackedState = Arc<Mutex<AppState>>;

impl AppState {
    pub fn new() -> Self {
        let (trigger, waiter) = watch::channel(());
        Self {
            process_queue: VecDeque::new(),
            output_map: HashMap::new(),
            waiter,
            trigger,
        }
    }
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

pub async fn dispatch(
    state: &PackedState,
    tool: &str,
    args: Value,
) -> Result<CallToolResult, ErrorData> {
    let (command, id) = ToolArguments::new_with_id(tool, args);
    tracing::debug!("Running command: {:?}", command);
    let (tx, mut rx) = mpsc::unbounded_channel::<Result<String>>();
    let trigger = {
        let mut s = state.lock().await;
        s.process_queue.push_back(command);
        s.output_map.insert(id, tx);
        s.trigger.clone()
    };
    trigger
        .send(())
        .map_err(|e| ErrorData::internal_error(format!("Unable to trigger send {e}"), None))?;
    let result = rx
        .recv()
        .await
        .ok_or(ErrorData::internal_error("Couldn't receive response", None))?;
    {
        let mut s = state.lock().await;
        s.output_map.remove_entry(&id);
    }
    tracing::debug!("Sending to MCP: {result:?}");
    match result {
        Ok(r) => Ok(CallToolResult::success(vec![Content::text(r)])),
        Err(err) => Ok(CallToolResult::error(vec![Content::text(err.to_string())])),
    }
}
