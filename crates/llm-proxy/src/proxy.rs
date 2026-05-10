use std::collections::HashMap;
use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use anyhow::{Result, anyhow};
use axum::body::Body;
use axum::extract::{Path, State};
use axum::http::{HeaderMap, HeaderName, HeaderValue, StatusCode};
use axum::response::Response;
use bytes::Bytes;
use futures_util::StreamExt;
use tracing::{info, warn};

use crate::config::{self, Config, ResolvedProvider};
use crate::scheduler::{Scheduler, Tier, TimedResponse};

pub struct AppState {
    pub bind: SocketAddr,
    pub scheduler: Scheduler,
    pub providers: HashMap<String, ResolvedProvider>,
    /// Logical model name -> (provider key, upstream model name).
    pub model_index: HashMap<String, (String, String)>,
    pub http: reqwest::Client,
}

impl AppState {
    pub fn new(cfg: Config, scheduler: Scheduler) -> Result<Self> {
        let mut providers = HashMap::new();
        let mut model_index: HashMap<String, (String, String)> = HashMap::new();
        for (name, p) in &cfg.providers {
            let resolved = config::resolve_provider(p)?;
            for (logical, upstream) in &resolved.models {
                if let Some((existing, _)) = model_index.get(logical) {
                    return Err(anyhow!(
                        "model {logical:?} is declared by both {existing:?} and {name:?}"
                    ));
                }
                model_index.insert(logical.clone(), (name.clone(), upstream.clone()));
            }
            providers.insert(name.clone(), resolved);
        }
        let http = reqwest::Client::builder()
            .pool_idle_timeout(std::time::Duration::from_secs(90))
            .build()?;
        Ok(Self {
            bind: cfg.bind,
            scheduler,
            providers,
            model_index,
            http,
        })
    }
}

pub async fn immediate_chat_completions(
    State(state): State<Arc<AppState>>,
    body: Bytes,
) -> Response {
    handle(state, Tier::Immediate, body).await
}

pub async fn batch_chat_completions(
    State(state): State<Arc<AppState>>,
    Path(slack_ms): Path<String>,
    body: Bytes,
) -> Response {
    let slack_ms: i64 = match slack_ms.parse() {
        Ok(n) => n,
        Err(_) => {
            return error_response(StatusCode::BAD_REQUEST, "slack_ms must be a signed integer");
        }
    };
    handle(state, Tier::Batch { slack_ms }, body).await
}

pub async fn list_models(State(state): State<Arc<AppState>>) -> Response {
    let started = Instant::now();
    let mut data: Vec<serde_json::Value> = state
        .model_index
        .iter()
        .map(|(logical, (provider, _upstream))| {
            serde_json::json!({
                "id": logical,
                "object": "model",
                "owned_by": provider,
            })
        })
        .collect();
    data.sort_by(|a, b| {
        a["id"]
            .as_str()
            .unwrap_or("")
            .cmp(b["id"].as_str().unwrap_or(""))
    });
    let body = serde_json::json!({ "object": "list", "data": data });
    let mut resp = Response::new(Body::from(body.to_string()));
    resp.headers_mut().insert(
        HeaderName::from_static("content-type"),
        HeaderValue::from_static("application/json"),
    );
    info!(
        endpoint = "models",
        count = state.model_index.len(),
        elapsed_ms = started.elapsed().as_millis() as u64,
        "request",
    );
    resp
}

async fn handle(state: Arc<AppState>, tier: Tier, body: Bytes) -> Response {
    let started = Instant::now();
    let (response, ctx) = handle_inner(state, tier, body).await;
    log_request(tier, &ctx, &response, started.elapsed());
    response
}

#[derive(Default)]
struct LogCtx {
    logical_model: Option<String>,
    provider: Option<String>,
    upstream_model: Option<String>,
    wait_ms: u64,
    hold_ms: u64,
}

