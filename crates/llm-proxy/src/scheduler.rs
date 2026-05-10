use std::future::Future;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use anyhow::{Context, Result};
use etcd_client::{Client, GetOptions, PutOptions, SortOrder, SortTarget, WatchOptions};
use rand::Rng;
use tokio::task::JoinHandle;
use tracing::{debug, warn};

use crate::config::{EtcdConfig, SchedulerConfig};

#[derive(Debug, Clone, Copy)]
pub enum Tier {
    Immediate,
    /// Signed slack in milliseconds. Effective deadline = enqueue_time + slack_ms;
    /// negative slack jumps ahead of any task arriving at the same instant.
    Batch {
        slack_ms: i64,
    },
}

pub struct TimedResponse {
    pub response: reqwest::Response,
    pub wait_ms: u64,
    pub hold_ms: u64,
}

#[derive(Clone)]
pub struct Scheduler {
    cfg: SchedulerConfig,
    endpoints: Vec<String>,
}

impl Scheduler {
    pub async fn new(etcd: EtcdConfig, cfg: SchedulerConfig) -> Self {
        Self {
            cfg,
            endpoints: etcd.endpoints,
        }
    }

    pub async fn run<F, Fut>(
        &self,
        provider: &str,
        upstream_model: &str,
        tier: Tier,
        attempt: F,
    ) -> reqwest::Result<TimedResponse>
    where
        F: FnMut() -> Fut + Send,
        Fut: Future<Output = reqwest::Result<reqwest::Response>> + Send,
    {
        match tier {
            Tier::Immediate => self.run_immediate(provider, upstream_model, attempt).await,
            Tier::Batch { slack_ms } => {
                let deadline_ms = unix_millis().saturating_add(slack_ms);
                self.run_batch(provider, upstream_model, deadline_ms, attempt)
                    .await
            }
        }
    }

    async fn run_immediate<F, Fut>(
        &self,
        provider: &str,
        upstream_model: &str,
        mut attempt: F,
    ) -> reqwest::Result<TimedResponse>
    where
        F: FnMut() -> Fut + Send,
        Fut: Future<Output = reqwest::Result<reqwest::Response>> + Send,
    {
        // Happy path: no etcd interaction.
        let resp = attempt().await?;
        if resp.status().as_u16() != 429 {
            return Ok(TimedResponse {
                response: resp,
                wait_ms: 0,
                hold_ms: 0,
            });
        }

        // 429: register a fleet-wide marker so batch tasks on this (provider, model) yield.
        let mut etcd_state = self.connect_for_marker(provider, upstream_model).await;
        let mut backoff_ms = self.cfg.backoff_initial_ms;
        loop {
            sleep_jittered(backoff_ms, self.cfg.backoff_jitter).await;
            backoff_ms = (backoff_ms.saturating_mul(2)).min(self.cfg.backoff_max_ms);

            let resp = attempt().await?;
            if resp.status().as_u16() != 429 {
                if let Some(state) = etcd_state.take() {
                    state.cleanup().await;
                }
                return Ok(TimedResponse {
                    response: resp,
                    wait_ms: 0,
                    hold_ms: 0,
                });
            }
        }
    }

