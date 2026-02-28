use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct RunScriptInPlayModeArgs {
    #[schemars(description = "Code to run")]
    pub code: String,
    #[schemars(description = "Timeout in seconds, defaults to 100 seconds")]
    pub timeout: Option<u32>,
    #[schemars(description = "Mode to run in, must be start_play or run_server")]
    pub mode: String,
}

#[tool_router(router = run_script_in_play_mode_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("run_script_in_play_mode.md")]
    #[tool(annotations(
        // Tool modifies its environment (e.g. starts/stops play mode)
        read_only_hint = false,
        // Tool may perform destructive updates (only meaningful when read_only_hint = false)
        destructive_hint = false,
        // Repeated calls with same args may have additional effects (only meaningful when read_only_hint = false)
        idempotent_hint = true,
        // Tool interacts with external entities beyond its closed domain
        open_world_hint = false
    ))]
    async fn run_script_in_play_mode(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<RunScriptInPlayModeArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "run_script_in_play_mode", &args)
            .await
    }
}
