import SwiftUI

// iPad 学习工作台：左栏相机舞台 + 拍题/观察/语音控制，右栏对话流 + 输入器。
// 复用 iPhone 已验证的相机管线（CameraView）、语音按钮（VoiceHoldArea）、
// 回答气泡（AssistantAnswerBubble 等），仅重排为 iPad 横向双栏。

struct iPadLearnView: View {
    @ObservedObject var state: AppState
    @Environment(\.openURL) private var openURL

    @State private var draft = ""
    @State private var previewAttachment: ChatAttachment?
    @FocusState private var composerFocused: Bool

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                captureColumn
                    .frame(width: 440)
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
            if state.sessionId == nil { state.startNewConversation() }
        }
        .onDisappear {
            if !state.isBursting { state.hideInlineCameraPreview() }
        }
        .sheet(item: $previewAttachment) { attachment in
            iPadAttachmentPreview(attachment: attachment)
        }
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

    // MARK: 左栏 — 相机 + 控制

    private var captureColumn: some View {
        VStack(spacing: 16) {
            cameraStage
            controlRow
            VoiceHoldArea(state: state, allowsCollapse: false)
                .frame(maxWidth: .infinity)
            statusLine
            Spacer(minLength: 0)
        }
        .padding(20)
    }

    private var cameraStage: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(Color.black)
            if state.cameraPreviewVisible {
                CameraView(state: state)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 44))
                        .foregroundStyle(.white.opacity(0.7))
                    Text("点击下方「拍题」打开相机")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            if state.isBursting {
                VStack {
                    HStack {
                        Label("智能观察中", systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
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

    private var controlRow: some View {
        HStack(spacing: 14) {
            Button {
                if state.cameraPreviewVisible {
                    state.performCameraPrimaryAction()
                } else {
                    state.openSingleCaptureCamera()
                }
            } label: {
                Label(state.cameraPreviewVisible ? "拍照" : "拍题",
                      systemImage: "camera.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("ipad-capture")

            Button {
                if state.isBursting { state.stopBurst() } else { state.startBurst() }
            } label: {
                Label(state.isBursting ? "停止观察" : "智能观察",
                      systemImage: state.isBursting ? "stop.circle.fill" : "eye")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.bordered)
            .tint(state.isBursting ? .red : .accentColor)
        }
    }

    private var statusLine: some View {
        HStack(spacing: 8) {
            if state.isThinking || state.isPreparingVoiceInput {
                ProgressView().scaleEffect(0.8)
            }
            Image(systemName: state.qaSystemImage)
                .foregroundStyle(.tint)
            Text(state.uploadState == "待机" ? state.qaStateText : state.uploadState)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 右栏 — 对话流 + 输入器

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if state.chatMessages.isEmpty {
                            emptyConversationHint
                        }
                        ForEach(state.chatMessages) { message in
                            chatRow(message)
                                .id(message.id)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: 760, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: state.chatMessages.count) { _ in
                    if let last = state.chatMessages.last {
                        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                    }
                }
            }
            Divider()
            composer
        }
        .background(Color(.systemGroupedBackground))
    }

    private var emptyConversationHint: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("开始学习")
                .font(.title3.weight(.semibold))
            Text("拍下题目，或直接在下方输入问题。AI 会结合你的学习目标、错题和记忆来辅导。")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 40)
    }

    private var latestAssistantId: UUID? {
        state.chatMessages.last(where: { $0.role == .assistant })?.id
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
            AssistantAnswerBubble(
                answer: message.text,
                visualizationCandidate: message.visualizationCandidate,
                visualizationReason: message.visualizationReason,
                visualization: message.visualization,
                showFollowUpActions: message.id == latestAssistantId,
                onQuickFollowUp: { state.submitQuickFollowUp($0) },
                onAddMistake: { state.addLatestAnswerToMistakeBook() },
                onFormMemory: { state.formMemoryFromLatestAnswer() },
                onSmartCapture: { state.smartCaptureFromMessage(message) },
                onGenerateVisualization: { state.generateVisualization(for: message) },
                onOpenVisualization: { viz in
                    if let url = viz.absoluteURL { openURL(url) }
                }
            )
        case .status:
            AssistantTextBubble(
                title: message.title ?? "状态",
                text: message.text,
                systemImage: message.systemImage ?? "info.circle",
                showsProgress: message.showsProgress
            )
        }
    }

    private var composer: some View {
        HStack(spacing: 12) {
            TextField("输入问题，或先拍题…", text: $draft, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain)
                .focused($composerFocused)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "paperplane.fill")
                    .font(.title3)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.borderedProminent)
            .clipShape(Circle())
            .accessibilityIdentifier("ipad-composer-send")
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.isThinking)
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

// MARK: - 附件预览

struct iPadAttachmentPreview: View {
    let attachment: ChatAttachment
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                if let image = attachment.image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
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