    async fn run_batch<F, Fut>(
        &self,
        provider: &str,
        upstream_model: &str,
        deadline_ms: i64,
        mut attempt: F,
    ) -> reqwest::Result<TimedResponse>
    where
        F: FnMut() -> Fut + Send,
        Fut: Future<Output = reqwest::Result<reqwest::Response>> + Send,
    {
        let started = Instant::now();
        let mut hold_ms = 0u64;
        let mut hold_start: Option<Instant> = None;

        let mut state = match self
            .enqueue_batch(provider, upstream_model, deadline_ms)
            .await
        {
            Some(s) => s,
            None => {
                let resp = attempt().await?;
                return Ok(TimedResponse {
                    response: resp,
                    wait_ms: 0,
                    hold_ms: 0,
                });
            }
        };

        let batch_pfx = batch_prefix(provider, upstream_model);
        let imm_pfx = immediate_prefix(provider, upstream_model);

        // Watches span the lifetime of this run so events that arrive between
        // checks (or during an in-flight attempt) aren't missed.
        let (_batch_watcher, mut batch_stream) = match state
            .client
            .watch(
                batch_pfx.as_bytes(),
                Some(WatchOptions::new().with_prefix()),
            )
            .await
        {
            Ok(v) => v,
            Err(e) => {
                warn!(error = %e, "opening batch watch failed; bypassing scheduler");
                state.cleanup().await;
                let resp = attempt().await?;
                let total = started.elapsed().as_millis() as u64;
                return Ok(TimedResponse {
                    response: resp,
                    wait_ms: total - hold_ms,
                    hold_ms,
                });
            }
        };
        let (_imm_watcher, mut imm_stream) = match state
            .client
            .watch(imm_pfx.as_bytes(), Some(WatchOptions::new().with_prefix()))
            .await
        {
            Ok(v) => v,
            Err(e) => {
                warn!(error = %e, "opening immediate watch failed; bypassing scheduler");
                state.cleanup().await;
                let resp = attempt().await?;
                let total = started.elapsed().as_millis() as u64;
                return Ok(TimedResponse {
                    response: resp,
                    wait_ms: total - hold_ms,
                    hold_ms,
                });
            }
        };

        let mut backoff_ms = self.cfg.backoff_initial_ms;
        loop {
            // Wait until I'm the head of the batch queue and no immediate is active.
            loop {
                match state.can_proceed(&batch_pfx, &imm_pfx).await {
                    Ok(true) => {
                        hold_start = Some(Instant::now());
                        break;
                    }
                    Ok(false) => {}
                    Err(e) => {
                        warn!(error = %e, "etcd can_proceed failed; bypassing scheduler");
                        state.cleanup().await;
                        if let Some(start) = hold_start.take() {
                            hold_ms += start.elapsed().as_millis() as u64;
                        }
                        let resp = attempt().await?;
                        let total = started.elapsed().as_millis() as u64;
                        return Ok(TimedResponse {
                            response: resp,
                            wait_ms: total - hold_ms,
                            hold_ms,
                        });
                    }
                }
                tokio::select! {
                    msg = batch_stream.message() => {
                        if let Err(e) = msg {
                            warn!(error = %e, "batch watch error; bypassing scheduler");
                            state.cleanup().await;
                            if let Some(start) = hold_start.take() {
                                hold_ms += start.elapsed().as_millis() as u64;
                            }
                            let resp = attempt().await?;
                            let total = started.elapsed().as_millis() as u64;
                            return Ok(TimedResponse {
                                response: resp,
                                wait_ms: total - hold_ms,
                                hold_ms,
                            });
                        }
                    }
                    msg = imm_stream.message() => {
                        if let Err(e) = msg {
                            warn!(error = %e, "immediate watch error; bypassing scheduler");
                            state.cleanup().await;
                            if let Some(start) = hold_start.take() {
                                hold_ms += start.elapsed().as_millis() as u64;
                            }
                            let resp = attempt().await?;
                            let total = started.elapsed().as_millis() as u64;
                            return Ok(TimedResponse {
                                response: resp,
                                wait_ms: total - hold_ms,
                                hold_ms,
                            });
                        }
                    }
                }
            }

            let resp = attempt().await?;
            if resp.status().as_u16() != 429 {
                state.cleanup().await;
                if let Some(start) = hold_start.take() {
                    hold_ms += start.elapsed().as_millis() as u64;
                }
                let total = started.elapsed().as_millis() as u64;
                return Ok(TimedResponse {
                    response: resp,
                    wait_ms: total - hold_ms,
                    hold_ms,
                });
            }

            // 429: end this hold slice, then yield back to wait_for_turn.
            if let Some(start) = hold_start.take() {
                hold_ms += start.elapsed().as_millis() as u64;
            }

            // Hold our slot, but yield back to wait_for_turn the moment an
            // immediate marker appears. The lease/key is preserved across the
            // yield, so queue position is retained.
            let sleep_ms = jittered_ms(backoff_ms, self.cfg.backoff_jitter);
            let sleep = tokio::time::sleep(Duration::from_millis(sleep_ms));
            tokio::pin!(sleep);
            tokio::select! {
                _ = &mut sleep => {}
                msg = imm_stream.message() => {
                    if let Err(e) = msg {
                        warn!(error = %e, "immediate watch error; bypassing scheduler");
                        state.cleanup().await;
                        let resp = attempt().await?;
                        let total = started.elapsed().as_millis() as u64;
                        return Ok(TimedResponse {
                            response: resp,
                            wait_ms: total - hold_ms,
                            hold_ms,
                        });
                    }
                }
            }
            backoff_ms = (backoff_ms.saturating_mul(2)).min(self.cfg.backoff_max_ms);
        }
    }

