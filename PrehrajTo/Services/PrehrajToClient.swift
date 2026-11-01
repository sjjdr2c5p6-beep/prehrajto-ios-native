import Foundation

enum PrehrajToError: LocalizedError {
    case invalidURL
    case networkError(String)
    case noStreamFound
    case loginFailed(String)
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Neplatná URL adresa."
        case .networkError(let reason):
            return "Chyba pripojenia: \(reason)"
        case .noStreamFound:
            return "Pre toto video sa nepodarilo nájsť priamy video stream."
        case .loginFailed(let message):
            return message
        case .premiumRequired:
            return "Táto funkcia vyžaduje aktívny Prehraj.to Premium účet."
        }
    }
}

/// Redirect-capturing delegate used to intercept the 302 Location header for `?do=download`
/// without downloading the multi-gigabyte video body during stream resolution.
private final class RedirectInterceptDelegate: NSObject, URLSessionTaskDelegate {
    var interceptedRedirectURL: URL?

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if let targetURL = request.url,
           targetURL.host?.contains("premiumcdn.net") == true || targetURL.pathExtension.isEmpty == false {
            interceptedRedirectURL = targetURL
            completionHandler(nil) // Stop redirect once we have the direct CDN link
        } else {
            completionHandler(request)
        }
    }
}

@MainActor
final class PrehrajToClient: ObservableObject {
    static let shared = PrehrajToClient()

    @Published var selectedDomain: String {
        didSet {
            UserDefaults.standard.set(selectedDomain, forKey: "prehrajto_domain")
        }
    }

    var baseURL: URL {
        URL(string: "https://\(selectedDomain)") ?? URL(string: "https://prehraj.to")!
    }

    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    init() {
        let savedDomain = UserDefaults.standard.string(forKey: "prehrajto_domain") ?? "prehraj.to"
        self.selectedDomain = savedDomain

        let config = URLSessionConfiguration.default
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.timeoutIntervalForRequest = 20
        config.httpAdditionalHeaders = [
            "User-Agent": Self.userAgent,
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "sk-SK,sk;q=0.9,cs-CZ;q=0.8,en-US;q=0.7"
        ]
        self.session = URLSession(configuration: config)
    }

    // MARK: - Search Videos (/hledej/<query>)

    func search(query: String, page: Int = 1) async throws -> [VideoItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return []
        }

        var urlString = "\(baseURL.absoluteString)/hledej/\(encoded)"
        if page > 1 {
            urlString += "?vp-page=\(page)"
        }
        guard let url = URL(string: urlString) else {
            throw PrehrajToError.invalidURL
        }

        var request = URLRequest(url: url)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        applyCustomCookies(to: &request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw PrehrajToError.networkError("Server vrátil neočakávanú odpoveď.")
        }

        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return HTMLParser.parseSearchResults(html: html, baseURL: baseURL)
    }

    // MARK: - Fetch Video Detail & Direct Native Stream URLs (/<slug>/<id>)

    func fetchVideoDetail(for item: VideoItem, isPremiumLoggedIn: Bool) async throws -> VideoDetail {
        let pageURL = baseURL.appendingPathComponent("\(item.videoSlug)/\(item.videoId)")
        var request = URLRequest(url: pageURL)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        applyCustomCookies(to: &request)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200...399).contains(httpResponse.statusCode) else {
            throw PrehrajToError.networkError("Nepodarilo sa načítať detail videa.")
        }

        let html = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)

        // If user has a Premium account, also resolve the uncompressed Original file URL (?do=download)
        var premiumOriginalURL: URL?
        if isPremiumLoggedIn {
            premiumOriginalURL = try? await resolvePremiumOriginalURL(for: item)
        }

        let detail = HTMLParser.parseVideoDetail(
            html: html,
            item: item,
            premiumOriginalURL: premiumOriginalURL
        )

        guard !detail.sources.isEmpty else {
            throw PrehrajToError.noStreamFound
        }

        return detail
    }

    // MARK: - Resolve Premium Original Stream (?do=download)

    func resolvePremiumOriginalURL(for item: VideoItem) async throws -> URL? {
        guard var components = URLComponents(
            url: baseURL.appendingPathComponent("\(item.videoSlug)/\(item.videoId)"),
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        components.queryItems = [URLQueryItem(name: "do", value: "download")]
        guard let downloadTriggerURL = components.url else { return nil }

        let delegate = RedirectInterceptDelegate()
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = true
        config.httpCookieStorage = HTTPCookieStorage.shared
        let redirectSession = URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        defer { redirectSession.finishTasksAndInvalidate() }

        var request = URLRequest(url: downloadTriggerURL)
        request.httpMethod = "GET"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(item.pageURL.absoluteString, forHTTPHeaderField: "Referer")
        applyCustomCookies(to: &request)

        _ = try? await redirectSession.data(for: request)
        return delegate.interceptedRedirectURL
    }

    // MARK: - Fetch & Parse WebVTT Subtitles

    func fetchSubtitleCues(from track: SubtitleTrack) async throws -> [SubtitleCue] {
        var request = URLRequest(url: track.url)
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        let (data, _) = try await session.data(for: request)
        let content = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        return VTTParser.parse(content: content)
    }

    // MARK: - Cookie Injection Helper

    func applyCustomCookies(to request: inout URLRequest) {
        var cookieParts: [String] = []
        if let cookies = HTTPCookieStorage.shared.cookies(for: baseURL) {
            for cookie in cookies {
                cookieParts.append("\(cookie.name)=\(cookie.value)")
            }
        }
        if let savedToken = KeychainHelper.read(forKey: "prehrajto_refresh_token"), !savedToken.isEmpty {
            if savedToken.contains("=") {
                cookieParts.append(savedToken)
            } else {
                cookieParts.append("refresh_token=\(savedToken)")
            }
        }
        if !cookieParts.isEmpty {
            request.setValue(cookieParts.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        }
    }
}
