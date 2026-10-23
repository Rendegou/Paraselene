//! Token 预算与估算器。规则（context-and-storage §7）：
//! 不把字符数当 token；估算器有名称、版本与误差裕量；UI 显示"预计"。
//! 首版估算器按中文 code point 折算并给裕量，模型/供应商元数据后续接入。

use serde::{Deserialize, Serialize};

/// 估算器身份与误差声明，随 manifest 外发可见。
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EstimatorInfo {
    pub name: String,
    pub version: String,
    /// 估算值上调的百分比（0-100），用于裕量。
    pub margin_percent: u32,
}

/// 首版中文估算器：1 token ≈ 1.6 code point，再上调 20% 裕量。
pub fn chinese_char_estimator() -> EstimatorInfo {
    EstimatorInfo {
        name: "chinese-char-v1".to_string(),
        version: "1.0.0".to_string(),
        margin_percent: 20,
    }
}

/// 按 code point 估算 token 并加上裕量。
pub fn estimate_tokens(estimator: &EstimatorInfo, text: &str) -> u64 {
    let chars = text.chars().count() as u64;
    let base = chars.div_ceil(16) * 10; // ×10/16，向上取整到 10
    base + base * estimator.margin_percent as u64 / 100
}

/// 默认上下文总预算（token）。来源：配置项接入前的保守默认；T05H 前接入设置。
pub const DEFAULT_BUDGET_TOKENS: u64 = 60_000;

/// 分层预算。input_budget = 窗口 - 输出预留 - 协议开销 - 安全预留（调用方计算后传入）。
#[derive(Debug, Clone, Copy)]
pub struct Budget {
    /// 本次装配的总 token 预算；必需层超出即整体拒绝。
    pub total: u64,
    /// 必需层的下限告警阈值；当前实现未使用，保留给审计。
    pub hard_min: u64,
    /// 选段层上限（当前由必需层判定兜底，字段留给后续收紧）。
    pub selection_max: u64,
    /// 检索证据层配额；装不下的命中记入 omitted。
    pub retrieval_max: u64,
    /// 摘要层配额（Summary 层尚未接入装配，字段预留给 T05E 后续阶段）。
    pub summary_max: u64,
}

impl Budget {
    /// 默认配额：必需层不受限（超限即拒绝），选段/检索/摘要各有上限。
    pub fn balanced(total: u64) -> Self {
        Self {
            total,
            hard_min: 0,
            selection_max: total / 4,
            retrieval_max: total / 2,
            summary_max: total / 4,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 估算含裕量且随文本增长() {
        let est = chinese_char_estimator();
        let small = estimate_tokens(&est, "一二三四五六七八");
        let large = estimate_tokens(&est, &"字".repeat(1600));
        assert!(large > small);
        assert_eq!(small, 12);
    }

    #[test]
    fn 预算配额合计不超总预算() {
        let budget = Budget::balanced(1000);
        assert!(budget.selection_max + budget.retrieval_max + budget.summary_max <= budget.total);
    }
}
