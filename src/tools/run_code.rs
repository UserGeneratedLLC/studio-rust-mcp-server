use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct RunCodeArgs {
    #[schemars(description = "Code to run")]
    pub command: String,
}

#[tool_router(router = run_code_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("run_code.md")]
    #[tool(annotations(
        // Tool modifies its environment (e.g. arbitrary code execution)
        read_only_hint = false,
        // Arbitrary code can destroy instances or data
        destructive_hint = true,
        // Repeated calls may have cumulative effects depending on the code
        idempotent_hint = false,
        // Operates entirely within the Studio session
        open_world_hint = false
    ))]
    async fn run_code(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<RunCodeArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "run_code", &args).await
    }
}
