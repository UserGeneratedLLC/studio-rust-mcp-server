use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
#[serde(rename_all = "snake_case")]
pub enum StartStopPlayMode {
    StartPlay,
    Stop,
    RunServer,
}

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct StartStopPlayArgs {
    #[schemars(
        description = "Don't use `run_server` unless you are sure no client/player is needed."
    )]
    pub mode: StartStopPlayMode,
}

#[tool_router(router = start_stop_play_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("start_stop_play.md")]
    #[tool(annotations(
        // Starts/stops play mode, modifying Studio state
        read_only_hint = false,
        // Starting/stopping play does not permanently destroy data
        destructive_hint = false,
        // Starting when already started returns "Already in play mode"
        idempotent_hint = true,
        // Operates entirely within the Studio session
        open_world_hint = false
    ))]
    async fn start_stop_play(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<StartStopPlayArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "start_stop_play", &args)
            .await
    }
}
