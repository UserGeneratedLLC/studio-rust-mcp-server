use crate::server_state::{dispatch, PackedState};
use rmcp::{
    handler::server::{router::tool::ToolRoute, wrapper::Parameters},
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

    ToolRoute::new(tool, move |Parameters(args): Parameters<Args>| {
        let state = state.clone();
        async move { dispatch(&state, "InsertModel", serde_json::to_value(args).unwrap()).await }
    })
}
