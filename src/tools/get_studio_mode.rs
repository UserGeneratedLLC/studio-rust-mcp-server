use super::prelude::*;

#[tool_router(router = get_studio_mode_route, vis = "pub")]
impl RBXStudioServer {
    #[tool(
        description = "Get the current studio mode. Returns the studio mode. The result will be one of start_play, run_server, or stop."
    )]
    async fn get_studio_mode(
        &self,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "get_studio_mode", &()).await
    }
}
