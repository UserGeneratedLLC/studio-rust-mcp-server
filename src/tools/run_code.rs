use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct RunCodeArgs {
    #[schemars(description = "Code to run")]
    pub command: String,
}

#[tool_router(router = run_code_route, vis = "pub")]
impl RBXStudioServer {
    #[tool(
        description = "Runs a command in Roblox Studio and returns the printed output. Can be used to both make changes and retrieve information"
    )]
    async fn run_code(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<RunCodeArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "run_code", &args).await
    }
}
