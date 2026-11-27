import Foundation
import UIKit
import Capacitor
import HealthKit
import WidgetKit
import ActivityKit
import WatchConnectivity

// יכולות native של סט: שמירת אימון ב-Apple Health, אימון פעיל במסך הנעילה, ונתונים לווידג'ט
@objc(SetNativePlugin)
public class SetNativePlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SetNativePlugin"
    public let jsName = "SetNative"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "saveWorkout", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "liveStart", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "liveUpdate", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "liveEnd", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "widgetSet", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "watchInfo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "watchPair", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "startWatchWorkout", returnType: CAPPluginReturnPromise)
    ]
    static let appGroup = "group.com.setapp.workout"
    private let store = HKHealthStore()

    // סגירת האפליקציה מהמסך של האפליקציות הפתוחות: מורידים את האימון ממסך הנעילה
    override public func load() {
        NotificationCenter.default.addObserver(self, selector: #selector(appWillTerminate), name: UIApplication.willTerminateNotification, object: nil)
        WatchLink.shared.activate()
    }

    // ---------- Apple Watch ----------
    // האם יש שעון מצומד ואפליקציית סט מותקנת בו
    @objc func watchInfo(_ call: CAPPluginCall) {
        guard WCSession.isSupported() else { call.resolve(["supported": false, "paired": false, "installed": false]); return }
        WatchLink.shared.whenActive { s in
            call.resolve(["supported": true, "paired": s.isPaired, "installed": s.isWatchAppInstalled])
        }
    }
    // שולח לשעון את החיבור לחשבון (טוקן מהשרת), כדי שלא יצטרכו להקליד קוד
    @objc func watchPair(_ call: CAPPluginCall) {
        guard let token = call.getString("token"), !token.isEmpty else { call.reject("token"); return }
        let name = call.getString("name") ?? ""
        guard WCSession.isSupported() else { call.reject("no watch"); return }
        WatchLink.shared.whenActive { s in
            guard s.isPaired, s.isWatchAppInstalled else { call.reject("watch app not installed"); return }
            let msg: [String: Any] = ["token": token, "name": name, "at": Date().timeIntervalSince1970]
            do { try s.updateApplicationContext(msg) } catch { call.reject(error.localizedDescription); return }
            // אם השעון פתוח עכשיו, מגיע מיד. אחרת הוא יקבל את זה בפעם הבאה שיפתח
            if s.isReachable { s.sendMessage(msg, replyHandler: nil, errorHandler: nil) }
            else { s.transferUserInfo(msg) }
            call.resolve(["sent": true])
        }
    }
    // פותח את אפליקציית סט בשעון עם אימון כוח, כשמתחילים אימון בטלפון
    @objc func startWatchWorkout(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable(), WCSession.isSupported() else { call.resolve(["started": false]); return }
        let conf = HKWorkoutConfiguration()
        conf.activityType = .traditionalStrengthTraining
        conf.locationType = .indoor
        store.startWatchApp(with: conf) { ok, _ in call.resolve(["started": ok]) }
    }
    @objc func appWillTerminate() {
        guard #available(iOS 16.2, *) else { return }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            for a in Activity<SetActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            done.signal()
        }
        _ = done.wait(timeout: .now() + 2)
    }

    // ---------- Apple Health ----------
    @objc func saveWorkout(_ call: CAPPluginCall) {
        guard HKHealthStore.isHealthDataAvailable() else { call.resolve(["saved": false]); return }
        let start = Date(timeIntervalSince1970: (call.getDouble("start") ?? 0) / 1000)
        let end = Date(timeIntervalSince1970: (call.getDouble("end") ?? 0) / 1000)
        guard end > start else { call.reject("bad dates"); return }
        let name = call.getString("name") ?? "אימון"
        let share: Set<HKSampleType> = [HKObjectType.workoutType()]
        store.requestAuthorization(toShare: share, read: nil) { ok, _ in
            guard ok else { call.resolve(["saved": false]); return }
            let conf = HKWorkoutConfiguration()
            conf.activityType = .traditionalStrengthTraining
            conf.locationType = .indoor
            let builder = HKWorkoutBuilder(healthStore: self.store, configuration: conf, device: .local())
            builder.beginCollection(withStart: start) { ok1, err1 in
                guard ok1 else { call.reject(err1?.localizedDescription ?? "begin"); return }
                builder.addMetadata([HKMetadataKeyWorkoutBrandName: "סט", "SetWorkoutName": name]) { _, _ in
                    builder.endCollection(withEnd: end) { ok2, err2 in
                        guard ok2 else { call.reject(err2?.localizedDescription ?? "end"); return }
                        builder.finishWorkout { workout, err3 in
                            if workout != nil { call.resolve(["saved": true]) } else { call.reject(err3?.localizedDescription ?? "finish") }
                        }
                    }
                }
            }
        }
    }

    // ---------- מסך נעילה ו-Dynamic Island ----------
    @available(iOS 16.2, *)
    private func state(_ o: JSObject) -> SetActivityAttributes.ContentState {
        func s(_ k: String) -> String { (o[k] as? String) ?? "" }
        return SetActivityAttributes.ContentState(
            name: s("name"), ex: s("ex"), set: s("set"), load: s("load"), mode: s("mode"),
            restEnd: Double(s("restEnd")) ?? 0, start: Double(s("start")) ?? Date().timeIntervalSince1970, done: s("done"))
    }

    @objc func liveStart(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(["started": false]); return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { call.resolve(["started": false]); return }
        let id = call.getString("id") ?? "w"
        let st = state(call.getObject("content") ?? [:])
        Task {
            for a in Activity<SetActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            do {
                _ = try Activity<SetActivityAttributes>.request(
                    attributes: SetActivityAttributes(id: id),
                    content: ActivityContent(state: st, staleDate: Date().addingTimeInterval(4 * 3600)),
                    pushType: nil)
                call.resolve(["started": true])
            } catch {
                call.reject(error.localizedDescription)
            }
        }
    }

    @objc func liveUpdate(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        let id = call.getString("id") ?? ""
        let st = state(call.getObject("content") ?? [:])
        Task {
            for a in Activity<SetActivityAttributes>.activities where a.attributes.id == id {
                await a.update(ActivityContent(state: st, staleDate: Date().addingTimeInterval(4 * 3600)))
            }
            call.resolve()
        }
    }

    @objc func liveEnd(_ call: CAPPluginCall) {
        guard #available(iOS 16.2, *) else { call.resolve(); return }
        Task {
            for a in Activity<SetActivityAttributes>.activities { await a.end(nil, dismissalPolicy: .immediate) }
            call.resolve()
        }
    }

    // ---------- ווידג'ט ----------
    @objc func widgetSet(_ call: CAPPluginCall) {
        let json = call.getString("json") ?? "{}"
        UserDefaults(suiteName: SetNativePlugin.appGroup)?.set(json, forKey: "today")
        WidgetCenter.shared.reloadAllTimelines()
        call.resolve()
    }
}


// חיבור WatchConnectivity לשעון. נדלק כשהאפליקציה עולה
final class WatchLink: NSObject, WCSessionDelegate {
    static let shared = WatchLink()
    private var waiting: [(WCSession) -> Void] = []
    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        if s.delegate == nil { s.delegate = self }
        if s.activationState != .activated { s.activate() }
    }
    func whenActive(_ f: @escaping (WCSession) -> Void) {
        activate()
        let s = WCSession.default
        if s.activationState == .activated { DispatchQueue.main.async { f(s) } }
        else { DispatchQueue.main.async { self.waiting.append(f) } }
    }
    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        DispatchQueue.main.async { let w = self.waiting; self.waiting = []; w.forEach { $0(session) } }
    }
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { WCSession.default.activate() }
}
