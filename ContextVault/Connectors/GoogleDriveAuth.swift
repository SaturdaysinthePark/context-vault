import Foundation
import AuthenticationServices
import CryptoKit

/// OAuth 2.0 + PKCE for Google Drive, using ASWebAuthenticationSession —
/// no SDK dependency. Requires an iOS OAuth Client ID from a Google Cloud
/// project (see docs/CONNECTORS.md); the redirect URI is the reversed
/// client ID, which iOS routes back to the auth session automatically.
///
/// Scope note: `drive.readonly` is a restricted scope for *published* apps
/// (CASA audit), but works immediately for the project owner's account
/// while the OAuth consent screen is in Testing mode — the right tradeoff
/// for development. Revisit before any App Store release.
struct GoogleTokens: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date

    var isExpired: Bool { Date.now >= expiresAt.addingTimeInterval(-60) }
}

@MainActor
final class GoogleDriveAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let scope = "https://www.googleapis.com/auth/drive.readonly"

    enum AuthError: LocalizedError {
        case invalidClientID
        case cancelled
        case tokenExchangeFailed
        case noRefreshToken

        var errorDescription: String? {
            switch self {
            case .invalidClientID: "That doesn't look like an iOS OAuth Client ID."
            case .cancelled: "Sign-in was cancelled."
            case .tokenExchangeFailed: "Google sign-in failed while exchanging tokens."
            case .noRefreshToken: "Google session expired — sign in again."
            }
        }
    }

    /// Runs the interactive sign-in and returns tokens.
    func signIn(clientID: String) async throws -> GoogleTokens {
        // Client IDs look like NNN-xxxx.apps.googleusercontent.com; the
        // redirect scheme is the same string reversed around the dots.
        guard clientID.hasSuffix(".apps.googleusercontent.com") else {
            throw AuthError.invalidClientID
        }
        let scheme = "com.googleusercontent.apps." + clientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        let redirectURI = "\(scheme):/oauth2redirect"

        let verifier = Self.randomURLSafeString(length: 64)
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: scheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else if let error = error as? ASWebAuthenticationSessionError,
                          error.code == .canceledLogin {
                    continuation.resume(throwing: AuthError.cancelled)
                } else {
                    continuation.resume(throwing: error ?? AuthError.tokenExchangeFailed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw AuthError.tokenExchangeFailed
        }

        return try await Self.exchange(code: code, verifier: verifier, clientID: clientID, redirectURI: redirectURI)
    }

    // MARK: Token endpoint

    private static func exchange(code: String, verifier: String, clientID: String, redirectURI: String) async throws -> GoogleTokens {
        let body = [
            "client_id": clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI,
        ]
        return try await tokenRequest(body: body, existingRefreshToken: nil)
    }

    static func refresh(tokens: GoogleTokens, clientID: String) async throws -> GoogleTokens {
        guard let refreshToken = tokens.refreshToken else {
            throw AuthError.noRefreshToken
        }
        let body = [
            "client_id": clientID,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token",
        ]
        return try await tokenRequest(body: body, existingRefreshToken: refreshToken)
    }

    private static func tokenRequest(body: [String: String], existingRefreshToken: String?) async throws -> GoogleTokens {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw AuthError.tokenExchangeFailed
        }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double
        }
        let decoded = try JSONDecoder().decode(TokenResponse.self, from: data)
        return GoogleTokens(
            accessToken: decoded.access_token,
            refreshToken: decoded.refresh_token ?? existingRefreshToken,
            expiresAt: Date.now.addingTimeInterval(decoded.expires_in)
        )
    }

    // MARK: PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        let charset = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: ASWebAuthenticationPresentationContextProviding

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        ASPresentationAnchor()
    }
}
