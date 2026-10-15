//! Cancellable caller-owned futures and bounded subscriptions.
use crate::{err, AppError, EventBatch, JobResult, Queue, Session, State};
use std::collections::VecDeque;
use tokio::sync::watch;
struct Registration {
    session: Session,
    id: String,
}
fn publish(state: &mut State, result: JobResult) {
    state.outcomes.insert(result.job_id.clone(), result.clone());
    for queue in state.events.values_mut() {
        if queue.items.len() == queue.capacity {
            queue.items.pop_front();
            queue.dropped += 1;
        }
        queue.items.push_back(result.clone());
    }
}
impl Drop for Registration {
    fn drop(&mut self) {
        if let Ok(mut state) = self.session.inner.lock() {
            state.jobs.remove(&self.id);
            if !state.outcomes.contains_key(&self.id) {
                let status = if state.db.is_none() {
                    "closed"
                } else {
                    "cancelled"
                };
                publish(
                    &mut state,
                    JobResult {
                        job_id: self.id.clone(),
                        status: status.into(),
                    },
                );
            }
        }
    }
}
impl Session {
    /// Query authoritative outcomes even after close or notification overflow.
    /// At most 256 IDs are retained per session; excess jobs fail with job_limit.
    pub fn job_status(&self, job_id: String) -> Result<JobResult, AppError> {
        let state = self.lock()?;
        if let Some(result) = state.outcomes.get(&job_id) {
            return Ok(result.clone());
        }
        let sender = state
            .jobs
            .get(&job_id)
            .ok_or_else(|| err("job_not_found"))?;
        let status = if state.db.is_none() {
            "closed"
        } else if *sender.borrow() {
            "cancelled"
        } else {
            "pending"
        };
        Ok(JobResult {
            job_id,
            status: status.into(),
        })
    }
    fn register_job(&self, job_id: &str, delay_ms: u64) -> Result<watch::Receiver<bool>, AppError> {
        if job_id.is_empty()
            || job_id.len() > 128
            || !job_id
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b == b'-')
            || delay_ms > 60000
        {
            return Err(err("invalid_input"));
        }
        let mut state = self.lock()?;
        if state.db.is_none() {
            return Err(err("session_closed"));
        }
        if state.jobs.contains_key(job_id) || state.outcomes.contains_key(job_id) {
            return Err(err("job_exists"));
        }
        if state.jobs.len() + state.outcomes.len() >= 256 {
            return Err(err("job_limit"));
        }
        let (sender, receiver) = watch::channel(false);
        state.jobs.insert(job_id.into(), sender);
        Ok(receiver)
    }
    /// Await a deterministic delay in milliseconds (0..60000); cancellation wins terminal commit.
    /// Dropping this future cancels it without leaving a spawned background task.
    pub async fn synthetic_job(
        &self,
        job_id: String,
        delay_ms: u64,
    ) -> Result<JobResult, AppError> {
        let mut receiver = self.register_job(&job_id, delay_ms)?;
        let registration = Registration {
            session: self.clone(),
            id: job_id.clone(),
        };
        tokio::select! {biased; _=receiver.changed()=>{}, _=tokio::time::sleep(std::time::Duration::from_millis(delay_ms))=>{},}
        let result = {
            let mut state = self.lock()?;
            let status = if state.db.is_none() {
                "closed"
            } else if *receiver.borrow() {
                "cancelled"
            } else {
                "completed"
            };
            let result = JobResult {
                job_id,
                status: status.into(),
            };
            publish(&mut state, result.clone());
            result
        };
        drop(registration);
        Ok(result)
    }
    /// Cancel a registered pending future; repeated cancellation is harmless.
    pub fn cancel_job(&self, job_id: String) -> Result<(), AppError> {
        let state = self.lock()?;
        if state.db.is_none() {
            return Err(err("session_closed"));
        }
        if state.outcomes.contains_key(&job_id) {
            return Err(err("job_finished"));
        }
        state
            .jobs
            .get(&job_id)
            .ok_or_else(|| err("job_not_found"))?
            .send_replace(true);
        Ok(())
    }
    /// Subscribe to at most 256 events (1..256), with oldest-drop overflow semantics.
    pub fn subscribe(&self, capacity: u32) -> Result<u64, AppError> {
        if !(1..=256).contains(&capacity) {
            return Err(err("invalid_input"));
        }
        let mut state = self.lock()?;
        if state.db.is_none() {
            return Err(err("session_closed"));
        }
        if state.events.len() >= 64 {
            return Err(err("subscription_limit"));
        }
        state.next_subscription = state
            .next_subscription
            .checked_add(1)
            .ok_or_else(|| err("subscription_limit"))?;
        let id = state.next_subscription;
        state.events.insert(
            id,
            Queue {
                capacity: capacity as usize,
                items: VecDeque::new(),
                dropped: 0,
            },
        );
        Ok(id)
    }
    /// Drain a subscription atomically, resetting its dropped count.
    pub fn poll_events(&self, subscription: u64) -> Result<EventBatch, AppError> {
        let mut state = self.lock()?;
        if state.db.is_none() {
            return Err(err("session_closed"));
        }
        let queue = state
            .events
            .get_mut(&subscription)
            .ok_or_else(|| err("subscription_not_found"))?;
        Ok(EventBatch {
            events: queue.items.drain(..).collect(),
            dropped: std::mem::take(&mut queue.dropped),
        })
    }
    /// Remove a subscription idempotently; no callback can run after return.
    pub fn unsubscribe(&self, subscription: u64) -> Result<(), AppError> {
        self.lock()?.events.remove(&subscription);
        Ok(())
    }
}
