pub mod get_console_output;
pub mod get_studio;
pub mod get_studio_mode;
pub mod insert_model;
pub mod list_studios;
pub mod run_code;
pub mod run_script_in_play_mode;
pub mod set_studio;
pub mod start_stop_play;

use crate::server_state::{get_or_create_session, PackedState, SessionState};
use rmcp::handler::server::router::tool::ToolRouter;

pub fn build_router<S: Send + Sync + 'static>(state: PackedState) -> ToolRouter<S> {
    ToolRouter::new()
        .with_route(run_code::route::<S>(state.clone()))
        .with_route(insert_model::route::<S>(state.clone()))
        .with_route(get_console_output::route::<S>(state.clone()))
        .with_route(get_studio_mode::route::<S>(state.clone()))
        .with_route(start_stop_play::route::<S>(state.clone()))
        .with_route(run_script_in_play_mode::route::<S>(state.clone()))
        .with_route(set_studio::route::<S>(state.clone()))
        .with_route(get_studio::route::<S>(state.clone()))
        .with_route(list_studios::route::<S>(state.clone()))
}

pub async fn resolve_session(state: &PackedState, parts: &http::request::Parts) -> SessionState {
    let mcp_session_id = extract_mcp_session_id(parts);
    let mut s = state.lock().await;
    get_or_create_session(&mut s, &mcp_session_id)
}

pub fn extract_mcp_session_id(parts: &http::request::Parts) -> String {
    parts
        .headers
        .get("mcp-session-id")
        .and_then(|v: &http::HeaderValue| v.to_str().ok())
        .unwrap_or("unknown")
        .to_string()
}
