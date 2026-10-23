//! Python 短练习的口令协议。此模块不执行用户代码，也不判断测试通过。
//! 测试判定必须来自通过 G13 隔离验证的运行器。

/// 五种显式学习口令。口令之外的自然语言由上层决定如何处理，
/// 本模块不猜测、尤其不会默认为"审阅通过"。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LearningCommand {
    Quiz,
    SignatureOnly,
    Guided,
    Hint,
    Review,
}

/// 只解析明确口令；其它自然语言由上层选择处理，不能默认为“审阅通过”。
pub fn parse_command(input: &str) -> Option<LearningCommand> {
    match input.trim().trim_end_matches(['。', '！', '!', '？', '?']) {
        "考我一下" => Some(LearningCommand::Quiz),
        "先只要接口" => Some(LearningCommand::SignatureOnly),
        "这段带我写" => Some(LearningCommand::Guided),
        "给一点提示" => Some(LearningCommand::Hint),
        "审阅我的答案" => Some(LearningCommand::Review),
        _ => None,
    }
}

/// 一道练习的完整材料。全部借用引用、不持有数据，便于题库以静态字面量定义；
/// 使用前必须通过 [`Exercise::validate`] 的完整性与数量检查。
pub struct Exercise<'a> {
    pub id: &'a str,
    pub topic: &'a str,
    /// 概念讲解句：须 3–6 句且每句非空，空内容不允许伪装成练习。
    pub concept_sentences: &'a [&'a str],
    /// 目标函数的纯签名（不带实现），"先只要接口"口令返回它。
    pub signature: &'a str,
    pub prompt: &'a str,
    pub quiz_question: &'a str,
    pub guided_step: &'a str,
    /// 三级提示，逐级更具体；数量固定为 3，与 hint 上限 3 对应。
    pub hints: [&'a str; 3],
}

impl Exercise<'_> {
    /// 简短概念说明、纯函数签名与逐级提示均须完整，避免空内容伪装成练习。
    pub fn validate(&self) -> Result<(), &'static str> {
        if self.id.trim().is_empty()
            || self.topic.trim().is_empty()
            || !(3..=6).contains(&self.concept_sentences.len())
            || self
                .concept_sentences
                .iter()
                .any(|line| line.trim().is_empty())
            || self.signature.trim().is_empty()
            || self.prompt.trim().is_empty()
            || self.quiz_question.trim().is_empty()
            || self.guided_step.trim().is_empty()
            || self.hints.iter().any(|hint| hint.trim().is_empty())
        {
            return Err("练习材料不完整");
        }
        Ok(())
    }
}

/// 单步教学反馈。审阅类反馈只依据可信运行器构造的 [`VerifiedTests`]，
/// 前端自报的通过率不会被接受。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TeachingReply {
    Quiz(String),
    Signature(String),
    Guided(String),
    Hint {
        level: u8,
        text: String,
    },
    /// 审阅口令到达时还没有可信测试结果：只要求先运行测试，不推测结果。
    NeedVerifiedTests,
    Review {
        passed_count: u32,
        total_count: u32,
        guidance: String,
    },
}

/// `VerifiedTests` 仅由未来可信运行器构造，不接受前端直接上报的通过率。
#[derive(Debug, Clone, Copy)]
pub struct VerifiedTests {
    passed_count: u32,
    total_count: u32,
}

impl VerifiedTests {
    /// 仅供已隔离的确定性运行器使用；运行器尚未接入产品。
    pub fn from_runner(passed_count: u32, total_count: u32) -> Option<Self> {
        if total_count == 0 || passed_count > total_count {
            return None;
        }
        Some(Self {
            passed_count,
            total_count,
        })
    }
}

/// 一次练习会话：持有练习材料与当前提示级别（0–3），按显式口令单步推进。
pub struct LearningSession<'a> {
    exercise: Exercise<'a>,
    hint_level: u8,
}

