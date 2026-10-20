//! Explicitly reviewed RPG and derived chapter-summary capabilities.
//!
//! reviewed RPG 与派生摘要桥接：预览一次性，发送需显式确认，输出不会直接确认正文。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    /// Full exact materials and a single-use ticket; no key/network access.
    ///
    /// 返回完整精确材料与一次性票据；不读密钥、不发网络。
    pub fn prepare_reviewed_task(&self, request_json: String) -> Result<String, BridgeError> {
        self.inner
            .prepare_reviewed_task(request_json)
            .map_err(Into::into)
    }
    /// One approved fixed-endpoint request. Output never directly confirms prose.
    ///
    /// 只发一次已批准的固定端点请求；输出不会直接确认正文。
    pub async fn send_reviewed_task(
        &self,
        work: String,
        id: String,
        confirmed: bool,
    ) -> Result<String, BridgeError> {
        self.inner
            .send_reviewed_task(work, id, confirmed)
            .await
            .map_err(Into::into)
    }
    /// Revoke an unused preview or in-flight task; no automatic retry.
    ///
    /// 撤销未使用预览或在途任务；不自动重试。
    pub fn cancel_reviewed_task(&self, work: String, id: String) -> Result<(), BridgeError> {
        self.inner
            .cancel_reviewed_task(work, id)
            .map_err(Into::into)
    }
}
