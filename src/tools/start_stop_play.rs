use crate::server_state::{dispatch, PackedState};
use http::request::Parts;
use rmcp::{
    handler::server::{router::tool::ToolRoute, tool::Extension, wrapper::Parameters},
    model::Tool,
    schemars,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
pub struct Args {
    #[schemars(
        description = "Mode to start or stop, must be start_play, stop, or run_server. Don't use run_server unless you are sure no client/player is needed."
    )]
    pub mode: String,
}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "start_stop_play",
        "Start or stop play mode or run the server. Don't enter run_server mode unless you are sure no client/player is needed.",
        serde_json::Map::new(),
    )
    .with_input_schema::<Args>();

    ToolRoute::new(
        tool,
        move |Extension(parts): Extension<Parts>, Parameters(args): Parameters<Args>| {
            let state = state.clone();
            async move {
                let session = super::resolve_session(&state, &parts).await;
                dispatch(
                    &state,
                    &session,
                    "StartStopPlay",
                    serde_json::to_value(args).unwrap(),
                )
                .await
            }
        },
    )
}
