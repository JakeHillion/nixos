use std::collections::HashMap;
use std::net::SocketAddr;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result, anyhow};
use serde::Deserialize;

#[derive(Debug, Clone, Deserialize)]
pub struct Config {
    pub bind: SocketAddr,
    pub etcd: EtcdConfig,
    #[serde(default)]
    pub scheduler: SchedulerConfig,
    pub providers: HashMap<String, ProviderConfig>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct EtcdConfig {
    #[serde(default)]
    pub endpoints: Vec<String>,
}

#[derive(Debug, Clone, Deserialize)]
pub struct SchedulerConfig {
    #[serde(default = "default_backoff_initial_ms")]
    pub backoff_initial_ms: u64,
    #[serde(default = "default_backoff_max_ms")]
    pub backoff_max_ms: u64,
    #[serde(default = "default_backoff_jitter")]
    pub backoff_jitter: f64,
    #[serde(default = "default_lease_ttl_secs")]
    pub lease_ttl_secs: i64,
}

impl Default for SchedulerConfig {
    fn default() -> Self {
        Self {
            backoff_initial_ms: default_backoff_initial_ms(),
            backoff_max_ms: default_backoff_max_ms(),
            backoff_jitter: default_backoff_jitter(),
            lease_ttl_secs: default_lease_ttl_secs(),
        }
    }
}

fn default_backoff_initial_ms() -> u64 {
    5_000
}
fn default_backoff_max_ms() -> u64 {
    300_000
}
fn default_backoff_jitter() -> f64 {
    0.25
}
fn default_lease_ttl_secs() -> i64 {
    30
}

#[derive(Debug, Clone, Deserialize)]
pub struct ProviderConfig {
    pub url: String,
    pub api_key_credential: String,
    pub models: HashMap<String, String>,
}

#[derive(Debug, Clone)]
pub struct ResolvedProvider {
    pub url: String,
    pub api_key: String,
    pub models: HashMap<String, String>,
}

pub fn load(path: &str) -> Result<Config> {
    let raw = std::fs::read_to_string(path).with_context(|| format!("reading {path}"))?;
    let mut cfg: Config = toml::from_str(&raw).context("parsing TOML")?;

    if let Ok(env_endpoints) = std::env::var("ETCD_ENDPOINTS") {
        if !env_endpoints.is_empty() {
            cfg.etcd.endpoints = env_endpoints
                .split(',')
                .map(|s| s.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect();
        }
    }
    Ok(cfg)
}

pub fn resolve_provider(cfg: &ProviderConfig) -> Result<ResolvedProvider> {
    let api_key = read_credential(&cfg.api_key_credential)
        .with_context(|| format!("reading credential {:?}", cfg.api_key_credential))?;
    Ok(ResolvedProvider {
        url: cfg.url.trim_end_matches('/').to_string(),
        api_key,
        models: cfg.models.clone(),
    })
}

fn read_credential(name: &str) -> Result<String> {
    let dir = std::env::var_os("CREDENTIALS_DIRECTORY")
        .ok_or_else(|| anyhow!("CREDENTIALS_DIRECTORY not set; expected systemd LoadCredential"))?;
    let path: PathBuf = Path::new(&dir).join(name);
    let raw = std::fs::read_to_string(&path)
        .with_context(|| format!("reading credential file {}", path.display()))?;
    Ok(raw.trim().to_string())
}
