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
    #[schemars(description = "Code to run")]
    pub command: String,
}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "run_code",
        "Runs a command in Roblox Studio and returns the printed output. Can be used to both make changes and retrieve information",
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
                    "RunCode",
                    serde_json::to_value(args).unwrap(),
                )
                .await
            }
        },
    )
}
