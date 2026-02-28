use super::prelude::*;

#[tool_router(router = get_console_output_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("get_console_output.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn get_console_output(
        &self,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "get_console_output", &())
            .await
    }
}
