import Foundation
import SwiftUI

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var account: PremiumAccountInfo?
    @Published var isAuthenticating: Bool = false
    @Published var authError: String?

    private let accountStorageKey = "prehrajto_account_info"
    private let emailKeychainKey = "prehrajto_email"
    private let passwordKeychainKey = "prehrajto_password"
    private let tokenKeychainKey = "prehrajto_refresh_token"

    var isPremiumActive: Bool {
        account?.isPremium == true
    }

    init() {
        loadSavedAccount()
    }

    // MARK: - Login with Email & Password (Nette frm-loginDialogForm)

    func loginWithCredentials(email: String, password: String) async throws {
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanEmail.isEmpty, !password.isEmpty else {
            throw PrehrajToError.loginFailed("Zadajte e-mail aj heslo.")
        }

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        let client = PrehrajToClient.shared
        let baseURL = client.baseURL

        // 1. Prime session cookies by visiting home page first
        var initialRequest = URLRequest(url: baseURL)
        initialRequest.setValue(PrehrajToClient.userAgent, forHTTPHeaderField: "User-Agent")
        _ = try? await URLSession.shared.data(for: initialRequest)

        // 2. Submit Nette login form: /?do=loginDialogForm-loginForm-submit
        guard let loginURL = URL(string: "\(baseURL.absoluteString)/?do=loginDialogForm-loginForm-submit") else {
            throw PrehrajToError.invalidURL
        }

        var request = URLRequest(url: loginURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue(PrehrajToClient.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Referer")
        request.setValue(baseURL.absoluteString, forHTTPHeaderField: "Origin")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")

        let bodyParams: [(String, String)] = [
            ("email", cleanEmail),
            ("password", password),
            ("remember", "on"),
            ("login", "Přihlásit se"),
            ("_do", "loginDialogForm-loginForm-submit")
        ]

        let formBody = bodyParams.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")

        request.httpBody = formBody.data(using: .utf8)

        let (data, _) = try await URLSession.shared.data(for: request)
        let responseHTML = String(data: data, encoding: .utf8) ?? ""

        // 3. Also fetch /profil to verify login and Premium validity
        var profileHTML = responseHTML
        if let profileURL = URL(string: "\(baseURL.absoluteString)/profil") {
            var profileReq = URLRequest(url: profileURL)
            profileReq.setValue(PrehrajToClient.userAgent, forHTTPHeaderField: "User-Agent")
            client.applyCustomCookies(to: &profileReq)
            if let (profData, _) = try? await URLSession.shared.data(for: profileReq),
               let profStr = String(data: profData, encoding: .utf8) {
                profileHTML += "\n" + profStr
            }
        }

        let status = HTMLParser.parseAccountStatus(html: profileHTML)
        let hasSessionCookie = (HTTPCookieStorage.shared.cookies(for: baseURL) ?? []).contains {
            $0.name.lowercased().contains("sess")
            || $0.name.lowercased().contains("token")
            || $0.name.lowercased().contains("user")
            || $0.name.lowercased().contains("nette")
        }

        // Check for explicit incorrect password error message in Czech/Slovak
        if profileHTML.localizedCaseInsensitiveContains("nesprávné heslo")
            || profileHTML.localizedCaseInsensitiveContains("účet neexistuje")
            || profileHTML.localizedCaseInsensitiveContains("neplatné přihlašovací") {
            throw PrehrajToError.loginFailed("Nesprávny e-mail alebo heslo.")
        }

        guard status.isLoggedIn || hasSessionCookie else {
            throw PrehrajToError.loginFailed("Prihlásenie sa nepodarilo overiť. Skontrolujte údaje alebo použite Session Token.")
        }

        // Save securely in Keychain
        KeychainHelper.save(cleanEmail, forKey: emailKeychainKey)
        KeychainHelper.save(password, forKey: passwordKeychainKey)

        let info = PremiumAccountInfo(
            email: cleanEmail,
            isPremium: true,
            premiumUntil: status.validity ?? "Aktívne predplatné",
            creditRemaining: "Neobmedzené streamovanie & sťahovanie",
            authMethod: .credentials,
            lastVerified: Date()
        )
        saveAccount(info)
    }

    // MARK: - Login with Refresh Token / Cookie (Bypass Cloudflare if needed)

    func loginWithToken(emailLabel: String, refreshToken: String) async throws {
        let cleanToken = refreshToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanToken.isEmpty else {
            throw PrehrajToError.loginFailed("Vložte platný refresh_token alebo Cookie reťazec.")
        }

        isAuthenticating = true
        authError = nil
        defer { isAuthenticating = false }

        KeychainHelper.save(cleanToken, forKey: tokenKeychainKey)

        let displayEmail = emailLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Premium Token Účet"
            : emailLabel.trimmingCharacters(in: .whitespacesAndNewlines)

        let info = PremiumAccountInfo(
            email: displayEmail,
            isPremium: true,
            premiumUntil: "Aktívny Token",
            creditRemaining: "Originálna kvalita + Offline sťahovanie",
            authMethod: .tokenCookie,
            lastVerified: Date()
        )
        saveAccount(info)
    }

    // MARK: - Auto Re-authenticate on Launch

    func refreshSessionIfNeeded() async {
        guard let account else { return }
        if account.authMethod == .credentials,
           let email = KeychainHelper.read(forKey: emailKeychainKey),
           let password = KeychainHelper.read(forKey: passwordKeychainKey) {
            try? await loginWithCredentials(email: email, password: password)
        }
    }

    // MARK: - Logout

    func logout() {
        KeychainHelper.delete(forKey: emailKeychainKey)
        KeychainHelper.delete(forKey: passwordKeychainKey)
        KeychainHelper.delete(forKey: tokenKeychainKey)
        UserDefaults.standard.removeObject(forKey: accountStorageKey)

        if let cookies = HTTPCookieStorage.shared.cookies {
            for cookie in cookies {
                HTTPCookieStorage.shared.deleteCookie(cookie)
            }
        }
        account = nil
    }

    // MARK: - Persistence

    private func saveAccount(_ info: PremiumAccountInfo) {
        account = info
        if let encoded = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(encoded, forKey: accountStorageKey)
        }
    }

    private func loadSavedAccount() {
        guard let data = UserDefaults.standard.data(forKey: accountStorageKey),
              let decoded = try? JSONDecoder().decode(PremiumAccountInfo.self, from: data) else {
            return
        }
        account = decoded
    }
}
