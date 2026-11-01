import Foundation

/// Minimal GraphQL-over-HTTP client with bearer auth, shared by both providers.
public struct GraphQLClient: Sendable {
    public let endpoint: URL
    private let token: String
    private let session: URLSession

    public init(endpoint: URL, token: String, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.token = token
        self.session = session
    }

    private struct Envelope<T: Decodable>: Decodable {
        struct GQLError: Decodable { let message: String }
        let data: T?
        let errors: [GQLError]?
    }

    public func execute<T: Decodable & Sendable>(
        _ query: String,
        variables: [String: String?] = [:],
        as type: T.Type = T.self
    ) async throws -> T {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("ToReview (macOS)", forHTTPHeaderField: "User-Agent")

        var body: [String: Any] = ["query": query]
        if !variables.isEmpty {
            body["variables"] = variables.mapValues { value -> Any in value.map { $0 as Any } ?? NSNull() }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw ProviderError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("not an HTTP response")
        }
        switch http.statusCode {
        case 200...299: break
        case 401, 403:
            // GitHub signals secondary rate limits with 403 too.
            if http.value(forHTTPHeaderField: "X-RateLimit-Remaining") == "0" { throw ProviderError.rateLimited }
            throw ProviderError.unauthorized
        case 429: throw ProviderError.rateLimited
        default:
            throw ProviderError.http(status: http.statusCode, body: String(decoding: data.prefix(500), as: UTF8.self))
        }

        let envelope: Envelope<T>
        do {
            envelope = try Self.decoder.decode(Envelope<T>.self, from: data)
        } catch {
            throw ProviderError.invalidResponse(error.localizedDescription)
        }
        if let errors = envelope.errors, !errors.isEmpty, envelope.data == nil {
            let messages = errors.map(\.message)
            // GitLab answers 200 with an error for an invalid token.
            if messages.contains(where: { $0.localizedCaseInsensitiveContains("unauthorized") || $0.localizedCaseInsensitiveContains("invalid token") }) {
                throw ProviderError.unauthorized
            }
            throw ProviderError.graphQL(messages)
        }
        guard let payload = envelope.data else {
            throw ProviderError.invalidResponse("empty data")
        }
        return payload
    }

    /// GitHub emits `2024-01-01T00:00:00Z`; GitLab may include fractional seconds or `+00:00`.
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let string = try decoder.singleValueContainer().decode(String.self)
            if let date = Self.isoFractional.date(from: string) ?? Self.iso.date(from: string) { return date }
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(string)"))
        }
        return decoder
    }()

    nonisolated(unsafe) private static let iso: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    nonisolated(unsafe) private static let isoFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
