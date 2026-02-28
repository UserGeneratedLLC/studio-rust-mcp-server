use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct StartStopPlayArgs {
    #[schemars(
        description = "Mode to start or stop, must be start_play, stop, or run_server. Don't use run_server unless you are sure no client/player is needed."
    )]
    pub mode: String,
}

#[tool_router(router = start_stop_play_route, vis = "pub")]
impl RBXStudioServer {
    #[tool(
        description = "Start or stop play mode or run the server. Don't enter run_server mode unless you are sure no client/player is needed."
    )]
    async fn start_stop_play(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<StartStopPlayArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "start_stop_play", &args)
            .await
    }
}
