use super::prelude::*;

#[tool_router(router = get_studio_mode_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("get_studio_mode.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn get_studio_mode(
        &self,
        ctx: RequestContext<RoleServer>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "get_studio_mode", &()).await
    }
}
