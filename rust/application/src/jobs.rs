//! Cancellable caller-owned futures and bounded subscriptions.
//!
//! 合成任务以调用方持有的 future 运行，不产生后台线程；取消信号优先于终端状态提交，
//! 终端结果保存在每会话最多 256 条的 outcomes 中。订阅队列有界并统计因溢出丢弃的最旧事件数。
use crate::{err, AppError, EventBatch, JobResult, Queue, Session, State};
use std::collections::VecDeque;
use tokio::sync::watch;
struct Registration {
    session: Session,
    id: String,
}
// outcomes 保留终态以便队列溢出后仍可查询；队列满时丢弃最旧事件并累计 dropped。
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
// future 被抛弃时没有显式取消机会；Drop 统一补写 cancelled（会话已关闭则 closed）终态。
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
    ///
    /// 即使会话关闭或通知队列溢出也返回权威终态；未知 id 返回 job_not_found。
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
    ///
    /// job_id 仅允许 ASCII 字母数字与 '-' 且不超过 128 字节，delay 为 0..=60000 毫秒；
    /// 重复 id 返回 job_exists，超过 256 个终态返回 job_limit。
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
        // biased 让取消信号优先于定时器，取消一定赢过同一轮的完成提交。
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
    ///
    /// 只取消 pending 任务；已完成返回 job_finished，未知返回 job_not_found。
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
    ///
    /// capacity 范围 1..=256；每个会话最多 64 个订阅，超限返回 subscription_limit。
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
    ///
    /// 原子排空队列并重置 dropped 计数；未知订阅返回 subscription_not_found。
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
    ///
    /// 幂等移除订阅；返回后不会再向该队列发布事件。
    pub fn unsubscribe(&self, subscription: u64) -> Result<(), AppError> {
        self.lock()?.events.remove(&subscription);
        Ok(())
    }
}
