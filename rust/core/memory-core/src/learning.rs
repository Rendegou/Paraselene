//! 学习轨迹的本地存储；运行器完成确定性测试后才调用记录入口。
//! 不执行代码、不访问用户目录，也不把练习代码发送给模型。

use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};

use crate::error::{Error, Result};
use crate::storage::db::Database;

const MAX_CODE_CHARS: usize = 20_000;

/// 一次练习尝试的完整记录（含用户提交的代码正文）。
///
/// 与 `learning_attempts` 表一一对应；`code` 只存本地库、不外发（见模块文档的隐私约定）。
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LearningAttempt {
    pub id: String,
    pub goal_memory_id: String,
    pub exercise_id: String,
    pub code: String,
    pub passed: bool,
    pub passed_count: u32,
    pub total_count: u32,
    pub hint_level: u8,
    pub weak_topic: Option<String>,
    pub created_at: String,
}

/// 仅由可信的本地测试执行结果构造；不要把前端自报的通过数直接传入。
pub struct NewLearningAttempt<'a> {
    pub goal_memory_id: &'a str,
    pub exercise_id: &'a str,
    pub code: &'a str,
    pub passed_count: u32,
    pub total_count: u32,
    pub hint_level: u8,
    pub weak_topic: Option<&'a str>,
}

/// 校验 `goal_memory_id` 指向一个仍然有效的学习目标（learning 空间、kind='goal'、未删除）。
///
/// 所有学习轨迹查询 / 写入前的统一作用域检查：跨空间或已软删的目标直接 NotFound，
/// 保证学习数据不会经猜测 id 泄漏到其他空间。
fn ensure_learning_goal(conn: &Connection, id: &str) -> Result<()> {
    let goal: bool = conn.query_row(
        "SELECT EXISTS(SELECT 1 FROM memories WHERE id = ?1 AND space = 'learning'
         AND kind = 'goal' AND deleted_at IS NULL)",
        [id],
        |row| row.get(0),
    )?;
    if !goal {
        return Err(Error::not_found("学习目标不存在"));
    }
    Ok(())
}

