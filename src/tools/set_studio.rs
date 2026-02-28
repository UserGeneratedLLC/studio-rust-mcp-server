use super::prelude::*;

#[derive(Debug, Deserialize, schemars::JsonSchema)]
pub struct SetStudioArgs {
    #[schemars(
        description = "The studio_id field from list_studios output. Omit to clear selection."
    )]
    pub studio_id: Option<String>,
}

#[tool_router(router = set_studio_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("set_studio.md")]
    #[tool(annotations(
        // Modifies session routing state
        read_only_hint = false,
        // Only changes which studio is targeted, no data loss
        destructive_hint = false,
        // Setting the same studio_id twice has the same effect
        idempotent_hint = true,
        // Operates on internal session state only
        open_world_hint = false
    ))]
    async fn set_studio(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<SetStudioArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        let mcp_session_id = Self::extract_mcp_session_id(&ctx);
        let mut s = self.state.lock().await;

        match args.studio_id {
            None => {
                let session = s
                    .sessions
                    .entry(mcp_session_id)
                    .or_insert_with(SessionState::new);
                session.selected_studio_id = None;
                Ok(CallToolResult::success(vec![Content::text(
                    "Studio selection cleared.",
                )]))
            }
            Some(id_str) => {
                let studio_id = id_str.parse::<uuid::Uuid>().map_err(|_| {
                    ErrorData::invalid_params(format!("Invalid studio_id: {id_str}"), None)
                })?;

                let conn = match s.connections.get(&studio_id) {
                    Some(conn) => conn,
                    None => {
                        let available: Vec<String> = s
                            .connections
                            .iter()
                            .map(|(id, c)| format!("  {} - {}", id, c.place_name))
                            .collect();
                        return Ok(CallToolResult::error(vec![Content::text(format!(
                            "No studio with studio_id {studio_id}. Call `list_studios` to see available studios.\nConnected:\n{}",
                            available.join("\n")
                        ))]));
                    }
                };

                let metadata =
                    serde_json::to_string_pretty(&conn.to_info(studio_id)).unwrap_or_default();

                let session = s
                    .sessions
                    .entry(mcp_session_id)
                    .or_insert_with(SessionState::new);
                session.selected_studio_id = Some(studio_id);
                Ok(CallToolResult::success(vec![Content::text(metadata)]))
            }
        }
    }
}
