//! 选段编辑的纯文本边界：坐标校验、对白保护与片段替换。
//! 选段坐标是 Unicode 字符序号（与前端 selection.ts 换算后的口径一致），
//! 任何越界或不一致的选段都在这里拒绝，不进入生成或保存路径。

use crate::{MAX_EDIT_FRAGMENT_CHARS, MAX_RESPONSE_CHARS, MAX_SELECTION_CHARS};

/// 选段修改模式：只改对白 / 重写保留动作逻辑 / 选段后续写。
#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum EditMode {
    DialogueOnly,
    PreserveAction,
    ContinueShort,
}

/// 一次选段编辑的输入：模式 + 字符坐标 + 客户端提交的选段文本。
/// 坐标为 Unicode 字符序号，与前端 selection.ts 换算后的口径一致。
#[derive(Debug, Clone)]
pub struct EditSelection {
    pub mode: EditMode,
    /// 选段起点（含），字符序号。
    pub start_char: usize,
    /// 选段终点（不含），字符序号。
    pub end_char: usize,
    /// 客户端所见选段文本；必须与正稿该坐标处的实际内容逐字一致，
    /// 否则视为选段已过期（用户看到的是旧快照）。
    pub selected_text: String,
}

/// 校验选段：起止有序、不越界、长度受限，且坐标处的实际文本与客户端
/// 提交文本逐字相同。任何不一致都在这里拒绝，不猜测用户真实意图。
pub(crate) fn validate_selection(body: &str, selection: &EditSelection) -> Result<(), String> {
    if selection.start_char >= selection.end_char
        || selection.end_char > body.chars().count()
        || selection.selected_text.chars().count() > MAX_SELECTION_CHARS
    {
        return Err("请选择正稿中不超过 4000 字的连续段落".into());
    }
    let actual: String = body
        .chars()
        .skip(selection.start_char)
        .take(selection.end_char - selection.start_char)
        .collect();
    if actual != selection.selected_text {
        return Err("所选段落与当前正稿不一致，请重新选择".into());
    }
    Ok(())
}

/// 剥离对白引号内的内容，返回（引号外文本, 对白段数）。
/// 同时支持中文弯引号“”与直角引号「」；引号不配对即报错——
/// 不完整引号会让"对白外逐字不变"的校验失去可靠边界。
pub(crate) fn non_dialogue(text: &str) -> Result<(String, usize), String> {
    let mut outside = String::new();
    let mut closing = None;
    let mut count = 0;
    for ch in text.chars() {
        match (closing, ch) {
            (None, '“') => {
                outside.push(ch);
                closing = Some('”');
            }
            (None, '「') => {
                outside.push(ch);
                closing = Some('」');
            }
            (Some(expected), actual) if expected == actual => {
                outside.push(ch);
                closing = None;
                count += 1;
            }
            (None, _) => outside.push(ch),
            _ => {}
        }
    }
    if closing.is_some() {
        return Err("选段或模型回复的对白引号不完整，未保存试写".into());
    }
    Ok((outside, count))
}

/// 将模型片段拼成整章待确认试写。只改选段；对白模式额外锁住对白外字符。
pub fn apply_edit(body: &str, selection: &EditSelection, response: &str) -> Result<String, String> {
    validate_selection(body, selection)?;
    if response.trim().is_empty() || response.chars().count() > MAX_RESPONSE_CHARS {
        return Err("模型片段为空或过长，未保存试写".into());
    }
    // 续写只追加一小段，片段上限比重写更严（产品口径 1500 字）。
    let fragment_limit = if selection.mode == EditMode::ContinueShort {
        1_500
    } else {
        MAX_EDIT_FRAGMENT_CHARS
    };
    if response.chars().count() > fragment_limit {
        return Err("模型返回内容超出选段修改长度，未保存试写".into());
    }
    if selection.mode == EditMode::DialogueOnly {
        // 对白模式：引号外文本与对白段数都必须与原选段完全一致，
        // 模型多改一个动作字、增减一段对白都拒绝。
        let before = non_dialogue(&selection.selected_text)?;
        let after = non_dialogue(response)?;
        if before.1 == 0 || before != after {
            return Err("模型修改了对白之外的文字或对白数量，未保存试写".into());
        }
    }
    let chars: Vec<char> = body.chars().collect();
    let mut result = String::new();
    // 续写保留到选段终点（追加在选段之后）；重写/对白模式替换整个选段，
    // 保留起点之前的前缀与终点之后的后缀，选段之外逐字不变。
    result.extend(
        &chars[..if selection.mode == EditMode::ContinueShort {
            selection.end_char
        } else {
            selection.start_char
        }],
    );
    result.push_str(response);
    result.extend(&chars[selection.end_char..]);
    if result.chars().count() > MAX_RESPONSE_CHARS {
        return Err("整章试写超过 200000 字上限，未保存".into());
    }
    Ok(result)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 选段重写和续写只改变所选位置_支持中文与表情字符() {
        let body = "开头😀。她说：“你好。”\n后来离开。";
        let selected = "她说：“你好。”";
        let start = "开头😀。".chars().count();
        let end = start + selected.chars().count();
        let rewrite = EditSelection {
            mode: EditMode::PreserveAction,
            start_char: start,
            end_char: end,
            selected_text: selected.into(),
        };
        assert_eq!(
            apply_edit(body, &rewrite, "她低声说：“回来。”").unwrap(),
            "开头😀。她低声说：“回来。”\n后来离开。"
        );
        let continued = EditSelection {
            mode: EditMode::ContinueShort,
            ..rewrite.clone()
        };
        assert_eq!(
            apply_edit(body, &continued, "她又笑了。 ").unwrap(),
            "开头😀。她说：“你好。”她又笑了。 \n后来离开。"
        );
        let wrong = EditSelection {
            selected_text: "不在正稿".into(),
            ..rewrite
        };
        assert!(apply_edit(body, &wrong, "任意内容").is_err());
    }

    #[test]
    fn 只改对白拒绝动作变化与不完整引号() {
        let selected = "她推开门，说：“进来。”";
        let selection = EditSelection {
            mode: EditMode::DialogueOnly,
            start_char: 0,
            end_char: selected.chars().count(),
            selected_text: selected.into(),
        };
        assert_eq!(
            apply_edit(selected, &selection, "她推开门，说：“请进。”").unwrap(),
            "她推开门，说：“请进。”"
        );
        assert!(apply_edit(selected, &selection, "她关上门，说：“请进。”").is_err());
        assert!(apply_edit(selected, &selection, "她推开门，说：“请进。 ").is_err());
    }
}
