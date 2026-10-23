//! 小说生成边界：只从当前作品已确认版本组装上下文；完整响应才可存为试写。
//! 本 crate 不依赖 Tauri，也不发网络请求。调用方负责预览票据、云开关复查与 Key。
//!
//! 模块划分（T05A）：
//! - [`generation`]：上下文组装与整章/选段预览（`prepare_generation`/`prepare_edit`）；
//! - [`edit`]：选段坐标校验与片段替换（`apply_edit`）；
//! - [`rpg`]：两阶段跑团场景与玩家回复；
//! - [`stream`]：模型流消费（`collect_complete`）；
//! - [`quality`]：字面规则候选（待决议题、人物禁令冲突）。
//!
//! 常量上限是本模块的硬边界，T05E 以分层预算替换 30000 字整书拼接口径。

mod context;
mod edit;
mod generation;
mod patch;
mod quality;
mod rpg;
mod stream;
mod working_edit;
mod working_generation;
mod working_output;

pub use context::{
    assemble_context, chinese_char_estimator, estimate_tokens, AssembleRequest, AssembledContext,
    Budget, ContextItem, ContextLayer, ContextManifest, EstimatorInfo, OmittedItem,
    DEFAULT_BUDGET_TOKENS,
};
pub use edit::{apply_edit, EditMode, EditSelection};
pub use generation::{current_context_versions, prepare_edit, prepare_generation, GenerationPlan};
pub use patch::{
    apply_all, apply_one, build_patch, char_ops, quote_hash, validate_patch, ApplyContext,
    CharOp, CharSpan, PartialApply, Patch, PatchBlock,
};
pub use quality::{all_conflicts_overridden, draft_conflicts, open_questions, DraftConflict, OpenQuestion};
pub use rpg::{parse_rpg_scene, prepare_rpg_scene, prepare_rpg_response, RpgSceneContent};
pub use stream::collect_complete;
pub use working_edit::{prepare_working_edit, validate_working_edit, WorkingEditPlan, WorkingEditRequest, WorkingReference};
pub use working_generation::{collect_cancellable, WorkingGenerationState, WorkingRun};
pub use working_output::{start_working_generation,complete_working_generation,apply_working_operation,reject_working_operation,working_operation_views,WorkingOperationView};

/// 创作要求/补充要求的最大字符数；超出即拒绝，不静默截断。
pub(crate) const MAX_INSTRUCTION_CHARS: usize = 2_000;
/// 整章试写与单次模型回复的硬上限；超限视为异常，不保存为试写。
pub(crate) const MAX_RESPONSE_CHARS: usize = 200_000;
/// 选段编辑一次可选内容的最大字符数。
pub(crate) const MAX_SELECTION_CHARS: usize = 4_000;
/// 选段替换片段的最大字符数；续写模式在 edit.rs 内另有更小的 1500 字内联限制。
pub(crate) const MAX_EDIT_FRAGMENT_CHARS: usize = 8_000;
