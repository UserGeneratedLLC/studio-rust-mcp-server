use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum TestMode {
    StartPlay,
    RunServer,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct RunScriptInPlayModeArgs {
    #[schemars(description = "Code to run")]
    pub code: String,
    #[schemars(description = "Timeout in seconds. Defaults to 100 seconds.")]
    pub timeout: Option<u32>,
    pub mode: TestMode,
}

#[tool_router(router = run_script_in_play_mode_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("run_script_in_play_mode.md")]
    #[tool(annotations(
        read_only_hint = false,
        destructive_hint = false,
        idempotent_hint = false,
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
