use crate::server_state::{
    value_to_mcp_string, PackedState, RegistrationMessage, RunCommandResponse, StudioConnection,
};
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::IntoResponse;
use futures_util::{SinkExt, StreamExt};
use rmcp::{
    handler::server::router::tool::ToolRouter,
    model::{Implementation, ProtocolVersion, ServerCapabilities, ServerInfo},
    tool_handler, ServerHandler,
};
use uuid::Uuid;

pub const STUDIO_PLUGIN_PORT: u16 = 44755;

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
                "You must be aware of current studio mode before using any tools.
Use run_code to query data from Roblox Studio or make changes.
Prefer start_stop_play over run_script_in_play_mode.
After calling run_script_in_play_mode, the datamodel status will be reset to stop mode.

MULTI-STUDIO: Multiple studios may be connected. Each agent session is isolated.
- Call list_studios to see all connected studios with their studio_id and metadata.
- Call get_studio to check which studio your session is currently targeting.
- Call set_studio(studio_id=X) to bind your session to a studio.
- All subsequent calls route to the selected studio automatically.
- For cross-studio operations, call set_studio to switch before each action.
- When exactly one studio is connected, selection is automatic.
- Studios are identified by studio_id (server-assigned UUID per WebSocket connection). A reconnecting studio gets a new studio_id.
- If get_studio returns nothing, the selected studio disconnected -- use list_studios and set_studio to pick a new one."
                    .to_string(),
            ),
        }
    }
}

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    State(state): State<PackedState>,
) -> impl IntoResponse {
    ws.on_upgrade(move |socket| handle_studio_connection(socket, state))
}

async fn handle_studio_connection(socket: WebSocket, state: PackedState) {
    let (mut ws_sender, mut ws_receiver) = socket.split();

    let registration = match ws_receiver.next().await {
        Some(Ok(Message::Binary(data))) => {
            match rmp_serde::from_slice::<RegistrationMessage>(&data) {
                Ok(reg) => reg,
                Err(e) => {
                    tracing::error!("Invalid registration message: {e}");
                    return;
                }
            }
        }
        other => {
            tracing::error!("Expected binary registration message, got: {other:?}");
            return;
        }
    };

    let studio_id = Uuid::new_v4();
    tracing::info!(
        "Studio connected: {} (place_id={}, place_name={})",
        studio_id,
        registration.place_id,
        registration.place_name
    );

    let ack = rmp_serde::to_vec_named(&serde_json::json!({
        "type": "registered",
        "studio_id": studio_id.to_string()
    }));
    if let Ok(ack_bytes) = ack {
        if ws_sender
            .send(Message::Binary(ack_bytes.into()))
            .await
            .is_err()
        {
            tracing::error!("Failed to send registration ack to studio {studio_id}");
            return;
        }
    }

    let (tx, mut rx) = tokio::sync::mpsc::unbounded_channel::<Vec<u8>>();

    {
        let mut s = state.lock().await;
        s.connections.insert(
            studio_id,
            StudioConnection {
                sender: tx,
                place_id: registration.place_id,
                place_name: registration.place_name,
                game_id: registration.game_id,
                job_id: registration.job_id,
                place_version: registration.place_version,
                creator_id: registration.creator_id,
                creator_type: registration.creator_type,
                connected_at: chrono::Utc::now(),
            },
        );
    }

    let state_for_sender = state.clone();
    let sender_task = tokio::spawn(async move {
        while let Some(bytes) = rx.recv().await {
            if ws_sender.send(Message::Binary(bytes.into())).await.is_err() {
                break;
            }
        }
        let _ = state_for_sender; // prevent drop before sender finishes
    });

    while let Some(msg) = ws_receiver.next().await {
        match msg {
            Ok(Message::Binary(data)) => match rmp_serde::from_slice::<RunCommandResponse>(&data) {
                Ok(response) => {
                    let mut s = state.lock().await;
                    if let Some(pending) = s.output_map.remove(&response.id) {
                        let result = if response.success {
                            Ok(value_to_mcp_string(response.response))
                        } else {
                            Err(
                                color_eyre::eyre::eyre!(value_to_mcp_string(response.response))
                                    .into(),
                            )
                        };
                        let _ = pending.sender.send(result);
                    } else {
                        tracing::warn!("Received response for unknown request ID: {}", response.id);
                    }
                }
                Err(e) => {
                    tracing::warn!("Failed to decode studio message: {e}");
                }
            },
            Ok(Message::Close(_)) => break,
            Err(e) => {
                tracing::warn!("WebSocket error from studio {studio_id}: {e}");
                break;
            }
            _ => {}
        }
    }

    // Cleanup: remove connection and fail pending requests
    {
        let mut s = state.lock().await;
        s.connections.remove(&studio_id);
        let pending_ids: Vec<Uuid> = s
            .output_map
            .iter()
            .filter(|(_, req)| req.connection_id == studio_id)
            .map(|(id, _)| *id)
            .collect();
        for id in pending_ids {
            if let Some(pending) = s.output_map.remove(&id) {
                let _ = pending
                    .sender
                    .send(Err(color_eyre::eyre::eyre!("Studio disconnected").into()));
            }
        }
    }

    sender_task.abort();
    tracing::info!("Studio disconnected: {studio_id}");
}
