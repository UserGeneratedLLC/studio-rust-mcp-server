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
                return Ok(CallToolResult::error(vec![Content::text(
                    "No studio selected. Call `list_studios` to see available studios, then `set_studio` to select one.",
                )]));
            }
        };

        let studio_id = match session.selected_studio_id {
            Some(id) => id,
            None if s.connections.len() == 1 => *s.connections.keys().next().unwrap(),
            None => {
                return Ok(CallToolResult::error(vec![Content::text(
                    "No studio selected. Call `list_studios` to see available studios, then `set_studio` to select one.",
                )]));
            }
        };

        match s.connections.get(&studio_id) {
            Some(conn) => {
                let info = conn.to_info(studio_id);
                let metadata = serde_json::to_string_pretty(&info).unwrap_or_default();
                Ok(CallToolResult::success(vec![Content::text(metadata)]))
            }
            None => Ok(CallToolResult::error(vec![Content::text(
                "Selected studio is no longer connected. Call `list_studios` to see available studios, then `set_studio` to select one.",
            )])),
        }
    }
}
