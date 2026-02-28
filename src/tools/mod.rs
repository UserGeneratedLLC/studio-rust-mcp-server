mod get_console_output;
mod get_studio;
mod get_studio_mode;
mod insert_model;
mod list_studios;
mod run_code;
mod run_script_in_play_mode;
mod set_studio;
mod start_stop_play;

pub(crate) mod prelude {
    pub use crate::rbx_studio_server::RBXStudioServer;
    pub use crate::server_state::{dispatch, get_or_create_session, SessionState, StudioInfo};
    pub use rmcp::{
        handler::server::{
            router::tool::ToolRouter,
            wrapper::{Json, Parameters},
        },
        model::{CallToolResult, Content},
        schemars,
        service::RequestContext,
        tool, tool_router, ErrorData, RoleServer,
    };
    pub use serde::{Deserialize, Serialize};
}

use prelude::*;

impl RBXStudioServer {
    pub(crate) fn build_tool_router() -> ToolRouter<Self> {
        Self::run_code_route()
            + Self::insert_model_route()
            + Self::get_console_output_route()
            + Self::get_studio_mode_route()
            + Self::start_stop_play_route()
            + Self::run_script_in_play_mode_route()
            + Self::set_studio_route()
            + Self::get_studio_route()
            + Self::list_studios_route()
    }

    pub(crate) async fn dispatch_to_studio<T: Serialize>(
        &self,
        ctx: &RequestContext<RoleServer>,
        tool: &str,
        args: &T,
    ) -> Result<CallToolResult, ErrorData> {
        let session = self.resolve_session(ctx).await;
        dispatch(&self.state, &session, tool, args).await
    }

    pub(crate) async fn resolve_session(&self, ctx: &RequestContext<RoleServer>) -> SessionState {
        let mcp_session_id = Self::extract_mcp_session_id(ctx);
        let mut s = self.state.lock().await;
        get_or_create_session(&mut s, &mcp_session_id)
    }

    pub(crate) fn extract_mcp_session_id(ctx: &RequestContext<RoleServer>) -> String {
        ctx.extensions
            .get::<http::request::Parts>()
            .and_then(|parts| parts.headers.get("mcp-session-id"))
            .and_then(|v| v.to_str().ok())
            .unwrap_or("unknown")
            .to_string()
    }
}
