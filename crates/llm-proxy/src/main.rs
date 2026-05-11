use std::sync::Arc;

use anyhow::{Context, Result};
use axum::Router;
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::EnvFilter;

mod config;
mod proxy;
mod scheduler;

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let config_path = std::env::var("LLM_PROXY_CONFIG")
        .unwrap_or_else(|_| "/etc/llm-proxy/config.toml".to_string());
    let cfg = config::load(&config_path).with_context(|| format!("loading {config_path}"))?;
    info!(?cfg.bind, "starting llm-proxy");

    if let Some(addr) = cfg.prometheus_bind {
        metrics_exporter_prometheus::PrometheusBuilder::new()
            .with_http_listener(addr)
            .install_recorder()
            .expect("failed to install prometheus recorder");
        info!(%addr, "prometheus metrics enabled");
    }

    let scheduler = scheduler::Scheduler::new(cfg.etcd.clone(), cfg.scheduler.clone()).await;
    let state = Arc::new(proxy::AppState::new(cfg, scheduler)?);

    let app = Router::new()
        .route(
            "/v1/immediate/chat/completions",
            axum::routing::post(proxy::immediate_chat_completions),
        )
        .route(
            "/v1/batch/{slack_ms}/chat/completions",
            axum::routing::post(proxy::batch_chat_completions),
        )
        .route(
            "/v1/immediate/models",
            axum::routing::get(proxy::list_models),
        )
        .route(
            "/v1/batch/{slack_ms}/models",
            axum::routing::get(proxy::list_models),
        )
        .with_state(state.clone());

    let listener = TcpListener::bind(state.bind).await?;
    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await?;
    Ok(())
}

async fn shutdown_signal() {
    use tokio::signal::unix::{SignalKind, signal};
    let mut sigterm = signal(SignalKind::terminate()).expect("install SIGTERM handler");
    let mut sigint = signal(SignalKind::interrupt()).expect("install SIGINT handler");
    tokio::select! {
        _ = sigterm.recv() => {}
        _ = sigint.recv() => {}
    }
    info!("shutdown signal received");
}
