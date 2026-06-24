import Foundation
import Security
import SwiftUI

// Shared server base (kept in sync with ContentView.serverBaseURL)
let authServerBaseURL = URL(string: "https://xue.evowit.com")!

// MARK: - Keychain (stores the JWT access token)

enum AuthKeychain {
    private static let service = "com.linyibin8.xue.auth"
    private static let account = "access_token"

    static func save(_ token: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = Data(token.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }

    static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else { return nil }
        return token
    }

    static func clear() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Identity profile

struct IdentityProfile: Identifiable, Hashable {
    let id: String
    let type: String   // student / parent / teacher
    let name: String

    init?(_ json: [String: Any]) {
        guard let id = json["id"] as? String else { return nil }
        self.id = id
        self.type = (json["profile_type"] as? String) ?? "student"
        self.name = (json["display_name"] as? String) ?? ""
    }

    var typeLabel: String {
        switch type {
        case "parent": return "家长"
        case "teacher": return "老师"
        default: return "学生"
        }
    }
}

enum AuthError: LocalizedError {
    case network
    case badResponse
    case server(Int, String)

    var errorDescription: String? {
        switch self {
        case .network: return "网络错误，请检查连接后重试"
        case .badResponse: return "服务器返回异常"
        case .server(_, let message): return message
        }
    }
}

// MARK: - Auth session (single source of truth for login state)

@MainActor
final class AuthSession: ObservableObject {
    static let shared = AuthSession()

    @Published private(set) var token: String?
    @Published private(set) var email = ""
    @Published private(set) var accountName = ""
    @Published private(set) var profiles: [IdentityProfile] = []
    @Published private(set) var activeStudentId = ""
    @Published private(set) var isAuthenticated = false
    @Published private(set) var bootstrapping = true

    private let activeStudentKey = "xue.activeStudentId"

    private init() {}

    var authHeader: String? { token.map { "Bearer \($0)" } }
    var studentProfiles: [IdentityProfile] { profiles.filter { $0.type == "student" } }
    var activeStudentName: String {
        profiles.first(where: { $0.id == activeStudentId })?.name ?? ""
    }

    func bootstrap() async {
        activeStudentId = UserDefaults.standard.string(forKey: activeStudentKey) ?? ""
        if let saved = AuthKeychain.load(), !saved.isEmpty {
            token = saved
            isAuthenticated = true
            await refreshMe()
        }
        bootstrapping = false
    }

    func refreshMe() async {
        guard let token else { return }
        var request = URLRequest(url: authServerBaseURL.appending(path: "/api/auth/me"))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                await signOut()
                return
            }
            if http.statusCode == 200,
               let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                apply(json)
                isAuthenticated = true
            }
        } catch {
            // offline: keep existing token/session
        }
    }

    private func apply(_ json: [String: Any]) {
        if let user = json["user"] as? [String: Any] {
            email = (user["email"] as? String) ?? email
        }
        if let account = json["account"] as? [String: Any] {
            accountName = (account["name"] as? String) ?? accountName
        }
        if let rawProfiles = json["profiles"] as? [[String: Any]] {
            profiles = rawProfiles.compactMap { IdentityProfile($0) }
            let students = profiles.filter { $0.type == "student" }
            if activeStudentId.isEmpty || !students.contains(where: { $0.id == activeStudentId }) {
                setActiveStudent(students.first?.id ?? "")
            }
        }
    }

    func setActiveStudent(_ id: String) {
        activeStudentId = id
        UserDefaults.standard.set(id, forKey: activeStudentKey)
    }

    func login(email: String, password: String) async throws {
        try await submit(path: "/api/auth/login", body: ["email": email, "password": password])
    }

    func register(email: String, password: String, studentName: String) async throws {
        var body: [String: Any] = ["email": email, "password": password]
        let trimmed = studentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["student_name"] = trimmed }
        try await submit(path: "/api/auth/register", body: body)
    }

    private func submit(path: String, body: [String: Any]) async throws {
        var request = URLRequest(url: authServerBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw AuthError.network
        }
        guard let http = response as? HTTPURLResponse else { throw AuthError.network }
        guard (200..<300).contains(http.statusCode) else {
            let detail = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["detail"] as? String
            throw AuthError.server(http.statusCode, detail ?? "请求失败（\(http.statusCode)）")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["access_token"] as? String else {
            throw AuthError.badResponse
        }
        token = newToken
        AuthKeychain.save(newToken)
        apply(json)
        isAuthenticated = true
    }

    func signOut() async {
        token = nil
        isAuthenticated = false
        profiles = []
        email = ""
        accountName = ""
        AuthKeychain.clear()
    }

    /// Called by the networking layer on a 401 to force re-login.
    func handleUnauthorized() {
        Task { await signOut() }
    }
}

