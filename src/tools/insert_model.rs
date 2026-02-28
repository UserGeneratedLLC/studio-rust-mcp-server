use super::prelude::*;

#[derive(Debug, Deserialize, Serialize, schemars::JsonSchema)]
pub struct InsertModelArgs {
    #[schemars(description = "Query to search for the model")]
    pub query: String,
}

#[tool_router(router = insert_model_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("insert_model.md")]
    #[tool(annotations(
        // Inserts new instances into workspace
        read_only_hint = false,
        // Only adds content, does not destroy existing data
        destructive_hint = false,
        // Each call inserts a new model instance
        idempotent_hint = false,
        // Queries the Roblox marketplace (external service)
        open_world_hint = true
    ))]
    async fn insert_model(
        &self,
        ctx: RequestContext<RoleServer>,
        Parameters(args): Parameters<InsertModelArgs>,
    ) -> Result<CallToolResult, ErrorData> {
        self.dispatch_to_studio(&ctx, "insert_model", &args).await
    }
}
