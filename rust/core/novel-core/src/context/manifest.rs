//! 上下文 manifest：逐项记录实际装配的内容、来源版本、估算 token、
//! 以及被省略的条目与原因。预览与外发审计只信这份清单（§6 流水线第 6 步）。

use serde::{Deserialize, Serialize};

use super::budget::EstimatorInfo;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ContextLayer {
    /// 必需：系统指令、人物卡与禁忌等硬约束、未决议题。
    HardConstraints,
    /// 必需：当前选段或目标章正文。
    Selection,
    /// 相关设定（lore 确认条目）。
    Lore,
    /// 原文检索证据（截至当前章序）。
    Retrieval,
    /// 章节/卷摘要（派生物，ready 才用）。
    Summary,
    /// 可省略的近期对话/互动历史。
    Chat,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextItem {
    pub layer: ContextLayer,
    /// 来源标识：document:<id> / lore:<id> / summary:<id> / chat:<scope>。
    pub source_id: String,
    /// 绑定版本（可空层如 chat 无版本）。
    pub source_version: Option<String>,
    /// 正文片段（JSON 转义后入消息；manifest 保留原文便于审计）。
    pub body: String,
    pub chars: u64,
    pub estimated_tokens: u64,
}

/// 一个因配额或有效性而被省略的条目。reason 面向用户可读：
/// 审计与预览要能说清"为什么这项没进上下文"。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct OmittedItem {
    pub layer: ContextLayer,
    pub source_id: String,
    pub reason: String,
}

/// 一次装配的完整清单：实际装入的条目、被省略的条目及原因、
/// 总估算 token 与预算。预览与外发审计只信这份清单（§6 流水线第 6 步）。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ContextManifest {
    /// 实际装入的条目（含来源版本与估算 token）。
    pub items: Vec<ContextItem>,
    /// 因配额不足等原因未装入的条目；reason 必须面向用户可读。
    pub omitted: Vec<OmittedItem>,
    /// 全部装入条目的估算 token 合计（含必需层）。
    pub total_estimated_tokens: u64,
    /// 本次装配的总预算，与 total 对照展示"预计"。
    pub budget_total: u64,
    /// 使用的估算器身份与裕量，随清单外发可见。
    pub estimator: EstimatorInfo,
}

impl ContextManifest {
    /// 单层估算 token 合计；UI 按层展示预算占用。
    pub fn layer_tokens(&self, layer: ContextLayer) -> u64 {
        self.items
            .iter()
            .filter(|item| item.layer == layer)
            .map(|item| item.estimated_tokens)
            .sum()
    }
}

#[cfg(test)]
mod tests {
    use super::super::budget::{estimate_tokens, chinese_char_estimator};
    use super::*;

    #[test]
    fn manifest分层计数与省略记录() {
        let est = chinese_char_estimator();
        let item = |layer: ContextLayer, body: &str| ContextItem {
            layer,
            source_id: "document:x".into(),
            source_version: Some("v1".into()),
            chars: body.chars().count() as u64,
            estimated_tokens: estimate_tokens(&est, body),
            body: body.to_string(),
        };
        let manifest = ContextManifest {
            items: vec![
                item(ContextLayer::HardConstraints, "人物卡"),
                item(ContextLayer::Retrieval, "相关段落"),
                item(ContextLayer::Retrieval, "更多证据"),
            ],
            omitted: vec![OmittedItem {
                layer: ContextLayer::Summary,
                source_id: "summary:3".into(),
                reason: "摘要过期（依赖第3章已变化）".into(),
            }],
            total_estimated_tokens: 100,
            budget_total: 1000,
            estimator: chinese_char_estimator(),
        };
        assert_eq!(manifest.layer_tokens(ContextLayer::Retrieval), 2 * estimate_tokens(&est, "相关段落"));
        assert_eq!(manifest.omitted.len(), 1);
    }
}