    async fn try_connect(&self) -> Option<Client> {
        if self.endpoints.is_empty() {
            return None;
        }
        match Client::connect(&self.endpoints, None).await {
            Ok(c) => Some(c),
            Err(e) => {
                warn!(error = %e, "etcd connect failed; bypassing scheduler");
                None
            }
        }
    }

    async fn connect_for_marker(
        &self,
        provider: &str,
        upstream_model: &str,
    ) -> Option<MarkerState> {
        let mut client = self.try_connect().await?;
        match register_immediate_marker(
            &mut client,
            provider,
            upstream_model,
            self.cfg.lease_ttl_secs,
        )
        .await
        {
            Ok((lease_id, key, ka)) => Some(MarkerState {
                client,
                lease_id,
                key,
                keepalive: Some(ka),
            }),
            Err(e) => {
                warn!(error = %e, "registering immediate marker failed; proceeding without fleet coordination");
                None
            }
        }
    }

    async fn enqueue_batch(
        &self,
        provider: &str,
        upstream_model: &str,
        deadline_ms: i64,
    ) -> Option<BatchState> {
        let mut client = self.try_connect().await?;
        match register_batch_key(
            &mut client,
            provider,
            upstream_model,
            deadline_ms,
            self.cfg.lease_ttl_secs,
        )
        .await
        {
            Ok((lease_id, key, ka)) => Some(BatchState {
                client,
                lease_id,
                key,
                keepalive: Some(ka),
            }),
            Err(e) => {
                warn!(error = %e, "registering batch key failed; bypassing scheduler");
                None
            }
        }
    }
}

struct MarkerState {
    client: Client,
    lease_id: i64,
    #[allow(dead_code)]
    key: String,
    keepalive: Option<JoinHandle<()>>,
}

impl MarkerState {
    async fn cleanup(mut self) {
        if let Some(h) = self.keepalive.take() {
            h.abort();
        }
        if let Err(e) = self.client.lease_revoke(self.lease_id).await {
            debug!(error = %e, "lease revoke (immediate marker) failed");
        }
    }
}

impl Drop for MarkerState {
    // If the future is dropped before cleanup() runs (e.g. caller cancelled,
    // attempt errored), abort the keepalive so the lease can expire naturally.
    fn drop(&mut self) {
        if let Some(h) = self.keepalive.take() {
            h.abort();
        }
    }
}

struct BatchState {
    client: Client,
    lease_id: i64,
    key: String,
    keepalive: Option<JoinHandle<()>>,
}

impl BatchState {
    async fn can_proceed(&mut self, batch_prefix: &str, immediate_prefix: &str) -> Result<bool> {
        let head = self
            .client
            .get(
                batch_prefix.as_bytes(),
                Some(
                    GetOptions::new()
                        .with_prefix()
                        .with_sort(SortTarget::Key, SortOrder::Ascend)
                        .with_limit(1),
                ),
            )
            .await
            .context("getting batch head")?;
        let head_key = head
            .kvs()
            .first()
            .map(|kv| std::str::from_utf8(kv.key()).unwrap_or_default());
        if head_key != Some(self.key.as_str()) {
            return Ok(false);
        }

        let imm = self
            .client
            .get(
                immediate_prefix.as_bytes(),
                Some(GetOptions::new().with_prefix().with_count_only()),
            )
            .await
            .context("counting immediate markers")?;
        Ok(imm.count() == 0)
    }

