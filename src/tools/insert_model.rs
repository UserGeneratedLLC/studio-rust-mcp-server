use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct InsertModelArgs {
    #[schemars(description = "Query to search for the model")]
    pub query: String,
}

#[tool_router(router = insert_model_route, vis = "pub")]
impl RBXStudioServer {
    #[tool(
        description = "Inserts a model from the Roblox marketplace into the workspace. Returns the inserted model name."
    )]
    async fn insert_model(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<InsertModelArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "insert_model", &args).await
    }
}
