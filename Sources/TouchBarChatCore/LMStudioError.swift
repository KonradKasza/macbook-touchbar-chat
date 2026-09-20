import Foundation

public enum LMStudioError: LocalizedError, Equatable, Sendable {
    case badURL
    case http(Int, String)
    case decode
    case emptyResponse
    case noModels
    case serverDown(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .badURL: return "Invalid LM Studio base URL."
        case .http(let code, let body): return "LM Studio HTTP \(code): \(body)"
        case .decode: return "Could not parse LM Studio response."
        case .emptyResponse: return "Empty response from model."
        case .noModels: return "No models available. Start the LM Studio server and load a model."
        case .serverDown(let detail):
            return "LM Studio server is not running (\(detail)). In LM Studio open Developer and toggle Start server — loading a model alone is not enough. Or run: lms server start"
        case .cancelled: return "Generation stopped."
        }
    }
}

public enum LMStudioErrorMapping {
    public static func mapTransportError(_ error: Error) -> LMStudioError {
        if error is CancellationError { return .cancelled }
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain {
            switch ns.code {
            case NSURLErrorCancelled:
                return .cancelled
            case NSURLErrorCannotConnectToHost, NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotFindHost, NSURLErrorNotConnectedToInternet:
                return .serverDown(ns.localizedDescription)
            default:
                break
            }
        }
        return .serverDown(error.localizedDescription)
    }
}
