import Foundation

// חיבור לשרת של סט. השעון מזדהה בטוקן שמתקבל בצימוד עם הטלפון.
struct WSet: Codable, Hashable { var kg: Double; var reps: Int }
struct WEx: Codable, Hashable { var name: String; var rest: Int?; var sets: [WSet] }
struct WPlan: Codable {
    var name: String?; var d: Int?; var sk: Int?; var when: String?
    var ex: [WEx]?; var none: Bool?; var msg: String?; var user: String?
}
struct PairStart: Codable { var pid: String; var code: String }
struct PairStatus: Codable { var ok: Bool; var token: String?; var name: String? }

struct ApiError: LocalizedError { let message: String; var errorDescription: String? { message } }

enum Api {
    static let base = "https://set-app-e0r6.onrender.com"

    static var token: String? {
        get { UserDefaults.standard.string(forKey: "set.watch.token") }
        set { UserDefaults.standard.set(newValue, forKey: "set.watch.token") }
    }
    static var userName: String? {
        get { UserDefaults.standard.string(forKey: "set.watch.user") }
        set { UserDefaults.standard.set(newValue, forKey: "set.watch.user") }
    }

    static func call<T: Decodable>(_ path: String, method: String = "GET", body: Data? = nil) async throws -> T {
        guard let url = URL(string: base + path) else { throw ApiError(message: "כתובת שגויה") }
        var r = URLRequest(url: url, timeoutInterval: 25)
        r.httpMethod = method
        r.setValue("SetWatch/1", forHTTPHeaderField: "User-Agent")
        if let t = token { r.setValue("Bearer " + t, forHTTPHeaderField: "Authorization") }
        if let b = body {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = b
        }
        let data: Data, resp: URLResponse
        do { (data, resp) = try await URLSession.shared.data(for: r) }
        catch { throw ApiError(message: "אין חיבור לאינטרנט. ודא שהטלפון קרוב או שיש Wi-Fi") }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if code == 401 && token != nil { token = nil; throw ApiError(message: "השעון נותק מהחשבון. צריך לחבר שוב") }
        if code >= 400 {
            let j = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            throw ApiError(message: (j?["error"] as? String) ?? "שגיאה בחיבור לשרת")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    static func pairStart() async throws -> PairStart { try await call("/api/watch/pair/start", method: "POST", body: Data("{}".utf8)) }
    static func pairStatus(_ pid: String) async throws -> PairStatus { try await call("/api/watch/pair/status?pid=" + pid) }
    static func today() async throws -> WPlan { try await call("/api/watch/today") }

    struct Ok: Codable { var ok: Bool? }
    static func finish(_ p: FinishPayload) async throws {
        let _: Ok = try await call("/api/watch/finish", method: "POST", body: try JSONEncoder().encode(p))
    }
}

// אימון שהסתיים בשעון. אם אין חיבור, נשמר בשעון ונשלח בפעם הבאה.
struct FinishPayload: Codable {
    var name: String; var sk: Int?; var start: Int; var dur: Int
    var kcal: Int; var hr: Int; var ex: [WEx]
}
