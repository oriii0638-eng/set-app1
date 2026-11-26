import Foundation
import Capacitor
import HealthKit
import WidgetKit
import ActivityKit

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
        CAPPluginMethod(name: "widgetSet", returnType: CAPPluginReturnPromise)
    ]
    static let appGroup = "group.com.setapp.workout"
    private let store = HKHealthStore()

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
                    content: ActivityContent(state: st, staleDate: nil),
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
                await a.update(ActivityContent(state: st, staleDate: nil))
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
