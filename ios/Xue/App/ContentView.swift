import AVFoundation
import SwiftUI
import UIKit

private let serverBaseURL = URL(string: "https://xue.evowit.com")!

struct ContentView: View {
    @StateObject private var state = AppState()

    var body: some View {
        VStack(spacing: 0) {
            CameraView(state: state)
                .overlay(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(state.modeTitle)
                            .font(.headline)
                        Text(state.sessionText)
                            .font(.caption)
                    }
                    .padding(10)
                    .background(.thinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
                }

            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Button {
                        state.requestSingleCapture()
                    } label: {
                        Label("拍题解析", systemImage: "camera.viewfinder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        state.toggleBurst()
                    } label: {
                        Label(state.isBursting ? "停止连拍" : "智能连拍", systemImage: state.isBursting ? "stop.circle" : "rectangle.stack")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                HStack {
                    Label(state.uploadState, systemImage: "antenna.radiowaves.left.and.right")
                    Spacer()
                    Text(serverBaseURL.host() ?? "")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(state.logs) { log in
                                Text(log.text)
                                    .font(.system(size: 12, design: .monospaced))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .id(log.id)
                            }
                        }
                    }
                    .frame(height: 170)
                    .onChange(of: state.logs.count) { _ in
                        if let last = state.logs.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
            .padding()
            .background(Color(.systemBackground))
        }
        .ignoresSafeArea(edges: .top)
        .task {
            state.log("App 启动，后端地址 \(serverBaseURL.absoluteString)")
        }
    }
}

struct LogLine: Identifiable {
    let id = UUID()
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var logs: [LogLine] = []
    @Published var uploadState = "待机"
    @Published var isBursting = false
    @Published var sessionId: String?

    var captureSingle: (() -> Void)?
    var captureBurstFrame: (() -> Void)?

    private var burstBuffer: [UIImage] = []
    private var burstTimer: Timer?
    private var secondTimer: Timer?
    private var lastFingerprint: Double?

    var modeTitle: String {
        isBursting ? "智能连拍学习回合" : "单张拍题解析"
    }

    var sessionText: String {
        sessionId.map { "回合 " + String($0.prefix(8)) } ?? "尚未创建学习回合"
    }

    func requestSingleCapture() {
        log("用户点击单张拍题，准备抓拍当前画面")
        uploadState = "拍照中"
        captureSingle?()
    }

    func toggleBurst() {
        isBursting ? stopBurst() : startBurst()
    }

    func startBurst() {
        isBursting = true
        burstBuffer.removeAll()
        uploadState = "创建学习回合"
        log("智能连拍启动：固定机位，开始观察画面变化")
        Task {
            await createSession()
            startTimers()
        }
    }

    func stopBurst() {
        isBursting = false
        burstTimer?.invalidate()
        secondTimer?.invalidate()
        burstTimer = nil
        secondTimer = nil
        log("智能连拍停止，剩余关键帧 \(burstBuffer.count) 张")
        Task { await flushBurst(reason: "用户停止连拍") }
    }

    func cameraDidOpen() {
        log("相机已打开，开始预览桌面课本/试卷")
    }

    func cameraFailed(_ message: String) {
        uploadState = "相机错误"
        log("相机错误：\(message)", level: "error")
    }

    func didCaptureSingle(_ image: UIImage) {
        log("单张照片已捕获，准备压缩上传")
        Task { await uploadSingle(image) }
    }

    func didCaptureBurstFrame(_ image: UIImage) {
        let fingerprint = imageFingerprint(image)
        let changed = lastFingerprint.map { abs($0 - fingerprint) > 6.0 } ?? true
        lastFingerprint = fingerprint
        if changed || burstBuffer.isEmpty {
            burstBuffer.append(image)
            log("检测到关键画面，加入批次缓存：\(burstBuffer.count) 张")
        } else {
            log("画面变化较小，本秒不加入关键帧")
        }
        if burstBuffer.count >= 3 {
            Task { await flushBurst(reason: "批次达到 3 张关键帧") }
        }
    }

    private func startTimers() {
        burstTimer?.invalidate()
        secondTimer?.invalidate()
        burstTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBursting else { return }
                self.log("智能连拍 tick：请求相机抓取候选帧")
                self.captureBurstFrame?()
            }
        }
        secondTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isBursting else { return }
                self.log("相机运行中：观察画面、等待关键变化、同步日志")
            }
        }
    }

    private func createSession() async {
        do {
            let data = try await postForm(path: "/api/sessions", fields: ["device_id": UIDevice.current.identifierForVendor?.uuidString ?? "iphone", "mode": "burst", "title": "智能连拍学习回合"], files: [])
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any], let id = json["session_id"] as? String {
                sessionId = id
                uploadState = "连拍中"
                log("学习回合创建成功：\(id)")
            }
        } catch {
            uploadState = "创建失败"
            log("创建学习回合失败：\(error.localizedDescription)", level: "error")
        }
    }

    private func uploadSingle(_ image: UIImage) async {
        uploadState = "上传单张"
        do {
            let jpeg = try jpegData(image)
            _ = try await postForm(path: "/api/solve-single", fields: ["device_id": UIDevice.current.identifierForVendor?.uuidString ?? "iphone"], files: [MultipartFile(field: "image", name: "question.jpg", mime: "image/jpeg", data: jpeg)])
            uploadState = "解析完成"
            log("单张拍题上传并解析完成，后端 dashboard 已更新")
        } catch {
            uploadState = "上传失败"
            log("单张拍题失败：\(error.localizedDescription)", level: "error")
        }
    }

    private func flushBurst(reason: String) async {
        guard let sessionId, !burstBuffer.isEmpty else { return }
        let frames = burstBuffer
        burstBuffer.removeAll()
        uploadState = "上传批次"
        log("上传智能连拍批次：\(reason)，共 \(frames.count) 张")
        do {
            let files = try frames.enumerated().map { index, image in
                MultipartFile(field: "images", name: "burst-\(index).jpg", mime: "image/jpeg", data: try jpegData(image))
            }
            _ = try await postForm(path: "/api/sessions/\(sessionId)/batches", fields: ["device_id": UIDevice.current.identifierForVendor?.uuidString ?? "iphone", "environment": "iPhone 固定机位，桌面课本/试卷学习场景"], files: files)
            uploadState = isBursting ? "连拍中" : "已停止"
            log("批次上传完成，后端将异步汇总学习报告")
        } catch {
            uploadState = "批次失败"
            log("批次上传失败：\(error.localizedDescription)", level: "error")
        }
    }

    func log(_ message: String, level: String = "info") {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        logs.append(LogLine(text: "[\(stamp)] \(message)"))
        if logs.count > 160 {
            logs.removeFirst(logs.count - 160)
        }
        Task { await uploadLog(message, level: level) }
    }

    private func uploadLog(_ message: String, level: String) async {
        var request = URLRequest(url: serverBaseURL.appending(path: "/api/logs"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = [
            "session_id": sessionId ?? NSNull(),
            "device_id": UIDevice.current.identifierForVendor?.uuidString ?? "iphone",
            "source": "ios",
            "level": level,
            "message": message
        ]
        request.httpBody = try? JSONSerialization.data(withJSONObject: payload)
        _ = try? await URLSession.shared.data(for: request)
    }

    private func postForm(path: String, fields: [String: String], files: [MultipartFile]) async throws -> Data {
        let boundary = "xue-\(UUID().uuidString)"
        var request = URLRequest(url: serverBaseURL.appending(path: path))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = makeMultipartBody(boundary: boundary, fields: fields, files: files)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    private func jpegData(_ image: UIImage) throws -> Data {
        let maxSide: CGFloat = 1600
        let size = image.size
        let ratio = min(1, maxSide / max(size.width, size.height))
        let target = CGSize(width: size.width * ratio, height: size.height * ratio)
        let renderer = UIGraphicsImageRenderer(size: target)
        let resized = renderer.image { _ in image.draw(in: CGRect(origin: .zero, size: target)) }
        guard let data = resized.jpegData(compressionQuality: 0.78) else {
            throw URLError(.cannotDecodeContentData)
        }
        return data
    }

    private func imageFingerprint(_ image: UIImage) -> Double {
        guard let cg = image.cgImage else { return 0 }
        let width = 8
        let height = 8
        var pixels = [UInt8](repeating: 0, count: width * height)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        pixels.withUnsafeMutableBytes { ptr in
            if let ctx = CGContext(data: ptr.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width, space: colorSpace, bitmapInfo: 0) {
                ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        return pixels.map(Double.init).reduce(0, +) / Double(pixels.count)
    }
}

struct MultipartFile {
    let field: String
    let name: String
    let mime: String
    let data: Data
}

private func makeMultipartBody(boundary: String, fields: [String: String], files: [MultipartFile]) -> Data {
    var body = Data()
    for (key, value) in fields {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
        body.append("\(value)\r\n")
    }
    for file in files {
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"\(file.field)\"; filename=\"\(file.name)\"\r\n")
        body.append("Content-Type: \(file.mime)\r\n\r\n")
        body.append(file.data)
        body.append("\r\n")
    }
    body.append("--\(boundary)--\r\n")
    return body
}

private extension Data {
    mutating func append(_ string: String) {
        append(Data(string.utf8))
    }
}

struct CameraView: UIViewControllerRepresentable {
    @ObservedObject var state: AppState

    func makeUIViewController(context: Context) -> CameraViewController {
        let controller = CameraViewController()
        controller.delegate = context.coordinator
        state.captureSingle = { [weak controller] in controller?.capture(kind: .single) }
        state.captureBurstFrame = { [weak controller] in controller?.capture(kind: .burst) }
        return controller
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(state: state)
    }

    final class Coordinator: NSObject, CameraViewControllerDelegate {
        let state: AppState

        init(state: AppState) {
            self.state = state
        }

        func cameraDidOpen() {
            Task { @MainActor in state.cameraDidOpen() }
        }

        func cameraFailed(_ message: String) {
            Task { @MainActor in state.cameraFailed(message) }
        }

        func didCapture(image: UIImage, kind: CaptureKind) {
            Task { @MainActor in
                switch kind {
                case .single:
                    state.didCaptureSingle(image)
                case .burst:
                    state.didCaptureBurstFrame(image)
                }
            }
        }
    }
}

enum CaptureKind {
    case single
    case burst
}

protocol CameraViewControllerDelegate: AnyObject {
    func cameraDidOpen()
    func cameraFailed(_ message: String)
    func didCapture(image: UIImage, kind: CaptureKind)
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    weak var delegate: CameraViewControllerDelegate?

    private let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var pendingKinds: [Int64: CaptureKind] = [:]

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    func capture(kind: CaptureKind) {
        let settings = AVCapturePhotoSettings()
        pendingKinds[settings.uniqueID] = kind
        output.capturePhoto(with: settings, delegate: self)
    }

    private func configure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    granted ? self?.setupSession() : self?.delegate?.cameraFailed("用户未授权相机")
                }
            }
        default:
            delegate?.cameraFailed("相机权限不可用")
        }
    }

    private func setupSession() {
        session.beginConfiguration()
        session.sessionPreset = .photo
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input),
              session.canAddOutput(output) else {
            delegate?.cameraFailed("无法初始化后置摄像头")
            return
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.delegate?.cameraDidOpen()
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let kind = pendingKinds.removeValue(forKey: photo.resolvedSettings.uniqueID) ?? .single
        if let error {
            delegate?.cameraFailed(error.localizedDescription)
            return
        }
        guard let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else {
            delegate?.cameraFailed("照片数据不可用")
            return
        }
        delegate?.didCapture(image: image, kind: kind)
    }
}
