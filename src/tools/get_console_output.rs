use super::prelude::*;

#[tool_router(router = get_console_output_route, vis = "pub")]
impl RBXStudioServer {
    #[tool(description = "Get the console output from Roblox Studio.")]
    async fn get_console_output(
        &self,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "get_console_output", &())
            .await
    }
}
