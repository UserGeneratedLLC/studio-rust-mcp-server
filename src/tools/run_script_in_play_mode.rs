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
    #[tool(
        description = "Run a script in play mode and automatically stop play after script finishes or timeout. \
        Returns the output of the script. \
        Result format: { success: boolean, value: string, error: string, logs: { level: string, message: string, ts: number }[], errors: { level: string, message: string, ts: number }[], duration: number, isTimeout: boolean }. \
        Prefer using start_stop_play tool instead. \
        After calling, the datamodel status will be reset to stop mode. \
        If it returns `StudioTestService: Previous call to start play session has not been completed`, call start_stop_play to stop first then try again."
    )]
    async fn run_script_in_play_mode(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<RunScriptInPlayModeArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "run_script_in_play_mode", &args)
            .await
    }
}
