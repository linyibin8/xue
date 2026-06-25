# 知进伴学 · 多端多版本管理手册

> 目标：每加一个功能，都能低成本地同步到 **iPad / iPhone / PC-Web** 三端，且不发散、不漂移。
> 本手册是「单一索引」——新功能照着走，AI（Claude Code）也照着这份文档干活。

---

## 1. 三端一后端拓扑

```
                ┌─────────────── 共享后端契约（唯一真相源）───────────────┐
                │  FastAPI  backend/app/main.py  （部署在 ydz:8028）        │
                │  REST /api/*  +  SQLite（每账号一库）+ 向量/记忆/复习      │
                └───────────────────────────┬─────────────────────────────┘
                                            │  同一套 /api/* 契约
          ┌──────────────────────┬──────────┴───────────┬────────────────────┐
   iPhone 端                 iPad 端                  PC-Web 端
   ios/ 单一 target          ios/ 同一 target          backend/app/static/*
   ContentView.swift         iPad/*.swift              dashboard / prompts /
   （横屏沉浸工作台）         （NavigationSplitView）    assets / session-panel
          └──────────┬───────────┘
                     │  共享核心：AppState / AuthSession / 所有模型 / 所有 API 调用
                     └──────────────（iOS 同一 target 内，零拷贝复用）
```

**关键事实：iPad 和 iPhone 是同一个 App、同一个 bundle（`com.linyibin8.xue`）、同一个 TestFlight（ASC `6783612413`）。**
启动时按 `UIDevice.current.userInterfaceIdiom` 在 `XueApp.swift` 分流：
- `.pad` → `iPadRootView`（`ios/Xue/App/iPad/`，原生主从结构）
- 其它 → `ContentView`（原横屏工作台）

两端**共享同一份核心层**（`AppState`、`AuthSession`、`ChatMessage`/`HistorySessionSummary`/`ReviewMistakeItem`… 所有模型、所有网络调用）。
→ **网络/模型/业务逻辑只写一遍**，iPad 文件只负责「容器 + 导航 + 布局」，调用 AppState 现有方法。

---

## 2. 管理原则：API 契约是唯一真相源

> 一个功能，永远**先定后端 endpoint（契约），再各端消费**。契约不在某一端的脑子里，而在 `main.py` 的路由签名 + 返回 JSON 结构里。

- 后端只暴露**与端无关**的数据/动作；任何端特有的展示逻辑留在端内。
- iOS 端的契约消费点**集中在 `AppState`**（解析 JSON → 模型 → `@Published`）。iPad/iPhone 的 View 不直接发请求，一律调 `AppState` 方法 → 契约改了只改 AppState 一处。
- Web 端在 `static/*.js` 里消费同样的 `/api/*`。

---

## 3. 功能矩阵（每加一个功能，补满这张表）

| 功能 | 后端 endpoint | AppState 方法/属性 | iPhone 视图 | iPad 视图 | Web 页面 |
|---|---|---|---|---|---|
| 拍题解析 | `POST /api/solve-single`, `POST /api/sessions/{id}/qa` | `requestSingleCapture()` / `submitTypedQuestion()` | `LandscapeLearningWorkbench` | `iPadLearnView` | session-panel |
| 语音问答 | `POST /api/sessions/{id}/qa` | `submitVoiceQuestion()` | `VoiceHoldArea` | `iPadLearnView`（复用 VoiceHoldArea） | — |
| 智能观察 | `POST /api/sessions/{id}/batches` | `startBurst()/stopBurst()` | 工作台 | `iPadLearnView` | session-panel |
| 历史 | `GET /api/sessions`, `/overview` | `refreshHistorySessions()` / `historyReport(for:)` | `HistorySessionSheet` | `iPadHistoryView` | dashboard |
| 错题本 | `GET /api/review-queue`（写入 `POST …/mistakes`） | `refreshReviewQueuePreview()` / `dueReviewItems` | 上下文工作区 | `iPadMistakesView` | assets |
| 记忆 | `GET /api/memory`, `POST …/memory` | `refreshMemoryDigest()` / `formMemoryFromLatestAnswer()` | 记忆区 | `iPadMemoryView` | dashboard |
| 偏好/上下文 | （本地 UserDefaults + `PATCH …/strategy`） | `coachPreferenceDidChange()` / `updateContextInclusion()` | `ChatSettingsPanel` | `iPadSettingsView` | prompts |
| 账号/多档案 | `/api/auth/*`, `/api/profiles*` | `AuthSession`（共享单例） | `AuthGateView` / `IdentityManagerView` | `iPadSettingsView` + 侧栏切换 | — |

> **TODO（下一个三端示范）**：`GET /api/mistakes`（按账号全量错题，独立于复习队列）。先后端加路由 → AppState 加 `refreshMistakes()` → iPad `iPadMistakesView` 切数据源 → iPhone 错题区 → Web assets。照矩阵补满即「同步完成」。

---

## 4. 发功能 Runbook（标准流程）

