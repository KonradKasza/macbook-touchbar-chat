import Foundation

/// Pure LM Studio HTTP helpers: URLs, bodies, parsing (no networking).
public enum LMStudioAPI {
    public static func endpoint(baseURL: String, path: String) throws -> URL {
        let trimmed = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmed + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw LMStudioError.badURL
        }
        return url
    }

    public static func authorizationHeader(apiToken: String) -> String? {
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : "Bearer \(token)"
    }

    /// Inject standing instructions into every user prompt (AGENTS.md-style).
    public static func composeInput(userText: String, instructions: String) -> String {
        let trimmed = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return userText }
        return """
        <instructions>
        \(trimmed)
        </instructions>

        \(userText)
        """
    }

    /// Plugin integrations for the current config (empty when tools disabled).
    public static func integrationsPayload(
        from config: LMStudioConfig,
        availablePluginIDs: [String]
    ) -> [[String: Any]] {
        guard config.enableTools else { return [] }
        let ids: [String]
        if config.enabledMCPPluginIDs.isEmpty {
            ids = availablePluginIDs
        } else {
            ids = config.enabledMCPPluginIDs.filter {
                availablePluginIDs.contains($0) || $0.hasPrefix("mcp/")
            }
        }
        return ids.map { id -> [String: Any] in
            ["type": "plugin", "id": id]
        }
    }

    public static func chatRequestBody(
        config: LMStudioConfig,
        userText: String,
        previousResponseID: String?,
        stream: Bool,
        availablePluginIDs: [String]
    ) -> [String: Any] {
        let instructions = config.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let composedInput = composeInput(userText: userText, instructions: instructions)
        let integrations = integrationsPayload(from: config, availablePluginIDs: availablePluginIDs)

        var body: [String: Any] = [
            "model": config.model,
            "input": composedInput,
            "temperature": config.temperature,
            "stream": stream,
            "store": true
        ]
        if !integrations.isEmpty {
            body["integrations"] = integrations
            body["context_length"] = 8192
        }
        if !instructions.isEmpty, previousResponseID == nil {
            body["system_prompt"] = instructions
        }
        if let previousResponseID {
            body["previous_response_id"] = previousResponseID
        }
        return body
    }

    public static func parseModelIDs(from data: Data) throws -> [String] {
        struct ModelsResponse: Decodable {
            struct Model: Decodable { let id: String }
            let data: [Model]
        }
        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        return decoded.data.map(\.id)
    }

    public struct ChatParseResult: Equatable {
        public var responseID: String?
        public var text: String

        public init(responseID: String?, text: String) {
            self.responseID = responseID
            self.text = text
        }
    }

    public static func parseChatResponse(_ data: Data) throws -> ChatParseResult {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LMStudioError.decode
        }
        let id = json["response_id"] as? String
        guard let output = json["output"] as? [[String: Any]] else {
            throw LMStudioError.decode
        }
        let text = try textFromOutputItems(output)
        return ChatParseResult(responseID: id, text: text)
    }

    public static func textFromOutputItems(_ output: [[String: Any]]) throws -> String {
        let messages = output.compactMap { item -> String? in
            guard (item["type"] as? String) == "message",
                  let content = item["content"] as? String,
                  !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return content
        }
        let text = messages.joined(separator: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return text }

        let tools = output.compactMap { item -> String? in
            guard (item["type"] as? String) == "tool_call",
                  let tool = item["tool"] as? String else { return nil }
            return tool
        }
        if !tools.isEmpty {
            return "Used tools: " + tools.joined(separator: ", ")
        }
        throw LMStudioError.emptyResponse
    }

    public static func throwIfNeeded(statusCode: Int?, data: Data) throws {
        guard let statusCode else { return }
        guard (200..<300).contains(statusCode) else {
            throw LMStudioError.http(statusCode, httpErrorDetail(statusCode: statusCode, data: data))
        }
    }

    public static func httpErrorDetail(statusCode: Int, data: Data) -> String {
        let body = String(data: data, encoding: .utf8) ?? ""
        var detail = String(body.prefix(280))
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let err = json["error"] as? [String: Any],
           let message = err["message"] as? String {
            detail = message
            if statusCode == 403, message.localizedCaseInsensitiveContains("plugin") {
                detail += " — In LM Studio: Server Settings → allow mcp.json plugins, create an API token with plugin permission, paste it in TouchBar Chat Settings. Or menu → Tools → disable Enable Tools."
            }
        }
        return detail
    }
}

/// Incremental SSE chat event processor (testable without URLSession).
public final class SSEChatAssembler: @unchecked Sendable {
    public private(set) var assembled = ""
    public private(set) var responseID: String?
    public private(set) var lastErrorMessage: String?

    private var eventName = ""
    private var dataLines: [String] = []

    public init() {}

    public enum Event {
        case partial(String)
        case status(String)
    }

    @discardableResult
    public func handleLine(_ line: String) -> [Event] {
        if line.hasPrefix("event:") {
            eventName = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            return []
        }
        if line.hasPrefix("data:") {
            dataLines.append(String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces))
            return []
        }
        if line.isEmpty {
            return flushEvent()
        }
        return []
    }

    @discardableResult
    public func flushEvent() -> [Event] {
        defer {
            eventName = ""
            dataLines.removeAll(keepingCapacity: true)
        }
        guard !dataLines.isEmpty else { return [] }
        let payload = dataLines.joined(separator: "\n")
        if payload == "[DONE]" { return [] }
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        let type = (json["type"] as? String) ?? eventName
        var events: [Event] = []

        switch type {
        case "message.delta":
            if let delta = json["content"] as? String, !delta.isEmpty {
                assembled += delta
                events.append(.partial(assembled))
            }
        case "tool_call.start":
            let tool = (json["tool"] as? String) ?? "tool"
            events.append(.status("Tool: \(tool)…"))
        case "tool_call.success":
            let tool = (json["tool"] as? String) ?? "tool"
            events.append(.status("Tool: \(tool) ✓"))
        case "tool_call.failure":
            let reason = (json["reason"] as? String) ?? "failed"
            events.append(.status("Tool error: \(reason)"))
        case "chat.end":
            if let result = json["result"] as? [String: Any] {
                if let id = result["response_id"] as? String {
                    responseID = id
                }
                if let output = result["output"] as? [[String: Any]],
                   let finalText = try? LMStudioAPI.textFromOutputItems(output),
                   !finalText.isEmpty {
                    assembled = finalText
                    events.append(.partial(assembled))
                }
            }
        case "error":
            if let err = json["error"] as? [String: Any],
               let message = err["message"] as? String {
                lastErrorMessage = message
            }
        default:
            break
        }
        return events
    }
}
