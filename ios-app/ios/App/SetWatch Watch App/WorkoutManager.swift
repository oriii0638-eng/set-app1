import Foundation
import HealthKit

// אימון כוח פעיל ב-Apple Health: דופק וקלוריות בזמן אמת, ונשמר ב-Health בסיום.
// כל עוד האימון פעיל, השעון משאיר את האפליקציה פתוחה (גם כשמורידים את היד).
@MainActor
final class WorkoutManager: NSObject, ObservableObject {
    let store = HKHealthStore()
    private var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?

    @Published var heartRate: Double = 0
    @Published var calories: Double = 0
    @Published var running = false
    private var hrSum = 0.0, hrCount = 0
    var avgHeartRate: Double { hrCount > 0 ? hrSum / Double(hrCount) : 0 }

    func requestAuth() async {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        let share: Set<HKSampleType> = [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
        let read: Set<HKObjectType> = [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned), HKObjectType.workoutType()]
        try? await store.requestAuthorization(toShare: share, read: read)
    }

    func start() async {
        await requestAuth()
        let conf = HKWorkoutConfiguration()
        conf.activityType = .traditionalStrengthTraining
        conf.locationType = .indoor
        do {
            let s = try HKWorkoutSession(healthStore: store, configuration: conf)
            let b = s.associatedWorkoutBuilder()
            b.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: conf)
            s.delegate = self
            b.delegate = self
            session = s; builder = b
            heartRate = 0; calories = 0; hrSum = 0; hrCount = 0
            let now = Date()
            s.startActivity(with: now)
            try await b.beginCollection(at: now)
            running = true
        } catch {
            running = false // בלי הרשאה עדיין אפשר להתאמן, רק בלי דופק
        }
    }

    func end() async {
        guard let s = session, let b = builder else { return }
        s.end()
        do {
            try await b.endCollection(at: Date())
            _ = try await b.finishWorkout()
        } catch {}
        running = false
        session = nil; builder = nil
    }

    func discard() {
        session?.end()
        builder?.discardWorkout()
        running = false
        session = nil; builder = nil
    }

    fileprivate func update(hr: Double?, kcal: Double?) {
        if let hr, hr > 0 { heartRate = hr; hrSum += hr; hrCount += 1 }
        if let kcal { calories = kcal }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState, from fromState: HKWorkoutSessionState, date: Date) {}
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        var hr: Double? = nil, kcal: Double? = nil
        let hrType = HKQuantityType(.heartRate), kType = HKQuantityType(.activeEnergyBurned)
        if collectedTypes.contains(hrType), let st = workoutBuilder.statistics(for: hrType) {
            hr = st.mostRecentQuantity()?.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
        }
        if collectedTypes.contains(kType), let st = workoutBuilder.statistics(for: kType) {
            kcal = st.sumQuantity()?.doubleValue(for: .kilocalorie())
        }
        if hr == nil && kcal == nil { return }
        let h = hr, k = kcal
        Task { @MainActor in self.update(hr: h, kcal: k) }
    }
}