impl<'a> LearningSession<'a> {
    /// 创建会话；材料校验失败即返回错误，不产生半初始化状态。
    pub fn new(exercise: Exercise<'a>) -> Result<Self, &'static str> {
        exercise.validate()?;
        Ok(Self {
            exercise,
            hint_level: 0,
        })
    }

    /// 显式口令驱动单步反馈；审阅没有真实测试时只要求先运行，不推测结果。
    pub fn respond(
        &mut self,
        command: LearningCommand,
        tests: Option<VerifiedTests>,
    ) -> TeachingReply {
        match command {
            LearningCommand::Quiz => TeachingReply::Quiz(self.exercise.quiz_question.into()),
            LearningCommand::SignatureOnly => {
                TeachingReply::Signature(self.exercise.signature.into())
            }
            LearningCommand::Guided => TeachingReply::Guided(self.exercise.guided_step.into()),
            LearningCommand::Hint => {
                // 提示级别封顶 3（与 hints 数组长度一致），数组索引因此不会越界。
                self.hint_level = (self.hint_level + 1).min(3);
                TeachingReply::Hint {
                    level: self.hint_level,
                    text: self.exercise.hints[(self.hint_level - 1) as usize].into(),
                }
            }
            LearningCommand::Review => match tests {
                None => TeachingReply::NeedVerifiedTests,
                Some(tests) => TeachingReply::Review {
                    passed_count: tests.passed_count,
                    total_count: tests.total_count,
                    guidance: if tests.passed_count == tests.total_count {
                        "测试全部通过，可以进入下一题。".into()
                    } else {
                        "还有测试未通过；先看失败用例，再请求分级提示。".into()
                    },
                },
            },
        }
    }

    /// 当前提示级别；0 表示尚未请求过提示。
    pub fn hint_level(&self) -> u8 {
        self.hint_level
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn exercise() -> Exercise<'static> {
        Exercise {
            id: "sum-even",
            topic: "循环条件",
            concept_sentences: &[
                "循环逐个处理元素。",
                "条件判断决定是否累加。",
                "函数返回计算结果。",
            ],
            signature: "def sum_even(numbers):",
            prompt: "求偶数之和。",
            quiz_question: "怎样判断一个数是偶数？",
            guided_step: "先写循环头，逐个读取 numbers。",
            hints: ["先遍历列表。", "用取余判断偶数。", "只有偶数才加进总和。"],
        }
    }

    #[test]
    fn 五种口令明确解析_未知内容不猜测() {
        for (text, expected) in [
            ("考我一下！", LearningCommand::Quiz),
            ("先只要接口", LearningCommand::SignatureOnly),
            ("这段带我写。", LearningCommand::Guided),
            ("给一点提示", LearningCommand::Hint),
            ("审阅我的答案？", LearningCommand::Review),
        ] {
            assert_eq!(parse_command(text), Some(expected));
        }
        assert_eq!(parse_command("帮我写完整答案"), None);
    }

    #[test]
    fn 分级提示有上限且未运行测试不能假装审阅() {
        let mut session = LearningSession::new(exercise()).unwrap();
        assert_eq!(
            session.respond(LearningCommand::Review, None),
            TeachingReply::NeedVerifiedTests
        );
        assert_eq!(
            session.respond(LearningCommand::SignatureOnly, None),
            TeachingReply::Signature("def sum_even(numbers):".into())
        );
        for level in 1..=4 {
            let _ = session.respond(LearningCommand::Hint, None);
            assert_eq!(session.hint_level(), level.min(3));
        }
        let tests = VerifiedTests::from_runner(1, 2).unwrap();
        assert!(matches!(
            session.respond(LearningCommand::Review, Some(tests)),
            TeachingReply::Review {
                passed_count: 1,
                total_count: 2,
                ..
            }
        ));
        assert!(VerifiedTests::from_runner(3, 2).is_none());
    }

    #[test]
    fn 概念说明必须三到六句() {
        let mut bad = exercise();
        bad.concept_sentences = &["只有一句。"];
        assert!(LearningSession::new(bad).is_err());
    }
}
