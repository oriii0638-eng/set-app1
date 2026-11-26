import Foundation
import WatchKit

// מצב האפליקציה בשעון: צימוד, אימון היום, אימון פעיל וטיימר מנוחה.
@MainActor
final class AppState: ObservableObject {
    @Published var paired = Api.token != nil
    @Published var plan: WPlan?
    @Published var loading = false
    @Published var error: String?

    // אימון פעיל
    @Published var ex: [WEx] = []
    @Published var done: [[Bool]] = []
    @Published var idx = 0
    @Published var started: Date?
    @Published var restEnd: Date?
    @Published var restTotal: Double = 90
    @Published var summary: Summary?

    let workout = WorkoutManager()
    private var restTask: Task<Void, Never>?

    struct Summary { var sets: Int; var volume: Int; var minutes: Int; var kcal: Int; var hr: Int; var saved: Bool }

    init() { restore() }

    // ---------- צימוד ----------
    func didPair(token: String, name: String?) {
        Api.token = token; Api.userName = name
        paired = true
        Task { await loadToday() }
    }
    func unpair() { Api.token = nil; paired = false; plan = nil }

    // ---------- אימון היום ----------
    func loadToday() async {
        loading = true; error = nil
        await flushPending()
        do { plan = try await Api.today() }
        catch {
            self.error = error.localizedDescription
            if Api.token == nil { paired = false }
        }
        loading = false
    }

    // ---------- אימון ----------
    var current: WEx? { ex.indices.contains(idx) ? ex[idx] : nil }
    var doneSets: Int { done.reduce(0) { $0 + $1.filter { $0 }.count } }
    var totalSets: Int { done.reduce(0) { $0 + $1.count } }

    func start() {
        guard let p = plan, let list = p.ex, !list.isEmpty else { return }
        ex = list
        done = list.map { Array(repeating: false, count: $0.sets.count) }
        idx = 0; started = Date(); summary = nil
        save()
        Task { await workout.start() }
        WKInterfaceDevice.current().play(.start)
    }

    /// הסט הבא שלא בוצע בתרגיל הנוכחי
    func isDone(_ j: Int) -> Bool { done.indices.contains(idx) && done[idx].indices.contains(j) && done[idx][j] }
    var nextSet: Int? { done.indices.contains(idx) ? done[idx].firstIndex(of: false) : nil }

    func update(set j: Int, kg: Double, reps: Int) {
        guard ex.indices.contains(idx), ex[idx].sets.indices.contains(j) else { return }
        ex[idx].sets[j].kg = max(0, kg); ex[idx].sets[j].reps = max(0, reps)
        // שינוי משקל עובר גם לסטים הבאים שעוד לא בוצעו
        for k in (j + 1)..<ex[idx].sets.count where !done[idx][k] { ex[idx].sets[k].kg = ex[idx].sets[j].kg }
        save()
    }

    func markDone(_ j: Int) {
        guard done.indices.contains(idx), done[idx].indices.contains(j) else { return }
        done[idx][j] = true
        save()
        WKInterfaceDevice.current().play(.success)
        let allDone = !done[idx].contains(false)
        if allDone && idx + 1 >= ex.count { return } // סט אחרון באימון: אין מנוחה
        startRest(Double(ex[idx].rest ?? 90))
        if allDone { idx += 1 }
    }
    func unmark(_ j: Int) {
        guard done.indices.contains(idx), done[idx].indices.contains(j) else { return }
        done[idx][j] = false; save()
    }

    func addSet() {
        guard ex.indices.contains(idx) else { return }
        let last = ex[idx].sets.last ?? WSet(kg: 0, reps: 10)
        ex[idx].sets.append(last); done[idx].append(false); save()
    }

    // ---------- טיימר מנוחה עם רטט ----------
    func startRest(_ sec: Double) {
        let s = max(10, sec)
        restTotal = s
        restEnd = Date().addingTimeInterval(s)
        scheduleRestHaptics()
    }
    func addRest(_ sec: Double) {
        guard let e = restEnd else { return }
        restEnd = e.addingTimeInterval(sec); restTotal += sec
        scheduleRestHaptics()
    }
    func skipRest() { restTask?.cancel(); restEnd = nil }

