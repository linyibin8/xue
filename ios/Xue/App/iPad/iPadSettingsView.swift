import SwiftUI

// iPad 设置：表单式。学习偏好 / 上下文开关 / 语音 / 学生档案 / 账号。
// 全部复用 AppState 与 AuthSession 现有的已持久化 setter。

struct iPadSettingsView: View {
    @ObservedObject var state: AppState
    @ObservedObject var auth: AuthSession

    @State private var showAddStudent = false
    @State private var newStudentName = ""

    private var students: [IdentityProfile] {
        auth.profiles.filter { $0.type == "student" }
    }

    var body: some View {
        NavigationStack {
            Form {
                preferenceSection
                questionSection
                contextSection
                voiceSection
                studentSection
                accountSection
            }
            .formStyle(.grouped)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
        }
        .alert("添加学生", isPresented: $showAddStudent) {
            TextField("学生姓名", text: $newStudentName)
            Button("取消", role: .cancel) { newStudentName = "" }
            Button("添加") {
                let name = newStudentName.trimmingCharacters(in: .whitespacesAndNewlines)
                newStudentName = ""
                guard !name.isEmpty else { return }
                Task { try? await auth.addProfile(type: "student", name: name) }
            }
        }
    }

    private var preferenceSection: some View {
        Section("学习偏好") {
            Picker("学习模式", selection: Binding(get: { state.learningMode }, set: { state.learningMode = $0; state.coachPreferenceDidChange() })) {
                ForEach(LearningModePreference.allCases) { Text($0.title).tag($0) }
            }
            Picker("讲解深度", selection: Binding(get: { state.coachDepth }, set: { state.coachDepth = $0; state.coachPreferenceDidChange() })) {
                ForEach(CoachDepthPreference.allCases) { Text($0.title).tag($0) }
            }
        }
    }

    private var questionSection: some View {
        Section {
            Toggle(isOn: Binding(get: { state.textOnlyQuestion }, set: { state.textOnlyQuestionDidChange($0) })) {
                Label("纯文字提问（不开相机）", systemImage: "keyboard")
            }
        } header: {
            Text("提问")
        } footer: {
            Text("开启后打字/快捷追问不会打开相机或抓取画面，按纯文字理解。拍题、语音、智能观察不受影响。")
        }
    }

    private var contextSection: some View {
        Section {
            contextToggle("视觉画面", systemImage: "photo", keyPath: \.visual, value: state.contextInclusionSettings.visual)
            contextToggle("智能观察", systemImage: "eye", keyPath: \.observation, value: state.contextInclusionSettings.observation)
            contextToggle("历史记录", systemImage: "clock", keyPath: \.history, value: state.contextInclusionSettings.history)
            contextToggle("错题本", systemImage: "exclamationmark.bubble", keyPath: \.mistakes, value: state.contextInclusionSettings.mistakes)
            contextToggle("知识库", systemImage: "books.vertical", keyPath: \.knowledge, value: state.contextInclusionSettings.knowledge)
            contextToggle("长期记忆", systemImage: "brain.head.profile", keyPath: \.memory, value: state.contextInclusionSettings.memory)
            contextToggle("学习策略", systemImage: "target", keyPath: \.strategy, value: state.contextInclusionSettings.strategy)
        } header: {
            Text("AI 上下文")
        } footer: {
            Text("控制 AI 回答时参考哪些信息。关闭某项可让回答更聚焦当前题目。")
        }
    }

    private func contextToggle(_ title: String, systemImage: String,
                               keyPath: WritableKeyPath<ContextInclusionSettings, Bool>,
                               value: Bool) -> some View {
        Toggle(isOn: Binding(get: { value }, set: { state.updateContextInclusion(keyPath, to: $0) })) {
            Label(title, systemImage: systemImage)
        }
    }

    private var voiceSection: some View {
        Section("语音朗读") {
            Toggle(isOn: Binding(get: { state.voicePlaybackEnabled }, set: { state.voicePlaybackEnabledDidChange($0) })) {
                Label("自动朗读回答", systemImage: "speaker.wave.2")
            }
            if state.voicePlaybackEnabled {
                VStack(alignment: .leading) {
                    Text("朗读语速 \(String(format: "%.2f", state.voicePlaybackRate))×")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Slider(value: Binding(get: { state.voicePlaybackRate }, set: { state.voicePlaybackRateDidChange($0) }),
                           in: 0.75...2.0, step: 0.25)
                }
            }
        }
    }

    private var studentSection: some View {
        Section {
            ForEach(students) { profile in
                HStack {
                    Label(profile.name, systemImage: "graduationcap")
                    Spacer()
                    if profile.id == auth.activeStudentId {
                        Text("当前").font(.caption).foregroundStyle(.tint)
                    } else {
                        Button("设为当前") { auth.setActiveStudent(profile.id) }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
            }
            .onDelete { indexSet in
                for index in indexSet {
                    let id = students[index].id
                    Task { try? await auth.deleteProfile(id: id) }
                }
            }
            Button {
                showAddStudent = true
            } label: {
                Label("添加学生", systemImage: "plus.circle")
            }
        } header: {
            Text("学生档案")
        }
    }

    private var accountSection: some View {
        Section("账号") {
            LabeledContent("邮箱", value: auth.email)
            if !auth.accountName.isEmpty {
                LabeledContent("账号名", value: auth.accountName)
            }
            Button(role: .destructive) {
                Task { await auth.signOut() }
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        }
    }
}
