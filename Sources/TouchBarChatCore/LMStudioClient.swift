import Foundation

/// LM Studio HTTP client (Foundation only). Persistence is injected by the app layer.
public final class LMStudioClient: @unchecked Sendable {
    public private(set) var config: LMStudioConfig
    public private(set) var previousResponseID: String?
    public var persistConfig: ((LMStudioConfig) -> Void)?

    private let session: URLSession
    private let transporterQueue = DispatchQueue(label: "com.touchbarchat.app.stream")
    private var activeTransporter: SSETransporter?

    public init(config: LMStudioConfig = LMStudioConfig(), session: URLSession = .shared) {
        self.config = config
        self.session = session
    }

    public func updateConfig(_ config: LMStudioConfig) {
        self.config = config
        persistConfig?(config)
    }

    public func resetConversation() {
        previousResponseID = nil
    }

    public func cancelActiveChat() {
        let transporter = transporterQueue.sync { activeTransporter }
        transporter?.cancel()
    }

    public func listModels() async throws -> [String] {
        let url = try LMStudioAPI.endpoint(baseURL: config.baseURL, path: "/v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyAuth(&request)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LMStudioErrorMapping.mapTransportError(error)
        }
        try throwIfNeeded(response, data: data)
        return try LMStudioAPI.parseModelIDs(from: data)
    }

    public func chat(
        input: String,
        onPartial: ((String) -> Void)? = nil,
        onStatus: ((String) -> Void)? = nil
    ) async throws -> String {
        var workingConfig = config
        if workingConfig.model.isEmpty {
            let models = try await listModels()
            guard let first = models.first else { throw LMStudioError.noModels }
            workingConfig.model = first
            updateConfig(workingConfig)
        }

        let url = try LMStudioAPI.endpoint(baseURL: workingConfig.baseURL, path: "/api/v1/chat")
        let available = MCPPlugins.discoverPluginIDs()
        let body = LMStudioAPI.chatRequestBody(
            config: workingConfig,
            userText: input,
            previousResponseID: previousResponseID,
            stream: onPartial != nil,
            availablePluginIDs: available
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuth(&request)
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        if onPartial != nil {
            return try await streamChat(request: request, onPartial: onPartial!, onStatus: onStatus)
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw LMStudioErrorMapping.mapTransportError(error)
        }
        try throwIfNeeded(response, data: data)
        let parsed = try LMStudioAPI.parseChatResponse(data)
        if let id = parsed.responseID {
            previousResponseID = id
        }
        return parsed.text
    }

    // MARK: - Private

    private func applyAuth(_ request: inout URLRequest) {
        if let value = LMStudioAPI.authorizationHeader(apiToken: config.apiToken) {
            request.setValue(value, forHTTPHeaderField: "Authorization")
        }
    }

    private func throwIfNeeded(_ response: URLResponse, data: Data) throws {
        let code = (response as? HTTPURLResponse)?.statusCode
        try LMStudioAPI.throwIfNeeded(statusCode: code, data: data)
    }

    private func streamChat(
        request: URLRequest,
        onPartial: @escaping (String) -> Void,
        onStatus: ((String) -> Void)?
    ) async throws -> String {
        var req = request
        req.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        req.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        req.cachePolicy = .reloadIgnoringLocalCacheData

        let transporter = SSETransporter()
        transporterQueue.sync { activeTransporter = transporter }
        defer {
            transporterQueue.sync {
                if activeTransporter === transporter {
                    activeTransporter = nil
                }
            }
        }

        let (bytes, response) = try await transporter.bytes(for: req)
        try throwIfNeeded(response, data: Data())

        let assembler = SSEChatAssembler()
        var lineBuffer = Data()

        func emit(_ events: [SSEChatAssembler.Event]) {
            for event in events {
                switch event {
                case .partial(let text): onPartial(text)
                case .status(let status): onStatus?(status)
                }
            }
        }

        do {
            for try await chunk in bytes {
                try Task.checkCancellation()
                lineBuffer.append(chunk)
                while let range = lineBuffer.range(of: Data([0x0A])) {
                    let lineData = lineBuffer.subdata(in: lineBuffer.startIndex..<range.lowerBound)
                    lineBuffer.removeSubrange(lineBuffer.startIndex..<range.upperBound)
                    var line = String(data: lineData, encoding: .utf8) ?? ""
                    if line.hasSuffix("\r") { line.removeLast() }
                    emit(assembler.handleLine(line))
                }
            }
            if !lineBuffer.isEmpty,
               let line = String(data: lineBuffer, encoding: .utf8)?
                .trimmingCharacters(in: CharacterSet(charactersIn: "\r")) {
                emit(assembler.handleLine(line))
            }
            emit(assembler.flushEvent())
        } catch is CancellationError {
            throw LMStudioError.cancelled
        } catch {
            if Task.isCancelled { throw LMStudioError.cancelled }
            throw LMStudioErrorMapping.mapTransportError(error)
        }

        if Task.isCancelled {
            throw LMStudioError.cancelled
        }

        if let id = assembler.responseID {
            previousResponseID = id
        }

        let text = assembler.assembled.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            if let sawError = assembler.lastErrorMessage {
                throw LMStudioError.http(0, sawError)
            }
            throw LMStudioError.emptyResponse
        }
        return text
    }
}

/// URLSession data-delegate stream so SSE chunks arrive immediately (no full-body buffering).
final class SSETransporter: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private var continuation: AsyncThrowingStream<UInt8, Error>.Continuation?
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var session: URLSession!
    private var dataTask: URLSessionDataTask?
    private var didYieldResponse = false
    private var isCancelled = false

    override init() {
        super.init()
        let config = URLSessionConfiguration.ephemeral
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.timeoutIntervalForRequest = 600
        config.timeoutIntervalForResource = 600
        config.httpAdditionalHeaders = ["Accept": "text/event-stream", "Cache-Control": "no-cache"]
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }

    func bytes(for request: URLRequest) async throws -> (AsyncThrowingStream<UInt8, Error>, URLResponse) {
        let stream = AsyncThrowingStream<UInt8, Error> { continuation in
            self.continuation = continuation
        }

        let response: URLResponse = try await withCheckedThrowingContinuation { cont in
            self.responseContinuation = cont
            let task = session.dataTask(with: request)
            self.dataTask = task
            task.resume()
        }

        return (stream, response)
    }

    func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        dataTask?.cancel()
        if !didYieldResponse {
            responseContinuation?.resume(throwing: CancellationError())
            responseContinuation = nil
        }
        continuation?.finish(throwing: CancellationError())
        continuation = nil
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if isCancelled {
            completionHandler(.cancel)
            return
        }
        if !didYieldResponse {
            didYieldResponse = true
            responseContinuation?.resume(returning: response)
            responseContinuation = nil
        }
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard !isCancelled else { return }
        for byte in data {
            continuation?.yield(byte)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isCancelled {
            if !didYieldResponse {
                responseContinuation?.resume(throwing: CancellationError())
                responseContinuation = nil
            }
            continuation?.finish(throwing: CancellationError())
            continuation = nil
            return
        }
        if let error {
            if !didYieldResponse {
                responseContinuation?.resume(throwing: error)
                responseContinuation = nil
            }
            continuation?.finish(throwing: error)
        } else {
            continuation?.finish()
        }
        continuation = nil
        self.session.finishTasksAndInvalidate()
    }
}
