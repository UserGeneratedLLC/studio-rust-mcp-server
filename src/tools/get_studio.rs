use crate::server_state::PackedState;
use http::request::Parts;
use rmcp::{
    handler::server::{router::tool::ToolRoute, tool::Extension, wrapper::Parameters},
    model::{CallToolResult, Content, Tool},
    schemars,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
pub struct Args {}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "get_studio",
        "Get the currently selected Roblox Studio instance for this session. Returns studio metadata if a studio is selected and still connected, or nothing if no studio is selected or the selected studio disconnected.",
        serde_json::Map::new(),
    )
    .with_input_schema::<Args>();

    ToolRoute::new(
        tool,
        move |Extension(parts): Extension<Parts>, Parameters(_): Parameters<Args>| {
            let state = state.clone();
            async move {
                let mcp_session_id = super::extract_mcp_session_id(&parts);
                let s = state.lock().await;

                let session = match s.sessions.get(&mcp_session_id) {
                    Some(session) => session,
                    None => {
                        return Ok(CallToolResult::success(vec![Content::text(
                            "No studio selected.",
                        )]));
                    }
                };

                let studio_id = match session.selected_studio_id {
                    Some(id) => id,
                    None => {
                        return Ok(CallToolResult::success(vec![Content::text(
                            "No studio selected.",
                        )]));
                    }
                };

                match s.connections.get(&studio_id) {
                    Some(conn) => {
                        let metadata = serde_json::to_string_pretty(&serde_json::json!({
                            "studio_id": studio_id.to_string(),
                            "place_id": conn.place_id,
                            "place_name": conn.place_name,
                            "game_id": conn.game_id,
                            "job_id": conn.job_id,
                            "place_version": conn.place_version,
                            "creator_id": conn.creator_id,
                            "creator_type": conn.creator_type,
                            "connected_at": conn.connected_at.to_rfc3339(),
                        }))
                        .unwrap_or_default();
                        Ok(CallToolResult::success(vec![Content::text(metadata)]))
                    }
                    None => Ok(CallToolResult::success(vec![Content::text(
                        "Selected studio is no longer connected. Use list_studios and set_studio to pick a new one.",
                    )])),
                }
            }
        },
    )
}
