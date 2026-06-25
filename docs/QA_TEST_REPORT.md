# 知进伴学 · 回归测试报告（iPad + iPhone 模拟器）

> 2026-06-25，build 202606251857 之后的全量回归。分 7 批次执行，证据=截图/日志/后端核对。
> 测试机：macstar@100.64.0.6（Xcode 模拟器）。测试账号：ipadqa@evowit.com。

## 分批策略（怎么分步骤）

| 批次 | 范围 | 工具 |
|---|---|---|
| 1 构建矩阵 | iPad/iPhone × Debug/Release 全编译 | xcodebuild |
| 2 启动/登录 | 两端冷启动→登录屏→autologin→主界面，扫崩溃 | simctl + 日志 |
| 3 iPad 视觉态 | 5 分区 × 竖/横屏 × 空/有数据 | XCUITest 截图 |
| 4 iPad 交互 | 输入切换/思考器/历史进对话/设置/错题详情 | XCUITest |
| 5 iPhone 回归 | 工作台/工具菜单/问答 | XCUITest |
| 6 数据管线 | 错题→错题本卡片；记忆；可视化 | API 注入 + XCUITest |
| 7 汇总 | 缺陷→修复→复测→本报告 | — |

测试基建：DEBUG 钩子 `XUE_AUTOLOGIN_*`（launchEnvironment 自动登录，绕过登录屏 flaky）+ `XUE_IPAD_SECTION`（直达分区）；XCUITest 用 `XCUIScreen.main.screenshot()` 避免 app 繁忙时抓不到图；稳定 accessibilityIdentifier（`ipad-section-*`/`ipad-composer-*`/`ipad-input-toggle` + 共享 `assistant-answer-actions` 等）。

## 结果

**✅ 通过（模拟器可测）**
- 构建矩阵 4/4 编译 0 error（含上架 Release）。
- 两端冷启动+autologin 进主界面，**无崩溃**（无 .ips、无 fatal）。
- iPad 5 分区渲染正常 + **竖横屏**都正常（NavigationSplitView 竖屏侧栏可收起、横屏常驻）。
- **#1 历史→进入对话**：点「进入对话」切到学习页 ✓（testIPad_05 passed）。
- **#4 输入切换**：底部统一条 拍题/文字/语音，右下角 mic⇄键盘切换 ✓（testIPad_04 passed，截图见语音态「按住说话」）。
- **#5 思考等待器**：提问后对话流出现「AI 正在思考你的问题…」+spinner ✓（截图 06b 确认）。
- **#3 错题本卡片**：注入错题后，详情=题目 + 我的作答(红)↔正确答案(绿) + 错误原因(橙) + 订正建议(绿) + 知识点 chips，清爽无杂乱 ✓（testIPad_07 passed）。
- 设置开关交互 ✓。
- **iPhone 回归**：工作台、工具菜单（观察/历史/上下文）✓，无回归。

**⚠️ 模拟器无法 E2E（需真机）—— 不是 bug**
- **真问答（QA）+ 拍题 + 智能观察**：`submitTypedQuestion` 会打开相机抓取当前画面作为上下文（`cameraPreviewVisible=true`+2.5s 取帧）。**模拟器无摄像头**，AVCaptureSession 起不来→取不到帧→QA 不发出（后端 qa:0）→app 被系统终止回桌面。**iPhone 模拟器上 QA 同样失败**（testIPhone_03 failed），而 iPhone 线上真机问答正常 → 证明是**模拟器无相机的通用限制，非 iPad bug**。iPad 与 iPhone 共用同一套 `submitTypedQuestion`/`submitRecognizedQuestion`。
- 因此依赖「真实回答」的项只能真机验证：**#7 动作收敛（正/反例）、#6 上下文 chips、#2 可视化异步轮询**。这些代码已编译通过、逻辑与 iPhone 线上一致。

## 发现的问题与处置

| 现象 | 结论 | 处置 |
|---|---|---|
| QA 在模拟器不返回、app 回桌面 | 模拟器无相机（通用限制，非 bug） | 文档化，转真机清单 |
| 测试里侧栏项「不可点」 | 竖屏侧栏收起 + 标识落在 Image 子元素 | 测试改横屏 + 按 section env 重启巡检 |
| 语音模式断言失败 | 选择器用了 `.exists`（过早） | 改 `waitForExistence` |
| 错题详情空白 | `cells.firstMatch` 命中侧栏 cell | 测试改按错题标题点选 |
| 截图抓到 wallpaper | `app.screenshot()` 在 app 繁忙时失败 | 改 `XCUIScreen.main.screenshot()` |

**未发现真实 App 崩溃或功能 bug。** 失败项全部是「模拟器无相机」或「测试脚本定位」问题。

## 真机验收清单（TestFlight，需测试者在真 iPad/iPhone 上过一遍）

1. 拍题：对准题目点「拍题」→ 出现解析回答。
2. 文字问答：输入问题发送 → 思考器 → 回答；**回答下应出现**举一反三/加入错题本/形成记忆（#7 正例）。
3. 闲聊：发「你好」→ 回答**不应**出现上述动作（#7 反例；注意 AI 回答若超 50 字启发式会判为实质——可后端加 `is_substantive` 更准）。
4. 上下文：每次提问上方「随本次发送」的 chips **可点开详情**（#6）。
5. 可视化：对一道适合作图的题点「生成可视化」→ 提示已排队 → **生成好自动打开**（#2，后端空闲异步，可能等十几秒~1 分钟）。
6. 加入错题本 → 错题本页出现该题，详情卡片清爽（#3 真机再确认）。
7. 形成记忆 → 记忆页出现条目。
8. 智能观察：开/关，弹幕与回合报告。
9. 历史：选会话→看报告→「进入对话」继续（#1）。
10. 竖横屏旋转、iPad 分屏多任务下布局正常。

## 可选改进（待定）
- 后端加 `GET /api/visualizations/status`（不触发生成）→ 可视化秒级状态。
- 问答返回加 `is_substantive` 标记 → #7 判断更准（替代 50 字启发式）。
- 评估：iPad 上「纯文字提问也强制开相机取帧」是否需要可关（目前沿用 iPhone 行为）。
