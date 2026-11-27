import Foundation
import WatchConnectivity
import WatchKit
import HealthKit
import CoreMotion

// ---------- סנכרון חי עם הטלפון ----------
// אותו אימון פעיל בטלפון ובשעון. כל סט נושא חותמת זמן t, והגרסה החדשה יותר מנצחת.
struct LSet: Codable { var kg: Double; var reps: Int; var done: Bool; var t: Double }
struct LEx: Codable { var id: String; var name: String; var rest: Int?; var sets: [LSet] }
struct Live: Codable {
    var id: String
    var name: String?
    var sk: Int?
    var startedAt: Double?
    var ex: [LEx]
    var rev: Int?
    var ended: Double?
    var how: String?
    var by: String?
    var src: String?
    var upd: Double?
    var hr: Int?
    var kcal: Int?
}
private struct LiveResp: Codable { var live: Live? }
private struct LivePut: Codable { var live: Live }

extension Api {
    static func liveGet() async throws -> Live? {
        let r: LiveResp = try await call("/api/watch/live")
        return r.live
    }
    @discardableResult
    static func livePut(_ l: Live) async throws -> Live? {
        let r: LiveResp = try await call("/api/watch/live", method: "POST", body: try JSONEncoder().encode(LivePut(live: l)))
        return r.live
    }
    static func liveEnd(id: String, saved: Bool) async {
        let b = try? JSONSerialization.data(withJSONObject: ["op": "end", "id": id, "how": saved ? "saved" : "cancel"])
        let _: LiveResp? = try? await call("/api/watch/live", method: "POST", body: b)
    }
    static func liveVitals(id: String, hr: Int, kcal: Int) async {
        let b = try? JSONSerialization.data(withJSONObject: ["op": "vitals", "id": id, "hr": hr, "kcal": kcal])
        let _: Ok? = try? await call("/api/watch/live", method: "POST", body: b)
    }
}

// ---------- התחברות אוטומטית: הטלפון שולח לשעון את החיבור לחשבון ----------
final class WatchSync: NSObject, WCSessionDelegate {
    static let shared = WatchSync()
    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        if s.delegate == nil { s.delegate = self }
        if s.activationState != .activated { s.activate() }
    }
    private func handle(_ d: [String: Any]) {
        guard let t = d["token"] as? String, !t.isEmpty else { return }
        let name = d["name"] as? String
        Task { @MainActor in AppState.shared.pairedFromPhone(token: t, name: name) }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        if activationState == .activated { handle(session.receivedApplicationContext) }
    }
    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) { handle(applicationContext) }
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) { handle(message) }
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) { handle(userInfo) }
}

// הטלפון יכול לפתוח את האפליקציה בשעון כשמתחילים אימון בטלפון
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() { WatchSync.shared.activate() }
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        Task { @MainActor in AppState.shared.phoneStartedWorkout() }
    }
}

// ---------- ספירת חזרות אוטומטית (ניסיוני) ----------
// מודד את התאוצה האנכית של היד בזמן הסט, מוצא את הקצב החוזר (אורך חזרה אחת) ומחשב כמה חזרות היו.
// עובד הכי טוב בתרגילים שבהם היד זזה למעלה ולמטה: כפיפות מרפקים, לחיצות, חתירות, סקוואט ודדליפט עם משקולות.
final class RepCounter: ObservableObject {
    @Published var reps = 0
    var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "set.watch.reps") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "set.watch.reps"); objectWillChange.send() }
    }
    private let mm = CMMotionManager()
    private let hz = 25.0
    private var buf: [Double] = []
    private var tick = 0

    var available: Bool { mm.isDeviceMotionAvailable }

    /// מתחיל לספור מאפס (בתחילת סט, כלומר אחרי המנוחה או אחרי שסומן הסט הקודם)
    func begin() {
        reps = 0; buf = []; tick = 0
        guard enabled, mm.isDeviceMotionAvailable else { return }
        if mm.isDeviceMotionActive { return }
        mm.deviceMotionUpdateInterval = 1.0 / hz
        mm.startDeviceMotionUpdates(to: .main) { [weak self] m, _ in
            guard let self, let m else { return }
            // תאוצה בכיוון הכבידה (למעלה/למטה), ביחידות g
            let g = m.gravity, a = m.userAcceleration
            let v = -(a.x * g.x + a.y * g.y + a.z * g.z)
            self.buf.append(v)
            if self.buf.count > Int(self.hz * 120) { self.buf.removeFirst(self.buf.count - Int(self.hz * 120)) }
            self.tick += 1
            if self.tick % Int(self.hz) == 0 { self.estimate() }
        }
    }
    func stop() {
        if mm.isDeviceMotionActive { mm.stopDeviceMotionUpdates() }
    }

    private func estimate() {
        let n = buf.count
        guard n >= Int(hz * 3) else { return }
        // חלון פעיל: מהדגימה הראשונה עד האחרונה שבהן יש תנועה ממשית
        let win = Int(hz / 2)
        var rms = [Double](repeating: 0, count: n)
        var acc = 0.0
        for i in 0..<n {
            acc += buf[i] * buf[i]
            if i >= win { acc -= buf[i - win] * buf[i - win] }
            rms[i] = (max(acc, 0) / Double(min(i + 1, win))).squareRoot()
        }
        guard let first = rms.firstIndex(where: { $0 > 0.06 }), let last = rms.lastIndex(where: { $0 > 0.06 }), last - first >= Int(hz * 2) else { return }
        let x = Array(buf[first...last])
        let mean = x.reduce(0, +) / Double(x.count)
        let y = x.map { $0 - mean }
        let e0 = y.reduce(0) { $0 + $1 * $1 }
        guard e0 > 0 else { return }
        // אוטוקורלציה: אורך חזרה בין 0.8 ל-6 שניות
        let lo = Int(hz * 0.8), hi = min(Int(hz * 6), y.count / 2)
        guard hi > lo else { return }
        var r = [Double](repeating: 0, count: hi + 1)
        var best = 0.0
        for lag in lo...hi {
            var s = 0.0
            for i in 0..<(y.count - lag) { s += y[i] * y[i + lag] }
            r[lag] = s / e0 * Double(y.count) / Double(y.count - lag)
            best = max(best, r[lag])
        }
        guard best > 0.25 else { return }
        // הקצב הכי קצר שעדיין חזק כמעט כמו הטוב ביותר, ושהוא שיא מקומי
        var period = 0
        for lag in (lo + 1)..<hi where r[lag] >= 0.85 * best && r[lag] >= r[lag - 1] && r[lag] >= r[lag + 1] { period = lag; break }
        if period == 0 { return }
        let count = Int((Double(x.count) / Double(period)).rounded())
        let c = max(0, min(50, count))
        if c != reps { reps = c }
    }
}
