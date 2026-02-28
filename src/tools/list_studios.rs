use super::prelude::*;

#[tool_router(router = list_studios_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("list_studios.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn list_studios(&self) -> Result<CallToolResult, ErrorData> {
        let s = self.state.lock().await;

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

        let result = serde_json::to_string_pretty(&studios).unwrap_or_else(|_| "[]".to_string());
        Ok(CallToolResult::success(vec![Content::text(result)]))
    }
}
