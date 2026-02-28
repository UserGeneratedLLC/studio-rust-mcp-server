use super::prelude::*;

#[tool_router(router = get_studio_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("get_studio.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn get_studio(
        &self,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        let mcp_session_id = Self::extract_mcp_session_id(&ctx);
        let s = self.state.lock().await;

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
            None if s.connections.len() == 1 => *s.connections.keys().next().unwrap(),
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
}
