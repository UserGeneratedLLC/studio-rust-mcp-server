use crate::error::{Report, Result};
use crate::server_state::{value_to_mcp_string, PackedState, RunCommandResponse, ToolArguments};
use axum::body::Bytes;
use axum::extract::State;
use axum::http::StatusCode;
use axum::response::IntoResponse;
use color_eyre::eyre::{eyre, Error, OptionExt};
use rmcp::{
    handler::server::router::tool::ToolRouter,
    model::{Implementation, ProtocolVersion, ServerCapabilities, ServerInfo},
    tool_handler, ServerHandler,
};
use rmpv::Value as MsgpackValue;
use tokio::sync::oneshot::Receiver;

pub const STUDIO_PLUGIN_PORT: u16 = 44755;
const LONG_POLL_DURATION: tokio::time::Duration = tokio::time::Duration::from_secs(15);

const MSGPACK_CONTENT_TYPE: &str = "application/msgpack";

#[derive(Clone)]
pub struct RBXStudioServer {
    tool_router: ToolRouter<Self>,
}

impl RBXStudioServer {
    pub fn new(tool_router: ToolRouter<Self>) -> Self {
        Self { tool_router }
    }
}

#[tool_handler]
impl ServerHandler for RBXStudioServer {
    fn get_info(&self) -> ServerInfo {
        ServerInfo {
            protocol_version: ProtocolVersion::LATEST,
            capabilities: ServerCapabilities::builder().enable_tools().build(),
            server_info: Implementation {
                name: "Roblox_Studio".to_string(),
                version: env!("CARGO_PKG_VERSION").to_string(),
                title: Some("Roblox Studio MCP Server".to_string()),
                description: None,
                icons: None,
                website_url: None,
            },
            instructions: Some(
                "You must aware of current studio mode before using any tools, infer the mode from conversation context or get_studio_mode.
User run_code to query data from Roblox Studio place or to change it
After calling run_script_in_play_mode, the datamodel status will be reset to stop mode.
Prefer using start_stop_play tool instead run_script_in_play_mode, Only used run_script_in_play_mode to run one time unit test code on server datamodel.
"
                .to_string(),
            ),
        }
    }
}

fn to_msgpack_response(value: &impl serde::Serialize) -> Result<impl IntoResponse> {
    let bytes = rmp_serde::to_vec_named(value)
        .map_err(|e| color_eyre::eyre::eyre!("msgpack serialize error: {e}"))?;
    Ok((
        [(axum::http::header::CONTENT_TYPE, MSGPACK_CONTENT_TYPE)],
        bytes,
    ))
}

fn from_msgpack_bytes<T: serde::de::DeserializeOwned>(bytes: &[u8]) -> Result<T> {
    rmp_serde::from_slice(bytes)
        .map_err(|e| color_eyre::eyre::eyre!("msgpack deserialize error: {e}").into())
}

pub async fn request_handler(State(state): State<PackedState>) -> Result<axum::response::Response> {
    let timeout = tokio::time::timeout(LONG_POLL_DURATION, async {
        let mut waiter = { state.lock().await.waiter.clone() };
        loop {
            {
                let mut s = state.lock().await;
                if let Some(task) = s.process_queue.pop_front() {
                    return Ok::<ToolArguments, Error>(task);
                }
            }
            waiter.changed().await?
        }
    })
    .await;
    match timeout {
        Ok(result) => Ok(to_msgpack_response(&result?)?.into_response()),
        _ => Ok((StatusCode::LOCKED, String::new()).into_response()),
    }
}

pub async fn response_handler(
    State(state): State<PackedState>,
    body: Bytes,
) -> Result<impl IntoResponse> {
    let payload: RunCommandResponse = from_msgpack_bytes(&body)?;
    tracing::debug!("Received reply from studio {payload:?}");
    let mut s = state.lock().await;
    let tx = s.output_map.remove(&payload.id).ok_or_eyre("Unknown ID")?;
    let result: Result<String, Report> = if payload.success {
        Ok(value_to_mcp_string(payload.response))
    } else {
        Err(Report::from(eyre!(value_to_mcp_string(payload.response))))
    };
    Ok(tx.send(result)?)
}

pub async fn proxy_handler(
    State(state): State<PackedState>,
    body: Bytes,
) -> Result<impl IntoResponse> {
    let command: ToolArguments = from_msgpack_bytes(&body)?;
    let id = command.id.ok_or_eyre("Got proxy command with no id")?;
    tracing::debug!("Received request to proxy {command:?}");
    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel();
    {
        let mut s = state.lock().await;
        s.process_queue.push_back(command);
        s.output_map.insert(id, tx);
    }
    let result = rx.recv().await.ok_or_eyre("Couldn't receive response")?;
    {
        let mut s = state.lock().await;
        s.output_map.remove_entry(&id);
    }
    let (success, response_str) = match result {
        Ok(s) => (true, s),
        Err(e) => (false, e.to_string()),
    };
    tracing::debug!("Sending back to dud: success={success}, response={response_str:?}");
    let response = RunCommandResponse {
        success,
        response: MsgpackValue::String(response_str.into()),
        id,
    };
    to_msgpack_response(&response)
}

pub async fn dud_proxy_loop(state: PackedState, exit: Receiver<()>) {
    let client = reqwest::Client::new();
    let mut waiter = { state.lock().await.waiter.clone() };
    while exit.is_empty() {
        let entry = { state.lock().await.process_queue.pop_front() };
        if let Some(entry) = entry {
            let body = match rmp_serde::to_vec_named(&entry) {
                Ok(b) => b,
                Err(e) => {
                    tracing::error!("Failed to serialize proxy entry: {e}");
                    continue;
                }
            };
            let res = client
                .post(format!("http://127.0.0.1:{STUDIO_PLUGIN_PORT}/proxy"))
                .header(reqwest::header::CONTENT_TYPE, MSGPACK_CONTENT_TYPE)
                .body(body)
                .send()
                .await;
            if let Ok(res) = res {
                let tx = {
                    state
                        .lock()
                        .await
                        .output_map
                        .remove(&entry.id.unwrap())
                        .unwrap()
                };
                let res = res
                    .bytes()
                    .await
                    .map_err(Into::into)
                    .and_then(|b| from_msgpack_bytes::<RunCommandResponse>(&b))
                    .and_then(|r| {
                        if r.success {
                            Ok(value_to_mcp_string(r.response))
                        } else {
                            Err(Report::from(eyre!(value_to_mcp_string(r.response))))
                        }
                    });
                tx.send(res).unwrap();
            } else {
                tracing::error!("Failed to proxy: {res:?}");
            };
        } else {
            waiter.changed().await.unwrap();
        }
    }
}
