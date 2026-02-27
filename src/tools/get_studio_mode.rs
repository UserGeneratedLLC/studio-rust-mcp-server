use crate::server_state::{dispatch, PackedState};
use rmcp::{
    handler::server::{router::tool::ToolRoute, wrapper::Parameters},
    model::Tool,
    schemars,
};
use serde::{Deserialize, Serialize};

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema, Clone)]
pub struct Args {}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "get_studio_mode",
        "Get the current studio mode. Returns the studio mode. The result will be one of start_play, run_server, or stop.",
        serde_json::Map::new(),
    )
    .with_input_schema::<Args>();

    ToolRoute::new(tool, move |Parameters(args): Parameters<Args>| {
        let state = state.clone();
        async move { dispatch(&state, "GetStudioMode", serde_json::to_value(args).unwrap()).await }
    })
}
