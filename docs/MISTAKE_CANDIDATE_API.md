# 错题候选（观察异步提取 → 学生确认导入）API

## 背景与模型

错题来源现在分两条，彻底分开：

| 来源 | detection_method | 入库状态 | 是否进正式错题本/复习队列 |
|------|------------------|----------|---------------------------|
| 主动拍题/批改 | `photo_grading` | `suspected`/`incomplete` | 是（直接进） |
| 智能观察（被动） | `observation` | **`candidate`** | **否**，先进"候选池"等学生确认 |
| 手动添加 | `manual` | `confirmed` | 是 |

`candidate` 是新增状态：智能观察时模型异步吐出"可疑错题候选"，落在候选池里，**不计入**复习队列（`/api/review-queue`）、也不计入学情画像。学生在客户端逐条 **导入** 或 **忽略**：

- 导入 → `status=confirmed`，进正式错题本并排入复习。
- 忽略 → `status=ignored`，丢弃。

## 接口

### 1. 列出候选 `GET /api/mistake-candidates`

Query 参数（都可选）：`subject`、`q`（关键词）、`page_size`（默认/上限同其它资产接口）。

返回：
```json
{
  "items": [
    {
      "id": "…",
      "title": "24÷6=",
      "question_text": "24÷6=",
      "student_answer": "3",
      "expected_answer": "4",
      "error_reason": "口诀记错",
      "error_type": "计算",
      "evidence": "答案被划掉重写仍错",
      "knowledge_points": ["表内除法"],
      "subject": "数学",
      "status": "candidate",
      "detection_method": "observation",
      "session_title": "智能观察学习回合",
      "first_seen_at": "…", "last_seen_at": "…"
      // 字段结构与 /api/review-queue 的 item 一致（mistake_row_to_dict）
    }
  ],
  "total": 1,
  "page_size": 30
}
```

### 2. 导入候选 `POST /api/mistakes/{id}/import`

把候选确认进正式错题本。Body 可空；也可带内联订正：
```json
{ "review_note": "…", "correction": "…", "next_action": "…", "error_type": "…" }
```
返回 `{ "mistake": { …, "status": "confirmed", "review_state": "queued" } }`。导入后该条从候选列表消失，出现在 `/api/review-queue`。

### 3. 忽略候选 `POST /api/mistakes/{id}/dismiss`

返回 `{ "mistake": { …, "status": "ignored" } }`。从候选列表消失，不进错题本。

### 4. 候选计数（角标）

`GET /api/student-profile` 的 `profile.review_summary.candidate_count`：当前待确认候选数。客户端可在"错题本"入口或"候选"Tab 上做角标。

## 客户端建议

- 新增一个"错题候选 (N)"区域/Tab（与正式"错题本"分开）。列表每条给 **导入 / 忽略** 两个动作（可整列滑动操作）。
- 导入前允许学生快速编辑订正/错因（可选，走 import 的 body）。
- 候选 `title`/`student_answer`/`expected_answer`/`evidence` 已结构化，直接展示即可；`evidence` 是模型判错依据（如"答案被划掉重写"）。
- 角标用 `candidate_count`；为 0 时不展示候选入口也可以。

## 注意

- 候选 **不会** 出现在 `/api/review-queue`、不计入 `active_review_count`/学情画像——这是有意为之。
- 候选提取是"搭车"在智能观察的后台分析里完成的，不额外消耗模型调用。
- 历史脏错题用 `backend/scripts/cleanup_mistake_noise.py` 清理（先 dry-run，再 `--apply`）。