### ① 后端（契约先行）
```bash
# 本地改 backend/app/main.py —— 务必 surgical（按 memory 部署纪律：字符串精确替换，勿整文件覆盖）
# 部署到 ydz（代码烤进镜像，data/ 是 root-owned 的 bind mount，勿覆盖）
ssh ydz@100.64.0.13
cd /home/ydz/services/xue/backend
rsync -c <本地 app/> ./app/        # 仅同步 app/
docker compose build --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= && docker compose up -d
# 冒烟：register/login → 新 endpoint 200，无 token → 401
```

### ② iOS 核心层（共享，只写一遍）
- 在 `AppState` 加方法解析新 endpoint → `@Published` 属性。
- 模型放在 ContentView.swift 顶部模型区（两端可见，**勿加 `private`**）。

### ③ 两端 UI（各接一次）
- iPhone：在工作台/sheet 里接。
- iPad：在对应 `iPad/iPad*.swift` 里接。**复用叶子视图时**，若是 `private struct`，去掉 `private`（仅放宽访问，行为不变）。

### ④ 构建 → 验证 → 发布（一条命令上两端）
```bash
# 同步到 Mac（local ios/Xue/App/ → Mac Xue/，App 层被拍平；新文件放 Xue/iPad/）
scp ContentView.swift XueApp.swift Info.plist macstar@100.64.0.6:/Users/macstar/Code/Xue/Xue/
scp iPad/*.swift macstar@100.64.0.6:/Users/macstar/Code/Xue/Xue/iPad/
ssh macstar@100.64.0.6 'cd /Users/macstar/Code/Xue && ~/bin/xcodegen generate'   # 新 .swift 自动纳入（sources: -path Xue 递归 glob）

# 模拟器验证（iPad + iPhone 回归）
xcodebuild -scheme Xue -destination "platform=iOS Simulator,name=iPad Pro 13-inch (M5)" CODE_SIGNING_ALLOWED=NO build

# 一条命令发布 → 通用二进制 → iPhone+iPad 同时拿到
~/testflight-auto/fastlane-ios-oneclick/bin/oneclick-ios bump-and-publish --project-dir /Users/macstar/Code/Xue --message '...'
# altool 卡死兜底：status 确认 VALID 后手动跑 configure_testflight.py + assign_testflight_testers_via_itms.py（见 memory）
```

---

## 5. 用 AI（Claude Code）高效管理多端

1. **本文档 = 单一索引**。任何新功能，先让 AI 读这份文档 + 功能矩阵，它就知道要动哪几格。
2. **代码图谱**：已部署 codebase-memory-mcp，UI 在 `https://codemap.evowit.com`（Basic Auth `evowit`）。让 AI 跨文件检索「某 endpoint 在哪被消费」「某模型谁在用」，避免漏端。
3. **`~/.claude` memory**：每次大改后，把"新增文件/端拓扑/发布 build 号"写回 memory，下次 AI 自动带上下文。
4. **一次 PR 一个功能、跨四格**：后端 + AppState + iPhone + iPad（+Web）尽量同一改动集，review 时对着矩阵逐格确认，杜绝「iPad 有、iPhone 没」的漂移。
5. **放宽访问而非复制**：iPad 要复用 iPhone 的叶子视图时，去掉 `private` 即可（同 target 共享），**绝不复制一份业务逻辑**——复制是多端漂移的头号来源。

---

## 6. 版本策略（避免 schema 漂移）

- **后端**：持续部署，容器即版本（无显式版本号）。**契约向后兼容**：加字段不删字段；删/改字段前先确认所有端已不依赖。
- **iOS**：`MARKETING_VERSION`（语义版本）+ `CURRENT_PROJECT_VERSION`/build 号（时间戳 `YYYYMMDDHHMM`）。iPhone 与 iPad 永远同版本（同一 build）。
- **Web**：随后端走，无独立版本。
- **黄金规则**：三端共享**同一后端契约**。后端先上、向后兼容，老版本 App 仍能用；新端特性靠新字段渐进增强，而非破坏式变更。

---

## 7. 文件地图（iOS 端）

```
ios/Xue/App/
  XueApp.swift          # @main，按 idiom 分流 iPhone/iPad
  ContentView.swift     # iPhone 工作台 + 全部共享核心（AppState/模型/网络/叶子视图）
  Auth.swift            # AuthSession（共享）+ 登录/注册/档案
  iPad/                 # iPad 原生端（仅容器+导航+布局，复用上面的核心）
    iPadRoot.swift        # NavigationSplitView 侧栏 + 学生切换 + 账号底栏
    iPadLearnView.swift   # 学习工作台：相机/语音/对话 双栏
    iPadHistoryView.swift # 历史：列表 + 报告
    iPadMistakesView.swift# 错题本：列表 + 详情（数据源=复习队列）
    iPadMemoryView.swift  # 记忆：画像 + 事件流
    iPadSettingsView.swift# 设置：偏好/上下文/语音/档案/账号
```
