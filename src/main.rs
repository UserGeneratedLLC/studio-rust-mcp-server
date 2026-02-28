use axum::routing::get;
use color_eyre::eyre::Result;
use rbx_studio_server::{ws_handler, RBXStudioServer, STUDIO_PLUGIN_PORT};
use rmcp::transport::streamable_http_server::{
    session::local::LocalSessionManager,
    tower::{StreamableHttpServerConfig, StreamableHttpService},
};
use server_state::AppState;
use std::net::Ipv4Addr;
use std::sync::Arc;
use tokio::sync::Mutex;
use tracing_subscriber::{self, EnvFilter};

mod error;
mod rbx_studio_server;
mod server_state;
mod tools;

fn install_plugin() {
    let plugin_bytes = include_bytes!(concat!(env!("OUT_DIR"), "/MCPStudioPlugin.rbxm"));
    let studio = match roblox_install::RobloxStudio::locate() {
        Ok(s) => s,
        Err(e) => {
            tracing::warn!("Could not locate Roblox Studio: {e}");
            return;
        }
    };
    let plugins = studio.plugins_path();
    if let Err(e) = std::fs::create_dir_all(plugins) {
        tracing::warn!("Could not create plugins directory: {e}");
        return;
    }
    let output = plugins.join("MCPStudioPlugin.rbxm");
    if let Err(e) = std::fs::write(&output, plugin_bytes) {
        tracing::warn!("Could not write plugin: {e}");
        return;
    }
    tracing::info!("Installed plugin to {}", output.display());
}

#[tokio::main]
async fn main() -> Result<()> {
    color_eyre::install()?;
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::from_default_env())
        .with_target(false)
        .with_thread_ids(true)
        .init();

    install_plugin();

    let app_state = Arc::new(Mutex::new(AppState::new()));

    let mcp_state = app_state.clone();
    let mcp_service = StreamableHttpService::new(
        move || Ok(RBXStudioServer::new(mcp_state.clone())),
        Arc::new(LocalSessionManager::default()),
        StreamableHttpServerConfig::default(),
    );

    let app = axum::Router::new()
        .route("/ws", get(ws_handler))
        .nest_service("/mcp", mcp_service)
        .with_state(app_state);

    let listener =
        tokio::net::TcpListener::bind((Ipv4Addr::new(127, 0, 0, 1), STUDIO_PLUGIN_PORT)).await?;
    tracing::info!("MCP server listening on http://127.0.0.1:{STUDIO_PLUGIN_PORT}");
    tracing::info!("  WebSocket endpoint: ws://127.0.0.1:{STUDIO_PLUGIN_PORT}/ws");
    tracing::info!("  MCP endpoint: http://127.0.0.1:{STUDIO_PLUGIN_PORT}/mcp");

    axum::serve(listener, app).await?;

    Ok(())
}
