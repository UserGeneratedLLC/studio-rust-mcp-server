use crate::server_state::PackedState;
use http::request::Parts;
use rmcp::{
    handler::server::{router::tool::ToolRoute, tool::Extension, wrapper::Parameters},
    model::{CallToolResult, Content, Tool},
    schemars, ErrorData,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
pub struct Args {
    #[schemars(
        description = "The studio_id field from list_studios output. Omit to clear selection."
    )]
    pub studio_id: Option<String>,
}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "set_studio",
        "Bind this session to a specific Roblox Studio instance. All subsequent tool calls will route to the selected studio. Use list_studios to discover available studio_ids.",
        serde_json::Map::new(),
    )
    .with_input_schema::<Args>();

    ToolRoute::new(
        tool,
        move |Extension(parts): Extension<Parts>, Parameters(args): Parameters<Args>| {
            let state = state.clone();
            async move {
                let mcp_session_id = super::extract_mcp_session_id(&parts);
                let mut s = state.lock().await;

                match args.studio_id {
                    None => {
                        let session = s
                            .sessions
                            .entry(mcp_session_id)
                            .or_insert_with(crate::server_state::SessionState::new);
                        session.selected_studio_id = None;
                        Ok(CallToolResult::success(vec![Content::text(
                            "Studio selection cleared.",
                        )]))
                    }
                    Some(id_str) => {
                        let studio_id = id_str.parse::<Uuid>().map_err(|_| {
                            ErrorData::invalid_params(format!("Invalid studio_id: {id_str}"), None)
                        })?;

                        let metadata = {
                            let conn = s.connections.get(&studio_id).ok_or_else(|| {
                                let available: Vec<String> = s
                                    .connections
                                    .iter()
                                    .map(|(id, c)| format!("  {} - {}", id, c.place_name))
                                    .collect();
                                ErrorData::invalid_params(
                                    format!(
                                        "No studio with studio_id {}.\nAvailable:\n{}",
                                        studio_id,
                                        available.join("\n")
                                    ),
                                    None,
                                )
                            })?;

                            serde_json::to_string_pretty(&serde_json::json!({
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
                            .unwrap_or_default()
                        };

                        let session = s
                            .sessions
                            .entry(mcp_session_id)
                            .or_insert_with(crate::server_state::SessionState::new);
                        session.selected_studio_id = Some(studio_id);
                        Ok(CallToolResult::success(vec![Content::text(metadata)]))
                    }
                }
            }
        },
    )
}
