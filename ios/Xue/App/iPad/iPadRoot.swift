import SwiftUI

// MARK: - iPad 原生端
// 与 iPhone 共享同一套核心：AppState / AuthSession / 所有数据模型 / 所有 API 调用。
// 这里只重写「容器 + 导航 + 布局」，把 iPhone 的横屏沉浸工作台换成 iPad 原生的
// NavigationSplitView 主从结构（侧栏 + 详情）。每个功能仍然调用 AppState 现有方法，
// 所以后端契约一变，两端自动同步。详见 docs/MULTI_CLIENT_GUIDE.md。

enum iPadSection: String, CaseIterable, Identifiable {
    case learn, history, mistakes, memory, settings
    var id: String { rawValue }

    var title: String {
        switch self {
        case .learn: return "学习"
        case .history: return "历史"
        case .mistakes: return "错题本"
        case .memory: return "记忆"
        case .settings: return "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .learn: return "sparkles"
        case .history: return "clock.arrow.circlepath"
        case .mistakes: return "exclamationmark.bubble"
        case .memory: return "brain.head.profile"
        case .settings: return "gearshape"
        }
    }
}

struct iPadRootView: View {
    @StateObject private var state = AppState()
    @ObservedObject private var auth = AuthSession.shared
    @State private var section: iPadSection?
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    init() {
        #if DEBUG
        if let s = ProcessInfo.processInfo.environment["XUE_IPAD_SECTION"],
           let sec = iPadSection(rawValue: s) {
            _section = State(initialValue: sec)
            return
        }
        #endif
        _section = State(initialValue: .learn)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
        } detail: {
            detail
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            state.startDeviceControlPolling()
            await auth.refreshOps()
        }
    }

    private var sidebar: some View {
        List(selection: $section) {
            Section {
                ForEach(iPadSection.allCases) { sec in
                    Label(sec.title, systemImage: sec.systemImage)
                        .tag(sec)
                        .accessibilityIdentifier("ipad-section-\(sec.rawValue)")
                }
            } header: {
                iPadStudentSwitcher(auth: auth)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("知进伴学")
        .safeAreaInset(edge: .bottom) {
            iPadAccountFooter(auth: auth)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch section ?? .learn {
        case .learn: iPadLearnView(state: state)
        case .history: iPadHistoryView(state: state, onContinue: { section = .learn })
        case .mistakes: iPadMistakesView(state: state)
        case .memory: iPadMemoryView(state: state)
        case .settings: iPadSettingsView(state: state, auth: auth)
        }
    }
}

// MARK: - 学生档案切换（侧栏顶部）

struct iPadStudentSwitcher: View {
    @ObservedObject var auth: AuthSession

    private var students: [IdentityProfile] {
        auth.profiles.filter { $0.type == "student" }
    }

    private var activeName: String {
        students.first(where: { $0.id == auth.activeStudentId })?.name
            ?? students.first?.name
            ?? "未选择学生"
    }

    var body: some View {
        Menu {
            ForEach(students) { profile in
                Button {
                    auth.setActiveStudent(profile.id)
                } label: {
                    if profile.id == auth.activeStudentId {
                        Label(profile.name, systemImage: "checkmark")
                    } else {
                        Text(profile.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.circle")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text(activeName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("当前学生")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
        .disabled(students.isEmpty)
    }
}

// MARK: - 账号 + 配额（侧栏底部）

struct iPadAccountFooter: View {
    @ObservedObject var auth: AuthSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Divider()
            HStack(spacing: 8) {
                Image(systemName: "envelope")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(auth.email.isEmpty ? auth.accountName : auth.email)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if auth.quotaEnabled {
                HStack(spacing: 6) {
                    Image(systemName: "bolt.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("今日免费额度剩余 \(max(auth.quotaRemaining, 0))/\(auth.quotaLimit)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            if auth.bgActive {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.7)
                    Text("后台生成中" + (auth.bgEtaSeconds > 0 ? " · 约\(auth.bgEtaSeconds)s" : ""))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
    }
}
