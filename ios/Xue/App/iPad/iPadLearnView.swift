import SwiftUI

enum iPadInputMode { case text, voice }

// iPad 学习工作台：左栏相机舞台 + 智能观察；右栏对话流 + 底部统一输入条
// （拍题 / 文字 / 语音 三合一，右下角切换语音⇄文字）。复用 iPhone 已验证的
// 相机管线、语音按钮、回答气泡，仅重排为 iPad 双栏。

struct iPadLearnView: View {
    @ObservedObject var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var draft = ""
    @State private var inputMode: iPadInputMode = .text
    @State private var previewAttachment: ChatAttachment?
    @State private var contextDetail: ContextBadgeItem?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                captureColumn
                    .frame(width: 320)
                    .background(Color(.secondarySystemBackground))
                Divider()
                conversationColumn
                    .frame(maxWidth: .infinity)
            }
            .navigationTitle("学习")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task {
            // 仅在真正空白时才新建对话；从历史「进入对话」已回放消息(chatMessages 非空)，不要清掉
            if state.sessionId == nil && state.chatMessages.isEmpty { state.startNewConversation() }
            #if DEBUG
            state.debugSeedChatIfRequested()
            #endif
        }
        .onDisappear {
            if !state.isBursting { state.hideInlineCameraPreview() }
        }
        .sheet(item: $previewAttachment) { iPadAttachmentPreview(attachment: $0) }
        .sheet(item: $contextDetail) { iPadContextDetailSheet(item: $0) }
    }

    // MARK: 工具栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigationBarTrailing) {
            Menu {
                Picker("学习模式", selection: Binding(get: { state.learningMode }, set: { state.learningMode = $0; state.coachPreferenceDidChange() })) {
                    ForEach(LearningModePreference.allCases) { Text($0.title).tag($0) }
                }
                Picker("讲解深度", selection: Binding(get: { state.coachDepth }, set: { state.coachDepth = $0; state.coachPreferenceDidChange() })) {
                    ForEach(CoachDepthPreference.allCases) { Text($0.title).tag($0) }
                }
            } label: {
                Label("偏好", systemImage: "slider.horizontal.3")
            }
            Button {
                state.startNewConversation()
                draft = ""
            } label: {
                Label("新对话", systemImage: "square.and.pencil")
            }
        }
    }

    // MARK: 左栏 — 相机 + 智能观察

    private var captureColumn: some View {
        VStack(spacing: 16) {
            cameraStage
            observationButton
            statusLine
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var cameraStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(Color.black)
            if state.cameraPreviewVisible {
                CameraView(state: state)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 40))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("点击下方相机按钮拍题")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if state.isBursting {
                VStack {
                    HStack {
                        Label("智能观察中", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(.red.opacity(0.85), in: Capsule())
                            .foregroundStyle(.white)
                        Spacer()
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
        .aspectRatio(3.0 / 4.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var observationButton: some View {
        Button {
            if state.isBursting { state.stopBurst() } else { state.startBurst() }
        } label: {
            Label(state.isBursting ? "停止观察" : "智能观察",
                  systemImage: state.isBursting ? "stop.circle.fill" : "eye")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(state.isBursting ? .red : .accentColor)
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            Image(systemName: state.qaSystemImage).foregroundStyle(.tint)
            Text(state.uploadState == "待机" ? state.qaStateText : state.uploadState)
                .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 右栏 — 对话流 + 底部统一输入条

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if state.chatMessages.isEmpty && !state.isThinking {
                            emptyConversationHint
                        }
                        ForEach(state.chatMessages) { message in
                            chatRow(message).id(message.id)
                        }
                        if state.isThinking {
                            thinkingRow.id("thinking-indicator")
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: state.chatMessages.count) { _ in scrollToBottom(proxy) }
                .onChange(of: state.isThinking) { thinking in if thinking { scrollToBottom(proxy) } }
            }
            Divider()
            composer
        }
        .background(Color(.systemGroupedBackground))
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        withAnimation {
            if state.isThinking {
                proxy.scrollTo("thinking-indicator", anchor: .bottom)
            } else if let last = state.chatMessages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private var emptyConversationHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开始学习").font(.title3.weight(.semibold))
            Text("拍下题目，或在下方输入 / 按住说话提问。AI 会结合你的学习目标、错题和记忆来辅导。")
                .font(.callout).foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    // 思考等待器（#5）
    private var thinkingRow: some View {
        HStack(alignment: .center, spacing: 10) {
            ProgressView()
            Text("AI 正在思考你的问题…")
                .font(.callout).foregroundStyle(.secondary)
            Spacer(minLength: 24)
        }
        .padding(12)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var latestAssistantId: UUID? {
        state.chatMessages.last(where: { $0.role == .assistant })?.id
    }

    // 仅在「有题目/有实质回答」时展示举一反三/加入错题本/形成记忆/可视化（#7）
    private func messageHasActions(_ m: ChatMessage) -> Bool {
        m.visualizationCandidate || m.text.count >= 50
    }

    @ViewBuilder
    private func chatRow(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                UserTextBubble(text: message.text)
                if !message.attachments.isEmpty {
                    AttachmentStrip(attachments: message.attachments) { previewAttachment = $0 }
                }
            }
        case .assistant:
            let acts = messageHasActions(message)
            AssistantAnswerBubble(
                answer: message.text,
                visualizationCandidate: message.visualizationCandidate,
                visualizationReason: message.visualizationReason,
                visualization: message.visualization,
                showFollowUpActions: message.id == latestAssistantId && acts,
                showAnswerActions: acts,
                onQuickFollowUp: { state.submitQuickFollowUp($0) },
                onAddMistake: { state.addLatestAnswerToMistakeBook() },
                onFormMemory: { state.formMemoryFromLatestAnswer() },
                onSmartCapture: { state.smartCaptureFromMessage(message) },
                onGenerateVisualization: { state.generateVisualization(for: message) },
                onOpenVisualization: { viz in if let url = viz.absoluteURL { openURL(url) } }
            )
        case .status:
            if !message.contextItems.isEmpty {
                iPadContextStatusRow(message: message) { contextDetail = $0 }
            } else {
                AssistantTextBubble(
                    title: message.title ?? "状态",
                    text: message.text,
                    systemImage: message.systemImage ?? "info.circle",
                    showsProgress: message.showsProgress
                )
            }
        }
    }

    // MARK: 底部统一输入条（拍题 / 文字 / 语音 三合一，右下角切换）（#4）

    private var composer: some View {
        HStack(spacing: 12) {
            if inputMode == .text {
                // 拍题
                Button {
                    if state.cameraPreviewVisible {
                        state.performCameraPrimaryAction()
                    } else {
                        state.openSingleCaptureCamera()
                    }
                } label: {
                    Image(systemName: "camera.fill").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("ipad-capture")

                TextField("输入问题，或先拍题…", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .accessibilityIdentifier("ipad-composer-field")
                    .focused($composerFocused)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .frame(maxWidth: .infinity)
                    .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    .contentShape(Rectangle())
                    .onSubmit(send)
                Button(action: send) {
                    Image(systemName: "paperplane.fill").font(.title3).frame(width: 44, height: 44)
                }
                .buttonStyle(.borderedProminent)
                .clipShape(Circle())
                .accessibilityIdentifier("ipad-composer-send")
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isThinking)
            } else {
                // 语音模式：占满整条，按钮更大更好按
                VoiceHoldArea(state: state, allowsCollapse: false, pressHeight: 52)
                    .frame(maxWidth: .infinity)
            }

            // 右下角：语音⇄文字 切换
            Button {
                composerFocused = false
                withAnimation { inputMode = inputMode == .text ? .voice : .text }
            } label: {
                Image(systemName: inputMode == .text ? "mic.fill" : "keyboard")
                    .font(.title3)
                    .frame(width: 44, height: 52)
            }
            .buttonStyle(.bordered)
            .tint(inputMode == .voice ? .accentColor : .secondary)
            .accessibilityIdentifier("ipad-input-toggle")
        }
        .padding(16)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !state.isThinking else { return }
        state.submitTypedQuestion(text)
        draft = ""
        composerFocused = false
    }
}

// MARK: - 上下文：本次携带的上下文（可点击查看）（#6）

struct iPadContextStatusRow: View {
    let message: ChatMessage
    let onTap: (ContextBadgeItem) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: message.systemImage ?? "tray.full")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 8) {
                Text(message.title ?? "随本次发送")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if !message.text.isEmpty {
                    Text(message.text)
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    ForEach(message.contextItems) { item in
                        Button { onTap(item) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: item.systemImage).font(.caption2)
                                Text(item.title).font(.caption.weight(.medium)).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 9))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(item.tone.color.opacity(0.12), in: Capsule())
                            .foregroundStyle(item.tone.color)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(11)
            .background(Color(.systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer(minLength: 24)
        }
    }
}

struct iPadContextDetailSheet: View {
    let item: ContextBadgeItem
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Label(item.title, systemImage: item.systemImage)
                        .font(.headline)
                        .foregroundStyle(item.tone.color)
                    Text((item.fullDetail ?? item.detail).isEmpty ? "（无更多详情）" : (item.fullDetail ?? item.detail))
                        .font(.body)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(20)
            }
            .navigationTitle("上下文详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}

// MARK: - 附件预览

struct iPadAttachmentPreview: View {
    let attachment: ChatAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = attachment.image {
                    Image(uiImage: image).resizable().scaledToFit()
                } else if let url = attachment.fullURL ?? attachment.thumbnailURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let img): img.resizable().scaledToFit()
                        case .failure: Image(systemName: "photo").foregroundStyle(.white)
                        default: ProgressView().tint(.white)
                        }
                    }
                } else {
                    Text(attachment.detail).foregroundStyle(.white)
                }
            }
            .navigationTitle(attachment.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