// MARK: - Login / register gate

struct AuthGateView: View {
    @ObservedObject private var auth = AuthSession.shared
    @State private var isRegister = false
    @State private var email = ""
    @State private var password = ""
    @State private var studentName = ""
    @State private var busy = false
    @State private var errorText = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.05, green: 0.12, blue: 0.18), Color(red: 0.02, green: 0.07, blue: 0.12)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            ).ignoresSafeArea()

            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 6) {
                        Text("知进伴学")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                        Text(isRegister ? "创建账号 · 开启学习陪伴" : "登录 · 继续你的学习")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(.top, 40)

                    VStack(spacing: 12) {
                        field(title: "邮箱", text: $email, keyboard: .emailAddress)
                        secureField(title: "密码（至少 8 位）", text: $password)
                        if isRegister {
                            field(title: "学生姓名（可选）", text: $studentName, keyboard: .default)
                        }

                        if !errorText.isEmpty {
                            Text(errorText)
                                .font(.footnote)
                                .foregroundStyle(.red)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }

                        Button(action: submit) {
                            HStack {
                                if busy { ProgressView().tint(.white) }
                                Text(isRegister ? "注册并进入" : "登录")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || email.isEmpty || password.count < 8)

                        Button(isRegister ? "已有账号？去登录" : "没有账号？去注册") {
                            withAnimation { isRegister.toggle(); errorText = "" }
                        }
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(18)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                    .padding(.horizontal, 22)

                    Text("xue.evowit.com")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.4))
                }
            }
        }
    }

    private func field(title: String, text: Binding<String>, keyboard: UIKeyboardType) -> some View {
        TextField("", text: text, prompt: Text(title).foregroundColor(.white.opacity(0.5)))
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .keyboardType(keyboard)
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func secureField(title: String, text: Binding<String>) -> some View {
        SecureField("", text: text, prompt: Text(title).foregroundColor(.white.opacity(0.5)))
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }

    private func submit() {
        busy = true
        errorText = ""
        Task {
            do {
                if isRegister {
                    try await auth.register(email: email.trimmingCharacters(in: .whitespaces), password: password, studentName: studentName)
                } else {
                    try await auth.login(email: email.trimmingCharacters(in: .whitespaces), password: password)
                }
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }
}

// MARK: - Account badge (identity switch + logout) shown in the workbench

struct AccountBadge: View {
    @ObservedObject private var auth = AuthSession.shared

    var body: some View {
        Menu {
            if !auth.email.isEmpty {
                Section(auth.accountName.isEmpty ? auth.email : "\(auth.accountName) · \(auth.email)") {
                    let students = auth.studentProfiles
                    if students.count > 1 {
                        ForEach(students) { profile in
                            Button {
                                auth.setActiveStudent(profile.id)
                            } label: {
                                Label(profile.name.isEmpty ? "学生" : profile.name,
                                      systemImage: profile.id == auth.activeStudentId ? "checkmark.circle.fill" : "person.circle")
                            }
                        }
                    }
                }
            }
            Button(role: .destructive) {
                Task { await auth.signOut() }
            } label: {
                Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "person.crop.circle")
                let title = auth.activeStudentName.isEmpty ? (auth.email.isEmpty ? "账号" : auth.email) : auth.activeStudentName
                Text(title).lineLimit(1)
            }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial, in: Capsule())
        }
    }
}
