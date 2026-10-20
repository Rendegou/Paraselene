//! Official DeepSeek BYOK capability; neither key nor raw network errors return.
//!
//! 官方 DeepSeek BYOK 生成桥接：prepare 只组装消息，send 需显式确认且只发固定端点、不自动重试，
//! 密钥与原始网络错误不返回。
use super::{models::BridgeError, CoreSession};
impl CoreSession {
    /// Explicit isolated credential write.
    ///
    /// 显式写入隔离凭据；空值或超长返回 invalid_input。
    pub fn set_deepseek_key(&self, key: String) -> Result<(), BridgeError> {
        self.inner.set_deepseek_key(key).map_err(Into::into)
    }
    /// Explicit presence query; never a startup action.
    ///
    /// 只查询凭据存在性，绝不在启动时自动调用。
    pub fn has_deepseek_key(&self) -> Result<bool, BridgeError> {
        self.inner.has_deepseek_key().map_err(Into::into)
    }
    /// Explicit isolated credential deletion.
    ///
    /// 显式删除隔离凭据；条目不存在也算成功。
    pub fn delete_deepseek_key(&self) -> Result<(), BridgeError> {
        self.inner.delete_deepseek_key().map_err(Into::into)
    }
    /// Opt-in cloud gate. Does not send a request.
    ///
    /// 云端开关为 opt-in；开启本身不发送请求。
    pub fn set_cloud_enabled(&self, value: bool) -> Result<(), BridgeError> {
        self.inner.set_cloud_enabled(value).map_err(Into::into)
    }
    /// Invalidates old chapter previews/runs on navigation.
    ///
    /// 导航时使旧章节的预览与在途运行失效。
    pub fn activate_generation_scope(
        &self,
        work: Option<String>,
        chapter: Option<String>,
    ) -> Result<(), BridgeError> {
        self.inner
            .activate_generation_scope(work, chapter)
            .map_err(Into::into)
    }
    /// Full exact messages and one-use preview ticket; no network/key access.
    ///
    /// 返回完整消息预览与一次性票据；不读取密钥、不发网络。
    pub fn prepare_generation(&self, request_json: String) -> Result<String, BridgeError> {
        self.inner
            .prepare_generation(request_json)
            .map_err(Into::into)
    }
    /// Explicit approved send to the official endpoint only; never retried.
    ///
    /// 只向官方固定端点发送已批准请求；不自动重试。
    pub async fn send_generation(
        &self,
        work: String,
        preview_id: String,
        confirmed: bool,
    ) -> Result<(), BridgeError> {
        self.inner
            .send_generation(work, preview_id, confirmed)
            .await
            .map_err(Into::into)
    }
    /// Explicit cancellation, including unused preview tickets.
    ///
    /// 显式取消，包括尚未使用的预览票据。
    pub fn cancel_generation(&self, work: String, operation_id: String) -> Result<(), BridgeError> {
        self.inner
            .cancel_generation(work, operation_id)
            .map_err(Into::into)
    }
}
