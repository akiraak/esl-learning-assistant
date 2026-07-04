import Foundation
import os

enum BackendAPIError: LocalizedError {
    case invalidBaseURL
    /// 401: X-API-Secret の未設定・不一致
    case unauthorized
    case serverError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Invalid server URL. Check the Server URL in Settings."
        case .unauthorized:
            "Authentication failed (401). Check the API Secret in Settings."
        case .serverError(let statusCode, let message):
            if let message, !message.isEmpty {
                "Server error (HTTP \(statusCode)): \(message)"
            } else {
                "Server error (HTTP \(statusCode))."
            }
        }
    }
}

/// backend の /api/* 呼び出しの共通処理。
/// base URL と API Secret は Settings 画面の値（UserDefaults、未設定時はビルド埋め込みの既定値）を使う。
/// 通信の開始・結果は os.Logger（category: "BackendAPI"）に記録する。
/// Xcode コンソールのほか、実機は Console.app や `log stream --predicate 'category == "BackendAPI"'` で確認できる。
enum BackendAPI {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ESLLearningAssistant",
        category: "BackendAPI"
    )

    private static var baseURLString: String {
        UserDefaults.standard.string(forKey: AppSettingsKeys.backendBaseURL)
            ?? AppSettingsKeys.defaultBackendBaseURL
    }

    /// (secret値, ログ用の出所説明)。secret の値そのものはログに出さない
    private static var secretInfo: (value: String, source: String) {
        if let value = UserDefaults.standard.string(forKey: AppSettingsKeys.apiSecret) {
            return (value, value.isEmpty ? "Settings (EMPTY)" : "Settings (\(value.count) chars)")
        }
        let value = AppSettingsKeys.defaultAPISecret
        return (value, value.isEmpty ? "build default (EMPTY)" : "build default (\(value.count) chars)")
    }

    private static func makeRequest(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: baseURLString)?.appendingPathComponent(path) else {
            logger.error("\(method, privacy: .public) \(path, privacy: .public): invalid base URL \"\(baseURLString, privacy: .public)\"")
            throw BackendAPIError.invalidBaseURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let secret = secretInfo
        if !secret.value.isEmpty {
            request.setValue(secret.value, forHTTPHeaderField: "X-API-Secret")
        }
        logger.info("\(method, privacy: .public) \(url.absoluteString, privacy: .public) [API Secret: \(secret.source, privacy: .public)]")
        return request
    }

    /// JSONボディをPOSTし、200ならレスポンスボディを返す。失敗はステータス・ボディをログに残して throw する。
    /// timeout はサーバ側の処理が URLRequest 既定の60秒を超えうるAPI（画像生成など）で指定する。
    static func post(path: String, body: some Encodable, timeout: TimeInterval? = nil) async throws -> Data {
        var request = try makeRequest(path: path, method: "POST")
        if let timeout {
            request.timeoutInterval = timeout
        }
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await send(request, path: path)
    }

    private static func send(_ request: URLRequest, path: String) async throws -> Data {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            logger.error("\(path, privacy: .public): transport error: \(error.localizedDescription, privacy: .public)")
            throw error
        }

        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
        if statusCode == 200 {
            logger.info("\(path, privacy: .public): HTTP 200 (\(data.count) bytes)")
            return data
        }

        let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? "<non-UTF8 \(data.count) bytes>"
        logger.error("\(path, privacy: .public): HTTP \(statusCode) body=\(bodySnippet, privacy: .public)")
        if statusCode == 401 {
            throw BackendAPIError.unauthorized
        }
        throw BackendAPIError.serverError(statusCode: statusCode, message: serverErrorMessage(from: data))
    }

    /// backend のエラーレスポンス `{"error": "..."}` からメッセージを取り出す
    private static func serverErrorMessage(from data: Data) -> String? {
        struct ErrorBody: Decodable { let error: String }
        return (try? JSONDecoder().decode(ErrorBody.self, from: data))?.error
    }

    // MARK: - 接続テスト（SettingsView の Test Connection 用）

    struct ConnectionTestResult {
        var serverLine: String
        var secretLine: String
    }

    /// /health（無認証）でサーバ疎通、GET /api/ping（要認証）で API Secret の一致を確認する。
    static func testConnection() async -> ConnectionTestResult {
        var result = ConnectionTestResult(serverLine: "", secretLine: "")

        do {
            let request = try makeRequest(path: "health", method: "GET")
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            result.serverLine = statusCode == 200
                ? "Server: OK (\(baseURLString))"
                : "Server: NG — /health returned HTTP \(statusCode)"
        } catch {
            result.serverLine = "Server: NG — \(error.localizedDescription)"
            result.secretLine = "API Secret: not tested (server unreachable)"
            logger.error("testConnection: health failed: \(error.localizedDescription, privacy: .public)")
            return result
        }

        do {
            let request = try makeRequest(path: "api/ping", method: "GET")
            let (_, response) = try await URLSession.shared.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            switch statusCode {
            case 401:
                result.secretLine = "API Secret: NG (401) — the secret does not match this server"
            default:
                // 旧backendは /api/ping 未実装で404だが、401でなければ認証は通過している
                result.secretLine = "API Secret: OK"
            }
        } catch {
            result.secretLine = "API Secret: not tested — \(error.localizedDescription)"
        }
        logger.info("testConnection: \(result.serverLine, privacy: .public) / \(result.secretLine, privacy: .public)")
        return result
    }
}
