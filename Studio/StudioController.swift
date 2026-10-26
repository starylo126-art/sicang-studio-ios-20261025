import UIKit
import WebKit
import UniformTypeIdentifiers
import ARKit
import AVFoundation

final class StudioController: UIViewController, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandlerWithReply, UIDocumentPickerDelegate {
    private var store: ResourceStore!
    private var server: LoopbackServer!
    private var webView: WKWebView!
    private let setup = UIStackView()
    private let status = UILabel()
    private let importButton = UIButton(type: .system)
    private var importing = false
    private var nativeFace: StudioFaceSession?
    private let faceFrameLock = NSLock()
    private var latestFaceFrame: [String: Any]?
    private var faceDeliveryScheduled = false
    private struct Export {
        let id: String
        let url: URL
        let handle: FileHandle
        let expected: Int
        var written: Int
    }
    private var export: Export?
    private let maximumExport = 150 * 1024 * 1024

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 0.97, green: 0.96, blue: 0.95, alpha: 1)
        buildSetup()
        do {
            store = try ResourceStore()
            let configuration = WKWebViewConfiguration()
            configuration.allowsInlineMediaPlayback = true
            configuration.mediaTypesRequiringUserActionForPlayback = []
            configuration.websiteDataStore = .default()
            configuration.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "studio")
            let faceSupported = ARFaceTrackingConfiguration.isSupported ? "true" : "false"
            configuration.userContentController.addUserScript(WKUserScript(source: "window.__studioNativeFaceAvailable=\(faceSupported);window.__studioShellVersion='1.2.6';", injectionTime: .atDocumentStart, forMainFrameOnly: true))
            webView = WKWebView(frame: .zero, configuration: configuration)
            webView.translatesAutoresizingMaskIntoConstraints = false
            webView.navigationDelegate = self
            webView.uiDelegate = self
            webView.isOpaque = false
            webView.backgroundColor = view.backgroundColor
            webView.scrollView.bounces = false
            webView.scrollView.contentInsetAdjustmentBehavior = .never
            nativeFace = StudioFaceSession { [weak self] value in self?.deliverFace(value) }
            NotificationCenter.default.addObserver(self, selector: #selector(pauseNativeFace), name: UIApplication.didEnterBackgroundNotification, object: nil)
            view.insertSubview(webView, belowSubview: setup)
            NSLayoutConstraint.activate([webView.topAnchor.constraint(equalTo: view.topAnchor), webView.bottomAnchor.constraint(equalTo: view.bottomAnchor), webView.leadingAnchor.constraint(equalTo: view.leadingAnchor), webView.trailingAnchor.constraint(equalTo: view.trailingAnchor)])
            server = LoopbackServer(store: store)
            server.start { [weak self] error in
                guard let self = self else { return }
                if let error = error { self.status.text = "本地服务启动失败：\(error.localizedDescription)。请关闭 App 后重试。"; return }
                self.importButton.isEnabled = true
                let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
                let update = UserDefaults.standard.string(forKey: "bundledResourceBuild") != build
                if let bundled = Bundle.main.url(forResource: "StarterResources", withExtension: "scstudio"), self.store.root == nil || update {
                    self.importResources(bundled)
                } else if self.store.root != nil { self.loadStudio() }
                else { self.status.text = "从「文件」选择电脑生成的 .scstudio 衣橱资源包。导入后无需联网。" }
            }
        } catch { status.text = error.localizedDescription }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        nativeFace?.setView(orientation: view.window?.windowScene?.interfaceOrientation ?? .portrait, size: view.bounds.size)
    }

    private func buildSetup() {
        let title = UILabel()
        title.text = "让衣橱里的角色动起来"
        title.font = .systemFont(ofSize: 23, weight: .medium)
        title.textColor = UIColor(red: 0.40, green: 0.32, blue: 0.47, alpha: 1)
        title.textAlignment = .center
        title.numberOfLines = 0
        status.text = "正在准备本地工作区…"
        status.font = .systemFont(ofSize: 15)
        status.textColor = .secondaryLabel
        status.numberOfLines = 0
        status.textAlignment = .center
        importButton.configuration = .filled()
        importButton.configuration?.title = "导入离线衣橱"
        importButton.configuration?.baseBackgroundColor = UIColor(red: 0.53, green: 0.44, blue: 0.62, alpha: 1)
        importButton.configuration?.cornerStyle = .large
        importButton.isEnabled = false
        importButton.addTarget(self, action: #selector(pickResources), for: .touchUpInside)
        setup.axis = .vertical
        setup.spacing = 24
        setup.addArrangedSubview(title)
        setup.addArrangedSubview(status)
        setup.addArrangedSubview(importButton)
        setup.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(setup)
        NSLayoutConstraint.activate([setup.centerYAnchor.constraint(equalTo: view.safeAreaLayoutGuide.centerYAnchor), setup.centerXAnchor.constraint(equalTo: view.centerXAnchor), setup.widthAnchor.constraint(lessThanOrEqualToConstant: 440), setup.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32), setup.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32), importButton.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)])
    }

    private func loadStudio() {
        webView.isHidden = false
        setup.isHidden = true
        webView.load(URLRequest(url: URL(string: LoopbackServer.origin + "/")!, cachePolicy: .reloadIgnoringLocalCacheData))
    }

    @objc private func pickResources() {
        guard !importing, presentedViewController == nil else { return }
        let type = UTType(filenameExtension: "scstudio") ?? .data
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [type], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first, !importing else { return }
        importResources(url)
    }

    private func importResources(_ url: URL) {
        guard !importing else { return }
        importing = true
        nativeFace?.stop()
        importButton.isEnabled = false
        // Stop camera and rendering before replacing resources.
        webView.loadHTMLString("", baseURL: nil)
        webView.isHidden = true
        setup.isHidden = false
        status.text = "正在校验并导入衣橱，请保持 App 在前台…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result = Result { try self.store.install(url) }
            DispatchQueue.main.async {
                self.importing = false
                self.importButton.isEnabled = true
                switch result {
                case .success:
                    UserDefaults.standard.set(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String, forKey: "bundledResourceBuild")
                    self.loadStudio()
                case .failure(let error):
                    self.status.text = error.localizedDescription
                    if self.store.root != nil { self.loadStudio(); self.alert(error.localizedDescription) }
                }
            }
        }
    }

    private func local(_ origin: WKSecurityOrigin) -> Bool { origin.protocol == "http" && origin.host == "127.0.0.1" && origin.port == Int(LoopbackServer.port) }

    func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        decisionHandler(local(origin) && frame.isMainFrame && type == .camera ? .prompt : .deny)
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else { decisionHandler(.cancel); return }
        if url.scheme == "about" || (url.scheme == "http" && url.host == "127.0.0.1" && url.port == Int(LoopbackServer.port)) { decisionHandler(.allow); return }
        if navigationAction.navigationType == .linkActivated && url.scheme == "https" { UIApplication.shared.open(url) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        status.text = "无法打开衣橱：\(error.localizedDescription)。请关闭 App 后重试。"
        setup.isHidden = false
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        nativeFace?.stop()
        loadStudio()
        alert("系统回收了画面进程，已重新打开衣橱。请重新开启摄像头；未完成的录制可能无法恢复。")
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
        guard message.frameInfo.isMainFrame, local(message.frameInfo.securityOrigin), let body = message.body as? [String: Any], let action = body["action"] as? String else { replyHandler(nil, "来源不允许"); return }
        do {
            switch action {
            case "startFace":
                nativeFace?.start { result in
                    switch result {
                    case .success(let sessionID): replyHandler(["ok": true, "delegate": "ARKit", "sessionID": sessionID], nil)
                    case .failure(let error): replyHandler(nil, error.localizedDescription)
                    }
                }
                return
            case "stopFace": nativeFace?.stop()
            case "calibrateFace":
                nativeFace?.calibrate { epoch in replyHandler(["ok": true, "calibrationEpoch": epoch], nil) }
                return
            case "import": pickResources()
            case "begin":
                guard export == nil, let id = body["id"] as? String, UUID(uuidString: id) != nil, let rawName = body["name"] as? String, let size = body["size"] as? Int, size > 0, size <= maximumExport else { throw StudioFailure("导出请求无效或已有文件正在保存。") }
                let name = String(rawName.map { character -> Character in "/\\:\0".contains(character) ? "_" : character }.prefix(150))
                let directory = FileManager.default.temporaryDirectory.appendingPathComponent("studio-export-" + id, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent(name.isEmpty ? "角色画面" : name)
                guard FileManager.default.createFile(atPath: url.path, contents: nil) else { throw StudioFailure("无法创建导出文件。") }
                export = Export(id: id, url: url, handle: try FileHandle(forWritingTo: url), expected: size, written: 0)
            case "chunk":
                guard var current = export, body["id"] as? String == current.id, let encoded = body["data"] as? String, encoded.count <= 65536, let data = Data(base64Encoded: encoded), current.written + data.count <= current.expected else { throw StudioFailure("导出数据无效。") }
                try current.handle.write(contentsOf: data)
                current.written += data.count
                export = current
            case "finish":
                guard let current = export, body["id"] as? String == current.id, current.written == current.expected, presentedViewController == nil else { throw StudioFailure("导出尚未完成，或另一个窗口仍在打开。") }
                try current.handle.close()
                export = nil
                let sheet = UIActivityViewController(activityItems: [current.url], applicationActivities: nil)
                sheet.popoverPresentationController?.sourceView = view
                sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.maxY - 70, width: 1, height: 1)
                sheet.completionWithItemsHandler = { _, _, _, _ in try? FileManager.default.removeItem(at: current.url.deletingLastPathComponent()) }
                present(sheet, animated: true)
            case "cancel":
                if let current = export, body["id"] as? String == current.id { try? current.handle.close(); try? FileManager.default.removeItem(at: current.url.deletingLastPathComponent()); export = nil }
            default: throw StudioFailure("未知操作。")
            }
            replyHandler(["ok": true], nil)
        } catch { replyHandler(nil, error.localizedDescription) }
    }

    private func alert(_ message: String) {
        guard presentedViewController == nil else { return }
        let alert = UIAlertController(title: "私藏动捕室", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    @objc private func pauseNativeFace() { nativeFace?.stop() }

    private func deliverFace(_ value: [String: Any]) {
        // One mailbox and one WebKit evaluation, regardless of camera rate.
        // An arriving sample REPLACES the pending sample instead of being lost
        // or appended behind old poses while the web content process is busy.
        faceFrameLock.lock()
        latestFaceFrame = value
        let schedule = !faceDeliveryScheduled
        faceDeliveryScheduled = true
        faceFrameLock.unlock()
        if schedule { DispatchQueue.main.async { [weak self] in self?.flushFaceFrame() } }
    }

    private func flushFaceFrame() {
        faceFrameLock.lock()
        let value = latestFaceFrame
        latestFaceFrame = nil
        if value == nil || importing { faceDeliveryScheduled = false }
        faceFrameLock.unlock()
        guard !importing, var value = value else { return }
        if let capturedAt = value["capturedAtMs"] as? Double {
            value["latency"] = max(0, Date().timeIntervalSince1970 * 1000 - capturedAt)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value), let json = String(data: data, encoding: .utf8) else { flushFaceFrame(); return }
        webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('studio-native-face',{detail:\(json)}))") { [weak self] _, _ in self?.flushFaceFrame() }
    }
}