impl Database {
    /// 在学习目标下记录一次练习；代码和结果只存在本地库。
    ///
    /// 输入校验失败返回 Parse 错误（exercise_id 非空且 ≤120 字符、代码非空且 ≤20k 字符、
    /// 通过数 ≤ 总数且总数 > 0、提示级别 ≤ 3、weak_topic 非空时 ≤80 字符）；
    /// 目标不存在 / 已删除 / 不在 learning 空间返回 NotFound。
    pub fn record_learning_attempt(
        &self,
        input: NewLearningAttempt<'_>,
    ) -> Result<LearningAttempt> {
        // 前端自报数据一律按不可信输入校验；通过数不允许超过总数，杜绝「满分伪造」。
        if input.exercise_id.trim().is_empty()
            || input.exercise_id.chars().count() > 120
            || input.code.trim().is_empty()
            || input.code.chars().count() > MAX_CODE_CHARS
            || input.total_count == 0
            || input.passed_count > input.total_count
            || input.hint_level > 3
            || input
                .weak_topic
                .is_some_and(|topic| topic.trim().is_empty() || topic.chars().count() > 80)
        {
            return Err(Error::parse("练习记录的题目、代码、测试数或提示级别无效"));
        }
        let id = uuid::Uuid::new_v4().to_string();
        let created_at = chrono::Utc::now().to_rfc3339();
        let passed = input.passed_count == input.total_count;
        self.with_tx(|tx| {
            ensure_learning_goal(tx, input.goal_memory_id)?;
            tx.execute(
                "INSERT INTO learning_attempts (id, goal_memory_id, exercise_id, code, passed,
                   passed_count, total_count, hint_level, weak_topic, created_at)
                 VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)",
                params![
                    id,
                    input.goal_memory_id,
                    input.exercise_id,
                    input.code,
                    passed,
                    input.passed_count,
                    input.total_count,
                    input.hint_level,
                    input.weak_topic.map(str::trim),
                    created_at
                ],
            )?;
            Ok(())
        })?;
        Ok(LearningAttempt {
            id,
            goal_memory_id: input.goal_memory_id.to_owned(),
            exercise_id: input.exercise_id.to_owned(),
            code: input.code.to_owned(),
            passed,
            passed_count: input.passed_count,
            total_count: input.total_count,
            hint_level: input.hint_level,
            weak_topic: input.weak_topic.map(str::trim).map(str::to_owned),
            created_at,
        })
    }

    /// 仅返回指定学习目标的尝试；跨空间或已删除目标返回错误。
    pub fn list_learning_attempts(&self, goal_memory_id: &str) -> Result<Vec<LearningAttempt>> {
        self.with_conn(|conn| {
            ensure_learning_goal(conn, goal_memory_id)?;
            let mut stmt = conn.prepare_cached(
                "SELECT id, goal_memory_id, exercise_id, code, passed, passed_count, total_count,
                        hint_level, weak_topic, created_at FROM learning_attempts
                 WHERE goal_memory_id = ?1 ORDER BY rowid DESC",
            )?;
            let rows = stmt
                .query_map([goal_memory_id], |row| {
                    Ok(LearningAttempt {
                        id: row.get(0)?,
                        goal_memory_id: row.get(1)?,
                        exercise_id: row.get(2)?,
                        code: row.get(3)?,
                        passed: row.get(4)?,
                        passed_count: row.get(5)?,
                        total_count: row.get(6)?,
                        hint_level: row.get(7)?,
                        weak_topic: row.get(8)?,
                        created_at: row.get(9)?,
                    })
                })?
                .collect::<std::result::Result<Vec<_>, _>>()?;
            Ok(rows)
        })
    }

    /// 返回最近一个仍未通过的薄弱主题；同主题后来通过后不再建议它。
    ///
    /// SQL 思路：对每个最近失败的 weak_topic，只取该主题最新一次尝试（子查询按 rowid 倒序取 1），
    /// 再在所有「最新失败」的主题里取最近的一个——这样同主题后来通过后，其最新记录 passed=1，
    /// 自然被外层 `a.passed = 0` 过滤掉，无需额外 UPDATE 清理。
    pub fn next_learning_weak_topic(&self, goal_memory_id: &str) -> Result<Option<String>> {
        self.with_conn(|conn| {
            // 不加载练习代码正文即可验证作用域并寻找薄弱点。
            ensure_learning_goal(conn, goal_memory_id)?;
            Ok(conn
                .query_row(
                    "SELECT a.weak_topic FROM learning_attempts a
             WHERE a.goal_memory_id = ?1 AND a.weak_topic IS NOT NULL AND a.passed = 0
               AND a.rowid = (SELECT b.rowid FROM learning_attempts b
                 WHERE b.goal_memory_id = a.goal_memory_id AND b.weak_topic = a.weak_topic
                 ORDER BY b.rowid DESC LIMIT 1)
             ORDER BY a.rowid DESC LIMIT 1",
                    [goal_memory_id],
                    |row| row.get(0),
                )
                .optional()?)
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::spaces::{NewMemory, Space};

    fn goal(db: &Database, space: Space) -> String {
        db.create_memory(NewMemory {
            space,
            work_id: None,
            kind: "goal".into(),
            title: "练 Python".into(),
            summary: None,
            status: None,
            reminder_pref: None,
            payload: None,
        })
        .unwrap()
        .id
    }

    #[test]
    fn 学习轨迹只写学习目标且薄弱点在通过后消失() {
        let db = Database::open_in_memory().unwrap();
        let learning = goal(&db, Space::Learning);
        let personal = goal(&db, Space::Personal);
        fn attempt(goal_memory_id: &str, passed_count: u32) -> NewLearningAttempt<'_> {
            NewLearningAttempt {
                goal_memory_id,
                exercise_id: "sum-even",
                code: "def sum_even(xs): return 0",
                passed_count,
                total_count: 2,
                hint_level: 1,
                weak_topic: Some("循环条件"),
            }
        }
        assert!(db.record_learning_attempt(attempt(&personal, 0)).is_err());
        assert!(db.list_learning_attempts(&personal).is_err());
        let failed = db.record_learning_attempt(attempt(&learning, 1)).unwrap();
        assert!(!failed.passed);
        assert_eq!(
            db.next_learning_weak_topic(&learning).unwrap().as_deref(),
            Some("循环条件")
        );
        let passed = db.record_learning_attempt(attempt(&learning, 2)).unwrap();
        assert!(passed.passed);
        assert_eq!(db.list_learning_attempts(&learning).unwrap().len(), 2);
        assert_eq!(db.next_learning_weak_topic(&learning).unwrap(), None);
        db.soft_delete_memory(&learning).unwrap();
        assert!(db.list_learning_attempts(&learning).is_err());
        assert!(db.next_learning_weak_topic(&learning).is_err());
    }

    #[test]
    fn 学习轨迹重开后仍保留代码结果和提示级别() {
        let temp = tempfile::tempdir().unwrap();
        let path = temp.path().join("index.db");
        let goal_id = {
            let db = Database::open(&path).unwrap();
            let id = goal(&db, Space::Learning);
            db.record_learning_attempt(NewLearningAttempt {
                goal_memory_id: &id,
                exercise_id: "sum-even",
                code: "def sum_even(xs): return 2",
                passed_count: 1,
                total_count: 2,
                hint_level: 2,
                weak_topic: Some("循环条件"),
            })
            .unwrap();
            id
        };
        let reopened = Database::open(&path).unwrap();
        let attempts = reopened.list_learning_attempts(&goal_id).unwrap();
        assert_eq!(attempts.len(), 1);
        assert_eq!(attempts[0].code, "def sum_even(xs): return 2");
        assert_eq!(
            (
                attempts[0].passed_count,
                attempts[0].total_count,
                attempts[0].hint_level
            ),
            (1, 2, 2)
        );
        assert_eq!(
            reopened
                .next_learning_weak_topic(&goal_id)
                .unwrap()
                .as_deref(),
            Some("循环条件")
        );
    }
}
