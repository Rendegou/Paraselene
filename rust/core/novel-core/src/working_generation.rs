//! 每个讨论的单次预览票据和可取消运行。这里只管理内存许可，不自行发请求。
use crate::WorkingEditPlan;
use futures_channel::oneshot;
use paraselene_llm_core::{IssuedPreview, PreviewLedger};
use std::{
    collections::HashMap,
    time::{Duration, Instant},
};

struct Pending {
    plan: WorkingEditPlan,
    ledger: PreviewLedger,
    issued: Instant,
}
struct Running {
    work_id: String,
    thread_id: String,
    cancel: oneshot::Sender<()>,
}
pub struct WorkingRun {
    pub plan: WorkingEditPlan,
    pub cancel: oneshot::Receiver<()>,
}

#[derive(Default)]
pub struct WorkingGenerationState {
    pending: HashMap<String, Pending>,
    running: HashMap<String, Running>,
}

impl WorkingGenerationState {
    pub fn issue(&mut self, plan: WorkingEditPlan) -> Result<IssuedPreview, String> {
        self.pending
            .retain(|_, p| p.issued.elapsed() < Duration::from_secs(300));
        if self
            .running
            .values()
            .any(|r| r.work_id == plan.request.work_id && r.thread_id == plan.request.thread_id)
        {
            return Err("当前讨论正在生成，请先取消或等待完成".into());
        }
        if self.pending.len() >= 64 {
            return Err("待确认预览过多，请先关闭不用的预览".into());
        }
        self.pending.retain(|_, p| {
            p.plan.request.work_id != plan.request.work_id
                || p.plan.request.thread_id != plan.request.thread_id
        });
        let mut ledger = PreviewLedger::default();
        let issued = ledger.issue(plan.prepared.clone());
        self.pending.insert(
            issued.id.clone(),
            Pending {
                plan,
                ledger,
                issued: Instant::now(),
            },
        );
        Ok(issued)
    }

    pub fn take(&mut self, work_id: &str, preview_id: &str) -> Result<WorkingRun, String> {
        let pending = self
            .pending
            .get(preview_id)
            .ok_or("预览已失效，请重新查看外发内容")?;
        if pending.plan.request.work_id != work_id {
            return Err("预览不属于当前作品".into());
        }
        let mut pending = self.pending.remove(preview_id).ok_or("预览已失效")?;
        pending.plan.prepared = pending
            .ledger
            .take(preview_id)
            .ok_or("预览已过期，请重新查看外发内容")?;
        let id = pending.plan.request.operation_id.clone();
        if self.running.contains_key(&id) {
            return Err("操作编号重复".into());
        }
        let (sender, cancel) = oneshot::channel();
        self.running.insert(
            id,
            Running {
                work_id: work_id.into(),
                thread_id: pending.plan.request.thread_id.clone(),
                cancel: sender,
            },
        );
        Ok(WorkingRun {
            plan: pending.plan,
            cancel,
        })
    }

    /// 同时作废待发送预览；取消信号被消费后，调用链 drop HTTP 响应流。
    pub fn cancel(&mut self, work_id: &str, operation_id: &str) -> bool {
        let mut cancelled = false;
        self.pending.retain(|_, p| {
            let matches =
                p.plan.request.work_id == work_id && p.plan.request.operation_id == operation_id;
            cancelled |= matches;
            !matches
        });
        if self.is_running(work_id, operation_id) {
            if let Some(running) = self.running.remove(operation_id) {
                let _ = running.cancel.send(());
                cancelled = true;
            }
        }
        cancelled
    }

    pub fn is_running(&self, work_id: &str, operation_id: &str) -> bool {
        self.running
            .get(operation_id)
            .is_some_and(|r| r.work_id == work_id)
    }

    /// 调用者持有状态 Mutex 时核对并收尾；取消先获胜则不执行候选保存。
    pub fn finish<T>(
        &mut self,
        work_id: &str,
        operation_id: &str,
        commit: impl FnOnce() -> Result<T, String>,
    ) -> Result<T, String> {
        if !self.is_running(work_id, operation_id) {
            return Err("生成已取消，未保存候选".into());
        }
        let result = commit();
        self.running.remove(operation_id);
        result
    }
}

/// 取消信号与模型读取竞争；选择取消后立即 drop 另一个 future 及其 HTTP 流。
pub async fn collect_cancellable(
    cancel: oneshot::Receiver<()>,
    generate: impl std::future::Future<Output = Result<String, String>>,
) -> Result<String, String> {
    match futures_util::future::select(Box::pin(cancel), Box::pin(generate)).await {
        futures_util::future::Either::Left(_) => Err("生成已取消，未保存候选".into()),
        futures_util::future::Either::Right((result, _)) => result,
    }
}