/// Uses the system's face tracker instead of compiling a web inference engine
/// every time the camera opens. No camera image is sent to JavaScript or a server.
private final class StudioFaceSession: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private let trackingQueue = DispatchQueue(label: "studio.face-tracking", qos: .userInteractive)
    private let output: ([String: Any]) -> Void
    // requestGeneration is main-queue-only; all following tracking state lives
    // on trackingQueue. UIKit orientation is copied there by setView.
    private var requestGeneration = 0
    private var active = false
    private var sessionID = 0
    private var calibrationEpoch = 0
    private var lastProcessed: TimeInterval = 0
    private var reference: simd_float3x3?
    private var imageBasis: SIMD3<Float>?
    private var sourceMirrored: Bool?
    private var orientation: UIInterfaceOrientation = .portrait
    private var viewportSize = CGSize(width: 1, height: 1)
    init(output: @escaping ([String: Any]) -> Void) {
        self.output = output
        super.init()
        session.delegate = self
        session.delegateQueue = trackingQueue
    }
    func setView(orientation: UIInterfaceOrientation, size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        trackingQueue.async { [weak self] in
            guard let self = self else { return }
            if self.orientation != orientation {
                self.reference = nil
                self.imageBasis = nil
                self.sourceMirrored = nil
                self.calibrationEpoch += 1
            }
            self.orientation = orientation
            self.viewportSize = size
        }
    }
    func start(completion: @escaping (Result<Int, Error>) -> Void) {
        guard ARFaceTrackingConfiguration.isSupported else { completion(.failure(StudioFailure("此设备不支持系统人脸追踪。"))); return }
        requestGeneration += 1
        let request = requestGeneration
        let begin: (Bool) -> Void = { [weak self] granted in
            DispatchQueue.main.async {
                guard let self = self, request == self.requestGeneration else { completion(.failure(StudioFailure("相机启动已取消。"))); return }
                guard granted else { completion(.failure(StudioFailure("请在设置中允许私藏动捕室使用摄像头。"))); return }
                let config = ARFaceTrackingConfiguration()
                config.maximumNumberOfTrackedFaces = 1
                config.isLightEstimationEnabled = false
                let formats = ARFaceTrackingConfiguration.supportedVideoFormats
                let realTime = formats.filter { $0.framesPerSecond >= 60 }
                if let format = (realTime.isEmpty ? formats : realTime).min(by: { a, b in
                    let ap = a.imageResolution.width * a.imageResolution.height
                    let bp = b.imageResolution.width * b.imageResolution.height
                    if realTime.isEmpty { return a.framesPerSecond == b.framesPerSecond ? ap < bp : a.framesPerSecond > b.framesPerSecond }
                    return a.framesPerSecond == b.framesPerSecond ? ap < bp : a.framesPerSecond < b.framesPerSecond
                }) { config.videoFormat = format }
                self.trackingQueue.async {
                    self.reference = nil
                    self.imageBasis = nil
                    self.sourceMirrored = nil
                    self.calibrationEpoch += 1
                    self.lastProcessed = 0
                    self.sessionID = request
                    self.active = true
                    self.session.run(config, options: [.resetTracking, .removeExistingAnchors])
                    DispatchQueue.main.async { completion(.success(request)) }
                }
            }
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: begin(true)
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video, completionHandler: begin)
        default: begin(false)
        }
    }
    func stop() {
        requestGeneration += 1
        trackingQueue.async { self.active = false; self.reference = nil; self.session.pause() }
    }
    func calibrate(completion: @escaping (Int) -> Void) {
        trackingQueue.async {
            self.reference = nil
            self.calibrationEpoch += 1
            let epoch = self.calibrationEpoch
            DispatchQueue.main.async { completion(epoch) }
        }
    }
    private func emit(_ value: [String: Any], timestamp: TimeInterval? = nil) {
        var packet = value
        packet["sessionID"] = sessionID
        packet["calibrationEpoch"] = calibrationEpoch
        if let timestamp = timestamp {
            packet["timestamp"] = timestamp * 1000
            let latency = max(0, (ProcessInfo.processInfo.systemUptime - timestamp) * 1000)
            packet["latency"] = latency
            packet["capturedAtMs"] = Date().timeIntervalSince1970 * 1000 - latency
        }
        output(packet)
    }
    func session(_ session: ARSession, didUpdate incomingFrame: ARFrame) {
        // If a callback waited behind other work, use ARKit's newest complete
        // frame instead of replaying the queued historical camera samples.
        let frame = session.currentFrame ?? incomingFrame
        guard active, frame.timestamp > lastProcessed else { return }
        lastProcessed = frame.timestamp
        guard let face = frame.anchors.compactMap({ $0 as? ARFaceAnchor }).first, face.isTracked else { emit(["tracking": false], timestamp: frame.timestamp); return }
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        let relative = viewMatrix * face.transform
        let position = SIMD3(face.transform.columns.3.x, face.transform.columns.3.y, face.transform.columns.3.z)
        let projected = frame.camera.projectPoint(position, orientation: orientation, viewportSize: viewportSize)
        let center = CGPoint(x: projected.x / viewportSize.width, y: projected.y / viewportSize.height)
        let distance = simd_length(SIMD3(relative.columns.3.x, relative.columns.3.y, relative.columns.3.z))
        let viewRotation = simd_float3x3(columns: (SIMD3(relative.columns.0.x, relative.columns.0.y, relative.columns.0.z), SIMD3(relative.columns.1.x, relative.columns.1.y, relative.columns.1.z), SIMD3(relative.columns.2.x, relative.columns.2.y, relative.columns.2.z)))
        func project(_ world: SIMD4<Float>) -> CGPoint {
            frame.camera.projectPoint(SIMD3(world.x, world.y, world.z), orientation: orientation, viewportSize: viewportSize)
        }
        let leftEye = project(face.transform * face.leftEyeTransform.columns.3)
        let rightEye = project(face.transform * face.rightEyeTransform.columns.3)
        let forward = project(face.transform * SIMD4<Float>(0, 0, 0.04, 1))
        let up = project(face.transform * SIMD4<Float>(0, 0.04, 0, 1))
        if imageBasis == nil || sourceMirrored == nil {
            // ARKit's VIEW presentation may be reflected, whereas raw matrices
            // and anatomical blendshape names are different contracts. Measure
            // the actual projectPoint mapping instead of guessing a sign from
            // the fact that a front-facing camera is in use.
            let cameraToWorld = simd_inverse(viewMatrix)
            let origin = SIMD4<Float>(position.x, position.y, position.z, 1)
            let positiveX = project(origin + cameraToWorld.columns.0 * 0.01)
            let positiveY = project(origin + cameraToWorld.columns.1 * 0.01)
            let xDerivative = positiveX.x - projected.x
            let yDerivative = positiveY.y - projected.y
            let eye = CGPoint(x: leftEye.x - rightEye.x, y: leftEye.y - rightEye.y)
            let top = CGPoint(x: up.x - projected.x, y: up.y - projected.y)
            let eyeLength = hypot(eye.x, eye.y), topLength = hypot(top.x, top.y)
            // The anatomical-left eye axis and the face-up axis also work for
            // a tilted neutral pose. X ordering alone would reverse at 90° roll.
            let parity = (eye.x * top.y - eye.y * top.x) / max(0.001, eyeLength * topLength)
            guard abs(viewRotation.columns.2.z) > 0.7,
                  eyeLength > max(2, viewportSize.width * 0.005), topLength > 2,
                  abs(parity) > 0.6, abs(xDerivative) > 0.01, abs(yDerivative) > 0.01 else {
                emit(["tracking": false], timestamp: frame.timestamp)
                return
            }
            // Image basis: +X projects right, +Y projects up, +Z points from
            // the face toward the camera. A reflected image is allowed here;
            // JS normalizes its horizontal channels before the user option.
            imageBasis = SIMD3<Float>(xDerivative > 0 ? 1 : -1, yDerivative < 0 ? 1 : -1, relative.columns.3.z < 0 ? 1 : -1)
            sourceMirrored = parity > 0
        }
        let basis = simd_float3x3(diagonal: imageBasis!)
        let rotation = basis * viewRotation
        // Both R and R0 now use the observed camera-image axes. Their delta
        // keeps camera-image yaw/roll even if the source has a reflection.
        // Source parity is fixed for this orientation epoch; occlusion, large
        // turns, explicit calibration and brief face loss cannot flip it.
        if reference == nil { reference = rotation }
        let delta = rotation * simd_transpose(reference!)
        let matrix: [Float] = [delta.columns.0.x, delta.columns.0.y, delta.columns.0.z, 0, delta.columns.1.x, delta.columns.1.y, delta.columns.1.z, 0, delta.columns.2.x, delta.columns.2.y, delta.columns.2.z, 0, 0, 0, 0, 1]
        // Swift enum spelling is our wire contract. ARKit's rawValue strings
        // are not that contract (in particular the left/right suffixes).
        // Read typed keys directly; do not silently turn an unknown key into 0.
        let channels: [(String, ARFaceAnchor.BlendShapeLocation)] = [
            ("eyeBlinkLeft", .eyeBlinkLeft), ("eyeBlinkRight", .eyeBlinkRight),
            ("eyeWideLeft", .eyeWideLeft), ("eyeWideRight", .eyeWideRight),
            ("jawOpen", .jawOpen), ("mouthClose", .mouthClose),
            ("mouthSmileLeft", .mouthSmileLeft), ("mouthSmileRight", .mouthSmileRight),
            ("browInnerUp", .browInnerUp), ("browOuterUpLeft", .browOuterUpLeft),
            ("browOuterUpRight", .browOuterUpRight), ("browDownLeft", .browDownLeft),
            ("browDownRight", .browDownRight),
            ("eyeLookOutLeft", .eyeLookOutLeft), ("eyeLookInLeft", .eyeLookInLeft),
            ("eyeLookInRight", .eyeLookInRight), ("eyeLookOutRight", .eyeLookOutRight),
            ("eyeLookDownLeft", .eyeLookDownLeft), ("eyeLookDownRight", .eyeLookDownRight),
            ("eyeLookUpLeft", .eyeLookUpLeft), ("eyeLookUpRight", .eyeLookUpRight)
        ]
        var shapes: [String: Double] = [:]
        for (name, key) in channels { if let value = face.blendShapes[key] { shapes[name] = value.doubleValue } }
        guard shapes["eyeBlinkLeft"] != nil, shapes["eyeBlinkRight"] != nil else {
            emit(["tracking": false, "error": "系统未返回眼睑参数，请重新开启摄像头。"], timestamp: frame.timestamp)
            return
        }
        emit(["tracking": true, "coordinateSpace": "camera-image", "sourceMirrored": sourceMirrored!, "matrix": matrix, "center": [center.x, center.y], "distance": distance, "blendshapes": shapes,
              "directionBasis": ["viewSigns": [imageBasis!.x, imageBasis!.y, imageBasis!.z], "leftEyeX": leftEye.x / viewportSize.width, "rightEyeX": rightEye.x / viewportSize.width, "forwardX": (forward.x - projected.x) / viewportSize.width, "forwardY": (forward.y - projected.y) / viewportSize.height, "upX": (up.x - projected.x) / viewportSize.width, "upY": (up.y - projected.y) / viewportSize.height]], timestamp: frame.timestamp)
    }
    func session(_ session: ARSession, didFailWithError error: Error) { active = false; session.pause(); emit(["error": error.localizedDescription, "tracking": false]) }
    func sessionWasInterrupted(_ session: ARSession) { emit(["tracking": false]) }
}