    private func scheduleRestHaptics() {
        restTask?.cancel()
        guard let end = restEnd else { return }
        restTask = Task { @MainActor in
            let dev = WKInterfaceDevice.current()
            // 3, 2, 1 ואז רטט חזק
            for mark in [3.0, 2.0, 1.0] {
                let wait = end.timeIntervalSinceNow - mark
                if wait > 0 { try? await Task.sleep(nanoseconds: UInt64(wait * 1e9)) }
                if Task.isCancelled { return }
                if end.timeIntervalSinceNow > mark - 0.9 { dev.play(.click) }
            }
            let rest = end.timeIntervalSinceNow
            if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1e9)) }
            if Task.isCancelled { return }
            dev.play(.notification)
            try? await Task.sleep(nanoseconds: 700_000_000)
            if Task.isCancelled { return }
            dev.play(.notification)
            restEnd = nil
            // תזכורת אם לא התחלת את הסט הבא אחרי 30 שניות
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            if Task.isCancelled { return }
            dev.play(.directionUp)
        }
    }

    // ---------- סיום ----------
    func finish() async {
        skipRest()
        let start = started ?? Date()
        let dur = Int(Date().timeIntervalSince(start))
        await workout.end()
        var out: [WEx] = []
        var sets = 0, vol = 0.0
        for (i, e) in ex.enumerated() {
            let ds = e.sets.enumerated().filter { done[i][$0.offset] }.map { $0.element }
            if ds.isEmpty { continue }
            sets += ds.count; vol += ds.reduce(0) { $0 + $1.kg * Double($1.reps) }
            out.append(WEx(name: e.name, rest: nil, sets: ds))
        }
        let kcal = workout.calories, hr = workout.avgHeartRate
        var saved = false
        if !out.isEmpty {
            let p = FinishPayload(name: plan?.name ?? "אימון", sk: plan?.sk, start: Int(start.timeIntervalSince1970 * 1000), dur: dur, kcal: Int(kcal.rounded()), hr: Int(hr.rounded()), ex: out)
            do { try await Api.finish(p); saved = true } catch { addPending(p) }
        }
        summary = Summary(sets: sets, volume: Int(vol.rounded()), minutes: max(1, dur / 60), kcal: Int(kcal.rounded()), hr: Int(hr.rounded()), saved: saved || out.isEmpty)
        WKInterfaceDevice.current().play(.success)
        clearActive()
    }

    func cancelWorkout() {
        skipRest(); workout.discard(); clearActive()
    }

    func closeSummary() {
        summary = nil
        Task { await loadToday() }
    }

    // ---------- שמירה מקומית (אם האפליקציה נסגרת באמצע) ----------
    private struct Active: Codable { var plan: WPlan?; var ex: [WEx]; var done: [[Bool]]; var idx: Int; var started: Date }
    private let activeKey = "set.watch.active", pendingKey = "set.watch.pending"

    private func save() {
        guard let s = started else { return }
        let a = Active(plan: plan, ex: ex, done: done, idx: idx, started: s)
        UserDefaults.standard.set(try? JSONEncoder().encode(a), forKey: activeKey)
    }
    private func restore() {
        guard let d = UserDefaults.standard.data(forKey: activeKey), let a = try? JSONDecoder().decode(Active.self, from: d) else { return }
        if Date().timeIntervalSince(a.started) > 4 * 3600 { UserDefaults.standard.removeObject(forKey: activeKey); return }
        plan = a.plan; ex = a.ex; done = a.done; idx = a.idx; started = a.started
        Task { await workout.start() } // ממשיך למדוד דופק אחרי שהאפליקציה נפתחה מחדש
    }
    private func clearActive() {
        started = nil; ex = []; done = []; idx = 0
        UserDefaults.standard.removeObject(forKey: activeKey)
    }

    private func addPending(_ p: FinishPayload) {
        var list = pending(); list.append(p)
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(list.suffix(10))), forKey: pendingKey)
    }
    private func pending() -> [FinishPayload] {
        guard let d = UserDefaults.standard.data(forKey: pendingKey) else { return [] }
        return (try? JSONDecoder().decode([FinishPayload].self, from: d)) ?? []
    }
    private func flushPending() async {
        var left: [FinishPayload] = []
        for p in pending() { do { try await Api.finish(p) } catch { left.append(p) } }
        if left.isEmpty { UserDefaults.standard.removeObject(forKey: pendingKey) }
        else { UserDefaults.standard.set(try? JSONEncoder().encode(left), forKey: pendingKey) }
    }
}