    async fn cleanup(mut self) {
        if let Some(h) = self.keepalive.take() {
            h.abort();
        }
        if let Err(e) = self.client.lease_revoke(self.lease_id).await {
            debug!(error = %e, "lease revoke (batch) failed");
        }
    }
}

impl Drop for BatchState {
    fn drop(&mut self) {
        if let Some(h) = self.keepalive.take() {
            h.abort();
        }
    }
}

async fn register_immediate_marker(
    client: &mut Client,
    provider: &str,
    upstream_model: &str,
    ttl_secs: i64,
) -> Result<(i64, String, JoinHandle<()>)> {
    let lease = client
        .lease_grant(ttl_secs, None)
        .await
        .context("lease grant")?;
    let lease_id = lease.id();
    let key = format!(
        "{}{}",
        immediate_prefix(provider, upstream_model),
        hex_id(lease_id)
    );
    client
        .put(
            key.as_bytes(),
            "",
            Some(PutOptions::new().with_lease(lease_id)),
        )
        .await
        .context("put immediate marker")?;
    let ka = spawn_keepalive(client.clone(), lease_id, ttl_secs);
    Ok((lease_id, key, ka))
}

async fn register_batch_key(
    client: &mut Client,
    provider: &str,
    upstream_model: &str,
    deadline_ms: i64,
    ttl_secs: i64,
) -> Result<(i64, String, JoinHandle<()>)> {
    let lease = client
        .lease_grant(ttl_secs, None)
        .await
        .context("lease grant")?;
    let lease_id = lease.id();
    let key = format!(
        "{}{}/{}",
        batch_prefix(provider, upstream_model),
        deadline_offset(deadline_ms),
        hex_id(lease_id)
    );
    client
        .put(
            key.as_bytes(),
            "",
            Some(PutOptions::new().with_lease(lease_id)),
        )
        .await
        .context("put batch key")?;
    let ka = spawn_keepalive(client.clone(), lease_id, ttl_secs);
    Ok((lease_id, key, ka))
}

fn spawn_keepalive(mut client: Client, lease_id: i64, ttl_secs: i64) -> JoinHandle<()> {
    let interval = Duration::from_secs(((ttl_secs / 3).max(1)) as u64);
    tokio::spawn(async move {
        let (mut keeper, mut stream) = match client.lease_keep_alive(lease_id).await {
            Ok(v) => v,
            Err(e) => {
                warn!(error = %e, lease_id, "lease keepalive setup failed");
                return;
            }
        };
        let mut ticker = tokio::time::interval(interval);
        ticker.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Delay);
        loop {
            ticker.tick().await;
            if keeper.keep_alive().await.is_err() {
                return;
            }
            if let Err(e) = stream.message().await {
                warn!(error = %e, lease_id, "lease keepalive recv failed");
                return;
            }
        }
    })
}

fn immediate_prefix(provider: &str, upstream_model: &str) -> String {
    format!("/llm-proxy/{provider}/{upstream_model}/immediate/")
}

fn batch_prefix(provider: &str, upstream_model: &str) -> String {
    format!("/llm-proxy/{provider}/{upstream_model}/batch/")
}

// Bias signed i64 deadline-millis into the unsigned space so etcd's lex sort
// matches numeric order across the full range. 20 digits fits 2^64.
fn deadline_offset(deadline_ms: i64) -> String {
    let biased = (deadline_ms as i128) + (1i128 << 63);
    format!("{biased:020}")
}

fn hex_id(id: i64) -> String {
    format!("{:016x}", id as u64)
}

fn unix_millis() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_millis() as i64)
        .unwrap_or(0)
}

fn jittered_ms(base_ms: u64, jitter: f64) -> u64 {
    let factor = {
        let mut rng = rand::thread_rng();
        1.0 + rng.gen_range(-jitter..jitter)
    };
    ((base_ms as f64) * factor).max(0.0) as u64
}

async fn sleep_jittered(base_ms: u64, jitter: f64) {
    tokio::time::sleep(Duration::from_millis(jittered_ms(base_ms, jitter))).await;
}
