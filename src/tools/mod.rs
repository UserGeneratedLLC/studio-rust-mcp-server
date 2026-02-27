pub mod get_console_output;
pub mod get_studio_mode;
pub mod insert_model;
pub mod run_code;
pub mod run_script_in_play_mode;
pub mod start_stop_play;

use crate::server_state::PackedState;
use rmcp::handler::server::router::tool::ToolRouter;

pub fn build_router<S: Send + Sync + 'static>(state: PackedState) -> ToolRouter<S> {
    ToolRouter::new()
        .with_route(run_code::route::<S>(state.clone()))
        .with_route(insert_model::route::<S>(state.clone()))
        .with_route(get_console_output::route::<S>(state.clone()))
        .with_route(get_studio_mode::route::<S>(state.clone()))
        .with_route(start_stop_play::route::<S>(state.clone()))
        .with_route(run_script_in_play_mode::route::<S>(state.clone()))
}
