use super::prelude::*;

#[tool_router(router = list_studios_route, vis = "pub")]
impl RBXStudioServer {
    #[doc = include_str!("list_studios.md")]
    #[tool(annotations(
        read_only_hint = true,
        destructive_hint = false,
        idempotent_hint = true,
        open_world_hint = false
    ))]
    async fn list_studios(&self) -> Result<Json<Vec<StudioInfo>>, ErrorData> {
        let s = self.state.lock().await;
        let studios: Vec<StudioInfo> = s
            .connections
            .iter()
            .map(|(id, conn)| conn.to_info(*id))
            .collect();
        Ok(Json(studios))
    }
}