async fn handle_inner(state: Arc<AppState>, tier: Tier, body: Bytes) -> (Response, LogCtx) {
    let mut ctx = LogCtx::default();

    let logical_model = match parse_model(&body) {
        Ok(m) => m,
        Err(e) => return (error_response(StatusCode::BAD_REQUEST, &e.to_string()), ctx),
    };
    ctx.logical_model = Some(logical_model.clone());

    let (provider_name, upstream_model) = match state.model_index.get(&logical_model) {
        Some(v) => v.clone(),
        None => {
            return (
                error_response(
                    StatusCode::BAD_REQUEST,
                    &format!("unknown model {logical_model:?}"),
                ),
                ctx,
            );
        }
    };
    ctx.provider = Some(provider_name.clone());
    ctx.upstream_model = Some(upstream_model.clone());

    let provider = state
        .providers
        .get(&provider_name)
        .expect("model_index points at a known provider");

    let rewritten = match rewrite_model(&body, &upstream_model) {
        Ok(v) => v,
        Err(e) => return (error_response(StatusCode::BAD_REQUEST, &e.to_string()), ctx),
    };

    let url = format!("{}/chat/completions", provider.url);
    let client = state.http.clone();
    let api_key = provider.api_key.clone();

    let send = || {
        let url = url.clone();
        let client = client.clone();
        let api_key = api_key.clone();
        let body_bytes = rewritten.clone();
        async move {
            client
                .post(&url)
                .bearer_auth(&api_key)
                .header("content-type", "application/json")
                .body(body_bytes)
                .send()
                .await
        }
    };

    let timed = match state
        .scheduler
        .run(&provider_name, &upstream_model, tier, send)
        .await
    {
        Ok(r) => r,
        Err(e) => {
            warn!(error = %e, "upstream request failed");
            return (
                error_response(StatusCode::BAD_GATEWAY, &format!("upstream: {e}")),
                ctx,
            );
        }
    };

    ctx.wait_ms = timed.wait_ms;
    ctx.hold_ms = timed.hold_ms;

    (forward_response(timed.response), ctx)
}

fn log_request(tier: Tier, ctx: &LogCtx, response: &Response, elapsed: Duration) {
    let tier_str = match tier {
        Tier::Immediate => "immediate".to_string(),
        Tier::Batch { slack_ms } => format!("batch:{slack_ms}"),
    };
    info!(
        tier = %tier_str,
        logical_model = ctx.logical_model.as_deref().unwrap_or("-"),
        provider = ctx.provider.as_deref().unwrap_or("-"),
        upstream_model = ctx.upstream_model.as_deref().unwrap_or("-"),
        status = response.status().as_u16(),
        elapsed_ms = elapsed.as_millis() as u64,
        wait_ms = ctx.wait_ms,
        hold_ms = ctx.hold_ms,
        "request",
    );
}

fn forward_response(resp: reqwest::Response) -> Response {
    let status =
        StatusCode::from_u16(resp.status().as_u16()).unwrap_or(StatusCode::INTERNAL_SERVER_ERROR);
    let mut headers = HeaderMap::new();
    for (name, value) in resp.headers() {
        if is_hop_header(name.as_str()) {
            continue;
        }
        if let (Ok(name), Ok(val)) = (
            HeaderName::from_bytes(name.as_str().as_bytes()),
            HeaderValue::from_bytes(value.as_bytes()),
        ) {
            headers.insert(name, val);
        }
    }
    // Convert a mid-body upstream error into a clean end-of-stream so hyper
    // emits the terminator chunk. Strict clients (aiohttp) reject a chunked
    // body that ends without it; lenient clients silently truncate. We
    // prefer truncation either way.
    let stream = resp.bytes_stream().filter_map(|item| async move {
        match item {
            Ok(b) => Some(Ok::<Bytes, std::convert::Infallible>(b)),
            Err(e) => {
                warn!(error = %e, "upstream body stream error; truncating response");
                None
            }
        }
    });
    let body = Body::from_stream(stream);
    let mut response = Response::new(body);
    *response.status_mut() = status;
    *response.headers_mut() = headers;
    response
}

fn is_hop_header(name: &str) -> bool {
    matches!(
        name.to_ascii_lowercase().as_str(),
        "connection"
            | "keep-alive"
            | "proxy-authenticate"
            | "proxy-authorization"
            | "te"
            | "trailer"
            | "transfer-encoding"
            | "upgrade"
            | "content-length"
    )
}

fn error_response(status: StatusCode, msg: &str) -> Response {
    let body = serde_json::json!({ "error": { "message": msg } });
    let mut resp = Response::new(Body::from(body.to_string()));
    *resp.status_mut() = status;
    resp.headers_mut().insert(
        HeaderName::from_static("content-type"),
        HeaderValue::from_static("application/json"),
    );
    resp
}

fn parse_model(body: &Bytes) -> Result<String> {
    let v: serde_json::Value =
        serde_json::from_slice(body).map_err(|e| anyhow!("invalid JSON body: {e}"))?;
    Ok(v.get("model")
        .and_then(|m| m.as_str())
        .ok_or_else(|| anyhow!("missing 'model' field"))?
        .to_string())
}

fn rewrite_model(body: &Bytes, upstream_model: &str) -> Result<Bytes> {
    let mut v: serde_json::Value =
        serde_json::from_slice(body).map_err(|e| anyhow!("invalid JSON body: {e}"))?;
    v["model"] = serde_json::Value::String(upstream_model.to_string());
    let bytes = serde_json::to_vec(&v).map_err(|e| anyhow!("encode JSON: {e}"))?;
    Ok(Bytes::from(bytes))
}
