import Foundation
import CryptoKit

struct StudioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}

/// Streaming, hash-checked resource import. Failed imports never replace the active pack.
final class ResourceStore {
    struct Entry: Decodable { let path: String; let size: UInt64; let sha256: String }
    struct Manifest: Decodable { let format: String; let version: Int; let files: [Entry] }
    private let base: URL
    private let lock = NSLock()
    private var active: URL?
    var root: URL? { lock.lock(); defer { lock.unlock() }; return active }

    init() throws {
        base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("Wardrobe", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        if let id = UserDefaults.standard.string(forKey: "activeResourceVersion"), UUID(uuidString: id) != nil {
            let url = base.appendingPathComponent(id, isDirectory: true)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("index.html").path) { active = url }
        }
    }

    static func validPath(_ path: String) -> Bool {
        !path.isEmpty && path.utf8.count < 512 && !path.contains("\\") && !path.contains(":") && !path.contains("\0") && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    func install(_ url: URL) throws {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        func read(_ length: Int) throws -> Data {
            var result = Data()
            while result.count < length {
                let next = try input.read(upToCount: length - result.count) ?? Data()
                guard !next.isEmpty else { throw StudioFailure("资源包不完整，请重新传输文件。") }
                result.append(next)
            }
            return result
        }
        guard try read(10) == Data("SCSTUDIO1\n".utf8) else { throw StudioFailure("请选择本项目生成的 .scstudio 资源包。") }
        let lengthBytes = try read(4)
        let manifestLength = lengthBytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8 * $1.offset) }
        guard manifestLength > 0 && manifestLength <= 2_000_000 else { throw StudioFailure("资源目录长度不正确。") }
        let manifest = try JSONDecoder().decode(Manifest.self, from: read(Int(manifestLength)))
        guard manifest.format == "private-wardrobe-resources", manifest.version == 1, !manifest.files.isEmpty, manifest.files.count <= 5000 else { throw StudioFailure("不支持此资源包版本。") }
        var paths = Set<String>(), total: UInt64 = 0
        for entry in manifest.files {
            guard Self.validPath(entry.path), paths.insert(entry.path).inserted, entry.size <= 64 * 1024 * 1024, entry.sha256.count == 64 else { throw StudioFailure("资源包中存在无效文件。") }
            total += entry.size
            guard total <= 250 * 1024 * 1024 else { throw StudioFailure("资源包超过 250 MB 上限。") }
        }
        let required: Set<String> = ["index.html", "wardrobe.html", "src/studio.js", "src/vision-worker.js", "models/face_landmarker.task", "vendor/mediapipe/vision_bundle.mjs"]
        guard required.isSubset(of: paths) else { throw StudioFailure("资源包缺少衣橱或动捕文件。") }
        let id = UUID().uuidString
        let staging = base.appendingPathComponent(id, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        var committed = false
        defer { if !committed { try? FileManager.default.removeItem(at: staging) } }
        for entry in manifest.files {
            let destination = staging.appendingPathComponent(entry.path)
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw StudioFailure("无法写入资源，请检查可用空间。") }
            let output = try FileHandle(forWritingTo: destination)
            defer { try? output.close() }
            var hash = SHA256(), remaining = entry.size
            while remaining > 0 {
                let bytes = try read(Int(min(remaining, 65536)))
                try output.write(contentsOf: bytes)
                hash.update(data: bytes)
                remaining -= UInt64(bytes.count)
            }
            let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
            guard digest == entry.sha256 else { throw StudioFailure("文件校验失败：\(entry.path)。请重新传输资源包。") }
        }
        guard (try input.read(upToCount: 1) ?? Data()).isEmpty else { throw StudioFailure("资源包包含多余数据。") }
        UserDefaults.standard.set(id, forKey: "activeResourceVersion")
        lock.lock(); active = staging; lock.unlock()
        committed = true
        // Keep older packs until the next import; never delete the currently served version.
        let versions = (try? FileManager.default.contentsOfDirectory(at: base, includingPropertiesForKeys: [.creationDateKey])) ?? []
        let older = versions.filter { $0 != staging && UUID(uuidString: $0.lastPathComponent) != nil }.sorted {
            ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        for obsolete in older.dropFirst() { try? FileManager.default.removeItem(at: obsolete) }
    }
}
