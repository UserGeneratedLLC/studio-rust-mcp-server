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
    #[schemars(description = "Query to search for the model")]
    pub query: String,
}

pub fn route<S: Send + Sync + 'static>(state: PackedState) -> ToolRoute<S> {
    let tool = Tool::new(
        "insert_model",
        "Inserts a model from the Roblox marketplace into the workspace. Returns the inserted model name.",
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
                    "InsertModel",
                    serde_json::to_value(args).unwrap(),
                )
                .await
            }
        },
    )
}
