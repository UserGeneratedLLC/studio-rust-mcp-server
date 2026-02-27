use crate::server_state::PackedState;
use rmcp::{
    handler::server::{router::tool::ToolRoute, wrapper::Parameters},
    model::{CallToolResult, Content, Tool},
    schemars,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
pub struct Args {}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "list_studios",
        "List all currently connected Roblox Studio instances with their studio_id and metadata.",
        serde_json::Map::new(),
    )
    .with_input_schema::<Args>();

    ToolRoute::new(tool, move |Parameters(_): Parameters<Args>| {
        let state = state.clone();
        async move {
            let s = state.lock().await;

            let studios: Vec<serde_json::Value> = s
                .connections
                .iter()
                .map(|(id, conn)| {
                    serde_json::json!({
                        "studio_id": id.to_string(),
                        "place_id": conn.place_id,
                        "place_name": conn.place_name,
                        "game_id": conn.game_id,
                        "job_id": conn.job_id,
                        "place_version": conn.place_version,
                        "creator_id": conn.creator_id,
                        "creator_type": conn.creator_type,
                        "connected_at": conn.connected_at.to_rfc3339(),
                    })
                })
                .collect();

            let result =
                serde_json::to_string_pretty(&studios).unwrap_or_else(|_| "[]".to_string());
            Ok(CallToolResult::success(vec![Content::text(result)]))
        }
    })
}
