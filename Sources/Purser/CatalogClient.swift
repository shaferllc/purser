import Foundation

enum ClientError: LocalizedError {
    case badURL
    case http(Int, String?)
    case notSignedIn
    case membershipRequired(String)

    var errorDescription: String? {
        switch self {
        case .badURL:
            "That server address isn't a valid URL."
        case let .http(status, message):
            message ?? "The server replied with HTTP \(status)."
        case .notSignedIn:
            "Sign in to your Chandlery account first."
        case let .membershipRequired(message):
            message
        }
    }
}

/// Talks to Chandlery. Stateless apart from the base URL and the device token,
/// so it's safe to hand around.
struct CatalogClient: Sendable {
    var baseURL: URL
    var token: String?

    private var session: URLSession { .shared }

    // MARK: - Catalog

    func catalog() async throws -> Catalog {
        let request = try authorized(URLRequest(url: endpoint("catalog", query: [URLQueryItem(name: "platform", value: "mac")])))
        let (data, response) = try await session.data(for: request)

        try check(response, data)

        return try JSONDecoder().decode(Catalog.self, from: data)
    }

    // MARK: - Account

    func signIn(email: String, password: String, deviceName: String) async throws -> (token: String, account: Account) {
        var request = URLRequest(url: endpoint("sessions"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "device_name": deviceName,
        ])

        let (data, response) = try await session.data(for: request)

        try check(response, data)

        struct Payload: Decodable {
            let token: String
            let account: Account
        }

        let payload = try JSONDecoder().decode(Payload.self, from: data)

        return (payload.token, payload.account)
    }

    func account() async throws -> Account {
        guard token != nil else { throw ClientError.notSignedIn }

        let request = try authorized(URLRequest(url: endpoint("account")))
        let (data, response) = try await session.data(for: request)

        try check(response, data)

        struct Payload: Decodable { let account: Account }

        return try JSONDecoder().decode(Payload.self, from: data).account
    }

    func signOut() async throws {
        guard token != nil else { return }

        var request = try authorized(URLRequest(url: endpoint("sessions")))
        request.httpMethod = "DELETE"

        _ = try? await session.data(for: request)
    }

    // MARK: - Downloads

    /// Resolve the gated download endpoint to the artifact's real URL.
    ///
    /// The redirect is followed by hand rather than by URLSession so the
    /// account's bearer token is never forwarded to whoever hosts the artifact.
    func resolveDownload(for app: CatalogApp) async throws -> URL {
        guard let release = app.latestRelease else { throw ClientError.badURL }
        guard let url = URL(string: release.downloadURL) else { throw ClientError.badURL }

        var request = try authorized(URLRequest(url: url))
        request.httpMethod = "GET"

        let session = URLSession(configuration: .ephemeral, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else { throw ClientError.badURL }

        if (300 ... 399).contains(http.statusCode),
           let location = http.value(forHTTPHeaderField: "Location"),
           let resolved = URL(string: location, relativeTo: url)
        {
            return resolved.absoluteURL
        }

        // No redirect means the server said no — surface why.
        if http.statusCode == 401 { throw ClientError.notSignedIn }
        if http.statusCode == 403 { throw ClientError.membershipRequired(message(from: data) ?? "Your membership has lapsed.") }

        try check(response, data)

        // A 200 here would mean the artifact is served inline; use the URL as-is.
        return url
    }

    // MARK: - Plumbing

    private func endpoint(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("api/v1/\(path)"),
            resolvingAgainstBaseURL: false
        )!

        if !query.isEmpty { components.queryItems = query }

        return components.url!
    }

    private func authorized(_ request: URLRequest) throws -> URLRequest {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 30

        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    private func check(_ response: URLResponse, _ data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard !(200 ... 299).contains(http.statusCode) else { return }

        switch http.statusCode {
        case 401: throw ClientError.notSignedIn
        case 403: throw ClientError.membershipRequired(message(from: data) ?? "Your membership has lapsed.")
        default: throw ClientError.http(http.statusCode, message(from: data))
        }
    }

    private func message(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }

        if let message = object["message"] as? String { return message }

        // Laravel validation errors: { errors: { email: ["…"] } }
        if let errors = object["errors"] as? [String: Any],
           let first = errors.values.compactMap({ ($0 as? [String])?.first }).first
        {
            return first
        }

        return nil
    }
}

/// Stops URLSession following the redirect out of Chandlery, so credentials
/// stay on our own host.
private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest _: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
