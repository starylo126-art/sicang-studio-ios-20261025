import Foundation
import Network

/// One device, one stable origin. Never listens on the LAN.
final class LoopbackServer {
    static let port: UInt16 = 18765
    static let origin = "http://127.0.0.1:18765"
    private let queue = DispatchQueue(label: "studio.loopback")
    private var listener: NWListener?
    private let store: ResourceStore
    init(store: ResourceStore) { self.store = store }

    func start(completion: @escaping (Error?) -> Void) {
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: NWEndpoint.Port(rawValue: Self.port)!)
            let listener = try NWListener(using: parameters)
            self.listener = listener
            var notified = false
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if !notified { notified = true; DispatchQueue.main.async { completion(nil) } }
                case .failed(let error):
                    if !notified { notified = true; DispatchQueue.main.async { completion(error) } }
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self = self else { connection.cancel(); return }
                connection.start(queue: self.queue)
                self.receive(connection, buffer: Data())
                self.queue.asyncAfter(deadline: .now() + 30) { connection.cancel() }
            }
            listener.start(queue: queue)
        } catch { completion(error) }
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] data, _, finished, error in
            guard let self = self else { connection.cancel(); return }
            var bytes = buffer
            if let data = data { bytes.append(data) }
            guard bytes.count <= 16384 else { self.failure(connection, status: "431 Request Header Fields Too Large"); return }
            if let end = bytes.range(of: Data("\r\n\r\n".utf8)) {
                self.respond(connection, request: String(decoding: bytes[..<end.lowerBound], as: UTF8.self))
            } else if finished || error != nil { connection.cancel() }
            else { self.receive(connection, buffer: bytes) }
        }
    }

    private func failure(_ connection: NWConnection, status: String) {
        let text = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(text.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }

    private func respond(_ connection: NWConnection, request: String) {
        let lines = request.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ")
        guard parts.count == 3, parts[0] == "GET" || parts[0] == "HEAD" else { failure(connection, status: "405 Method Not Allowed"); return }
        // Prevent requests with an unrelated Host header from accessing this origin.
        let expectedHost = "127.0.0.1:\(Self.port)"
        guard lines.dropFirst().contains(where: { $0.lowercased() == "host: \(expectedHost)" }) else { failure(connection, status: "403 Forbidden"); return }
        guard let decoded = String(parts[1]).split(separator: "?", maxSplits: 1).first?.removingPercentEncoding, decoded.hasPrefix("/"), let root = store.root else { failure(connection, status: "404 Not Found"); return }
        let relative = decoded == "/" ? "index.html" : String(decoded.dropFirst())
        guard ResourceStore.validPath(relative) else { failure(connection, status: "403 Forbidden"); return }
        let url = root.appendingPathComponent(relative).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]), values.isRegularFile == true, let size = values.fileSize, let handle = try? FileHandle(forReadingFrom: url) else { failure(connection, status: "404 Not Found"); return }
        let types = ["html":"text/html; charset=utf-8", "js":"text/javascript; charset=utf-8", "mjs":"text/javascript; charset=utf-8", "css":"text/css; charset=utf-8", "json":"application/json", "wasm":"application/wasm", "png":"image/png", "webp":"image/webp", "jpg":"image/jpeg", "svg":"image/svg+xml", "ico":"image/x-icon"]
        let type = types[url.pathExtension.lowercased()] ?? "application/octet-stream"
        let header = "HTTP/1.1 200 OK\r\nContent-Type: \(type)\r\nContent-Length: \(size)\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
            guard error == nil, parts[0] != "HEAD", let self = self else { try? handle.close(); connection.cancel(); return }
            self.sendFile(handle, connection: connection)
        })
    }

    private func sendFile(_ handle: FileHandle, connection: NWConnection) {
        do {
            guard let bytes = try handle.read(upToCount: 65536), !bytes.isEmpty else { try? handle.close(); connection.cancel(); return }
            connection.send(content: bytes, completion: .contentProcessed { [weak self] error in
                guard error == nil, let self = self else { try? handle.close(); connection.cancel(); return }
                self.sendFile(handle, connection: connection)
            })
        } catch { try? handle.close(); connection.cancel() }
    }
}
