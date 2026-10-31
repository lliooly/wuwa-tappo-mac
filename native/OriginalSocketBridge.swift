import Foundation

/// Changes only the WebSocket transport; Engine.IO/Socket.IO stays in the release JS.
final class OriginalSocketBridge: NSObject, URLSessionWebSocketDelegate {
    private struct Connection {
        let task: URLSessionWebSocketTask
        let emit: ([String: Any]) -> Void
    }
    private var connections: [String: Connection] = [:]
    private lazy var session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: .main)

    func open(id: String, url: URL, token: String, emit: @escaping ([String: Any]) -> Void) throws {
        guard connections[id] == nil, url.scheme == "wss",
              url.host == "api-mc-wuwatappo.kurogames-global.com",
              url.port == nil || url.port == 443,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.path == "/socket.io/",
              parts.queryItems?.first(where: { $0.name == "token" })?.value == token,
              !token.isEmpty else { throw CocoaError(.fileReadNoPermission) }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        let task = session.webSocketTask(with: request)
        task.taskDescription = id
        connections[id] = Connection(task: task, emit: emit)
        task.resume()
    }

    func send(id: String, text: String?, data: String?, completion: @escaping (String?) -> Void) {
        guard let connection = connections[id] else { completion("WebSocket is closed"); return }
        let message: URLSessionWebSocketTask.Message
        if let text = text { message = .string(text) }
        else if let raw = data, let bytes = Data(base64Encoded: raw) { message = .data(bytes) }
        else { completion("Invalid WebSocket frame"); return }
        connection.task.send(message) { error in
            DispatchQueue.main.async { completion(error == nil ? nil : "WebSocket send failed") }
        }
    }

    func close(id: String, code: Int, reason: String) {
        guard let connection = connections[id] else { return }
        connection.task.cancel(with: URLSessionWebSocketTask.CloseCode(rawValue: code) ?? .normalClosure,
                               reason: reason.data(using: .utf8))
    }

    func stop() {
        for connection in connections.values { connection.task.cancel(with: .goingAway, reason: nil) }
        connections.removeAll()
        session.invalidateAndCancel()
    }

    private func receive(_ task: URLSessionWebSocketTask) {
        guard let id = task.taskDescription, connections[id] != nil else { return }
        task.receive { [weak self, weak task] result in
            DispatchQueue.main.async {
                guard let self = self, let task = task, let connection = self.connections[id] else { return }
                switch result {
                case .success(.string(let text)):
                    connection.emit(["type": "message", "text": text]); self.receive(task)
                case .success(.data(let data)):
                    connection.emit(["type": "message", "data": data.base64EncodedString()]); self.receive(task)
                case .failure(let error):
                    self.fail(task, error: error)
                @unknown default:
                    self.close(id: id, code: 1003, reason: "Unsupported frame")
                }
            }
        }
    }

    private func fail(_ task: URLSessionTask, error: Error) {
        guard let id = task.taskDescription, let connection = connections.removeValue(forKey: id) else { return }
        let http = (task.response as? HTTPURLResponse)?.statusCode ?? 0
        connection.emit(["type": "error", "httpStatus": http, "errorCode": (error as NSError).code])
        connection.emit(["type": "close", "code": 1006, "reason": "", "wasClean": false])
        task.cancel()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        guard let id = webSocketTask.taskDescription, let connection = connections[id] else { return }
        connection.emit(["type": "open", "protocol": `protocol` ?? ""])
        receive(webSocketTask)
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask,
                    didCloseWith closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        guard let id = webSocketTask.taskDescription, let connection = connections.removeValue(forKey: id) else { return }
        connection.emit(["type": "close", "code": closeCode.rawValue,
                         "reason": reason.flatMap { String(data: $0, encoding: .utf8) } ?? "", "wasClean": true])
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error { fail(task, error: error) }
    }
}
