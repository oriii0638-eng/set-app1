import Foundation
import WatchKit

// מצב האפליקציה בשעון: צימוד, אימון היום, אימון פעיל וטיימר מנוחה.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()
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
    let counter = RepCounter()
    private var restTask: Task<Void, Never>?

    // סנכרון חי עם הטלפון
    @Published var liveId: String?
    @Published var phoneNote: String?      // הודעה קצרה כמו "סומן בטלפון"
    private var stamps: [[Double]] = []   // מתי שונה כל סט (מילישניות)
    private var exIds: [String] = []
    private var liveRev = 0
    private var pushTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var lastVitals = Date.distantPast
    private var skipLive: Set<String> = []

    struct Summary { var sets: Int; var volume: Int; var minutes: Int; var kcal: Int; var hr: Int; var saved: Bool; var onPhone: Bool = false }

    init() {
        restore()
        WatchSync.shared.activate()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if self.paired { await self.pollLive() }
                let wait: UInt64 = self.started != nil ? 2_000_000_000 : 4_000_000_000
                try? await Task.sleep(nanoseconds: wait)
            }
        }
    }

    // ---------- צימוד ----------
    func didPair(token: String, name: String?) {
        Api.token = token; Api.userName = name
        paired = true
        Task { await loadToday() }
    }
    func unpair() { Api.token = nil; paired = false; plan = nil }
    /// התחברות אוטומטית: הטוקן הגיע מהטלפון
    func pairedFromPhone(token: String, name: String?) {
        if Api.token == token || UserDefaults.standard.string(forKey: "set.watch.revoked") == token { return }
        WKInterfaceDevice.current().play(.success)
        didPair(token: token, name: name)
    }

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
        stamps = list.map { Array(repeating: 1, count: $0.sets.count) }
        exIds = list.indices.map { "w\($0)" }
        liveId = "w" + UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).lowercased()
        liveRev = 0
        idx = 0; started = Date(); summary = nil
        save()
        Task { await workout.start() }
        counter.begin()
        WKInterfaceDevice.current().play(.start)
        pushLive()
    }

    /// הסט הבא שלא בוצע בתרגיל הנוכחי
    func isDone(_ j: Int) -> Bool { done.indices.contains(idx) && done[idx].indices.contains(j) && done[idx][j] }
    var nextSet: Int? { done.indices.contains(idx) ? done[idx].firstIndex(of: false) : nil }

    func update(set j: Int, kg: Double, reps: Int) {
        guard ex.indices.contains(idx), ex[idx].sets.indices.contains(j) else { return }
        ex[idx].sets[j].kg = max(0, kg); ex[idx].sets[j].reps = max(0, reps)
        stamp(idx, j)
        // שינוי משקל עובר גם לסטים הבאים שעוד לא בוצעו
        for k in (j + 1)..<ex[idx].sets.count where !done[idx][k] { ex[idx].sets[k].kg = ex[idx].sets[j].kg; stamp(idx, k) }
        save(); pushLive()
    }

    func markDone(_ j: Int) {
        guard done.indices.contains(idx), done[idx].indices.contains(j) else { return }
        // ספירת חזרות אוטומטית: אם נספרו חזרות בסט הזה, הן נרשמות (אפשר לתקן בנגיעה על הסט)
        if counter.enabled && counter.reps >= 2 && ex[idx].sets.indices.contains(j) { ex[idx].sets[j].reps = counter.reps }
        done[idx][j] = true
        stamp(idx, j)
        save(); pushLive()
        counter.stop()
        WKInterfaceDevice.current().play(.success)
        let allDone = !done[idx].contains(false)
        if allDone && idx + 1 >= ex.count { return } // סט אחרון באימון: אין מנוחה
        startRest(Double(ex[idx].rest ?? 90))
        if allDone { idx += 1 }
    }
    func unmark(_ j: Int) {
        guard done.indices.contains(idx), done[idx].indices.contains(j) else { return }
        done[idx][j] = false; stamp(idx, j); save(); pushLive()
    }

    func addSet() {
        guard ex.indices.contains(idx) else { return }
        let last = ex[idx].sets.last ?? WSet(kg: 0, reps: 10)
        ex[idx].sets.append(last); done[idx].append(false)
        if stamps.indices.contains(idx) { stamps[idx].append(now()) }
        save(); pushLive()
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
    func skipRest() { restTask?.cancel(); restEnd = nil; if started != nil { counter.begin() } }

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
            self.counter.begin()
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
            let p = FinishPayload(name: liveName ?? plan?.name ?? "אימון", sk: liveSk ?? plan?.sk, start: Int(start.timeIntervalSince1970 * 1000), dur: dur, kcal: Int(kcal.rounded()), hr: Int(hr.rounded()), ex: out)
            do { try await Api.finish(p); saved = true } catch { addPending(p) }
        }
        // השעון שמר: הטלפון יסגור אצלו את האימון בלי לשמור שוב
        if let id = liveId { await Api.liveEnd(id: id, saved: !out.isEmpty) }
        summary = Summary(sets: sets, volume: Int(vol.rounded()), minutes: max(1, dur / 60), kcal: Int(kcal.rounded()), hr: Int(hr.rounded()), saved: saved || out.isEmpty)
        WKInterfaceDevice.current().play(.success)
        clearActive()
    }

    func cancelWorkout() {
        if let id = liveId { Task { await Api.liveEnd(id: id, saved: false) } }
        skipRest(); workout.discard(); clearActive()
    }

    func closeSummary() {
        summary = nil
        Task { await loadToday() }
    }

    // ---------- שמירה מקומית (אם האפליקציה נסגרת באמצע) ----------
    private struct Active: Codable { var plan: WPlan?; var ex: [WEx]; var done: [[Bool]]; var idx: Int; var started: Date; var liveId: String?; var stamps: [[Double]]?; var exIds: [String]?; var liveName: String?; var liveSk: Int? }
    private let activeKey = "set.watch.active", pendingKey = "set.watch.pending"

    private func save() {
        guard let s = started else { return }
        let a = Active(plan: plan, ex: ex, done: done, idx: idx, started: s, liveId: liveId, stamps: stamps, exIds: exIds, liveName: liveName, liveSk: liveSk)
        UserDefaults.standard.set(try? JSONEncoder().encode(a), forKey: activeKey)
    }
    private func restore() {
        guard let d = UserDefaults.standard.data(forKey: activeKey), let a = try? JSONDecoder().decode(Active.self, from: d) else { return }
        if Date().timeIntervalSince(a.started) > 4 * 3600 { UserDefaults.standard.removeObject(forKey: activeKey); return }
        plan = a.plan; ex = a.ex; done = a.done; idx = a.idx; started = a.started
        liveId = a.liveId; liveName = a.liveName; liveSk = a.liveSk
        stamps = a.stamps ?? a.ex.map { Array(repeating: 1, count: $0.sets.count) }
        exIds = a.exIds ?? a.ex.indices.map { "w\($0)" }
        Task { await workout.start() } // ממשיך למדוד דופק אחרי שהאפליקציה נפתחה מחדש
    }
    private func clearActive() {
        started = nil; ex = []; done = []; idx = 0
        stamps = []; exIds = []; liveId = nil; liveRev = 0; liveName = nil; liveSk = nil
        counter.stop()
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

    // ---------- סנכרון חי עם הטלפון ----------
    private var liveName: String?
    private var liveSk: Int?
    private func now() -> Double { Date().timeIntervalSince1970 * 1000 }
    private func stamp(_ i: Int, _ j: Int) {
        guard stamps.indices.contains(i) else { return }
        while stamps[i].count <= j { stamps[i].append(1) }
        stamps[i][j] = now()
    }
    private func snapshot() -> Live? {
        guard let id = liveId, let st = started else { return nil }
        var list: [LEx] = []
        for (i, e) in ex.enumerated() {
            let sets = e.sets.enumerated().map { (j, s) in
                LSet(kg: s.kg, reps: s.reps, done: done.indices.contains(i) && done[i].indices.contains(j) && done[i][j],
                     t: stamps.indices.contains(i) && stamps[i].indices.contains(j) ? stamps[i][j] : 1)
            }
            list.append(LEx(id: exIds.indices.contains(i) ? exIds[i] : "w\(i)", name: e.name, rest: e.rest, sets: sets))
        }
        return Live(id: id, name: liveName ?? plan?.name ?? "אימון", sk: liveSk ?? plan?.sk, startedAt: st.timeIntervalSince1970 * 1000, ex: list)
    }
    /// שולח לשרת את המצב (חצי שנייה אחרי השינוי האחרון)
    func pushLive() {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled, let l = self.snapshot() else { return }
            if let r = try? await Api.livePut(l), r.id == self.liveId { self.liveRev = r.rev ?? self.liveRev }
        }
    }
    /// מיזוג מה שהגיע מהטלפון: לכל סט, הגרסה עם החותמת המאוחרת יותר
    private func apply(_ l: Live) {
        var changed = false
        for (k, re) in l.ex.enumerated() {
            var i = exIds.firstIndex(of: re.id) ?? -1
            if i < 0, ex.indices.contains(k), ex[k].name == re.name { i = k }
            if i < 0 {
                ex.append(WEx(name: re.name, rest: re.rest, sets: re.sets.map { WSet(kg: $0.kg, reps: $0.reps) }))
                done.append(re.sets.map { $0.done }); stamps.append(re.sets.map { $0.t }); exIds.append(re.id)
                changed = true; continue
            }
            if exIds.indices.contains(i) { exIds[i] = re.id }
            for (j, rs) in re.sets.enumerated() {
                if !ex[i].sets.indices.contains(j) {
                    ex[i].sets.append(WSet(kg: rs.kg, reps: rs.reps)); done[i].append(rs.done)
                    while stamps[i].count <= j { stamps[i].append(1) }
                    stamps[i][j] = rs.t; changed = true; continue
                }
                let mine = stamps[i].indices.contains(j) ? stamps[i][j] : 1
                if rs.t > mine {
                    let was = done[i][j]
                    ex[i].sets[j].kg = rs.kg; ex[i].sets[j].reps = rs.reps; done[i][j] = rs.done
                    while stamps[i].count <= j { stamps[i].append(1) }
                    stamps[i][j] = rs.t; changed = true
                    if rs.done && !was {
                        phoneNote = "סט סומן בטלפון 📱"
                        WKInterfaceDevice.current().play(.click)
                        // אם זה הסט האחרון בתרגיל הנוכחי, עוברים לתרגיל הבא
                        if i == idx && !done[idx].contains(false) && idx + 1 < ex.count { idx += 1 }
                    }
                }
            }
        }
        if changed { save() }
    }
    func pollLive() async {
        guard let l = try? await Api.liveGet() else { return }
        if started != nil, let id = liveId, l.id == id {
            if l.ended != nil, l.by == "phone" {
                // האימון הסתיים בטלפון ונשמר שם. בשעון שומרים רק ל-Apple Health
                skipRest()
                let dur = Int(Date().timeIntervalSince(started ?? Date()))
                await workout.end()
                let sets = done.reduce(0) { $0 + $1.filter { $0 }.count }
                summary = l.how == "saved" ? Summary(sets: sets, volume: 0, minutes: max(1, dur / 60), kcal: Int(workout.calories.rounded()), hr: Int(workout.avgHeartRate.rounded()), saved: true, onPhone: true) : nil
                WKInterfaceDevice.current().play(.success)
                clearActive()
                return
            }
            if let rev = l.rev, rev != liveRev { liveRev = rev; apply(l) }
            // דופק וקלוריות לטלפון, כדי שיישמרו גם באימון שמסתיים שם
            if Date().timeIntervalSince(lastVitals) > 10, workout.heartRate > 0 || workout.calories > 0 {
                lastVitals = Date()
                await Api.liveVitals(id: id, hr: Int(workout.avgHeartRate.rounded()), kcal: Int(workout.calories.rounded()))
            }
            return
        }
        // אימון שהתחיל בטלפון: מצטרפים אליו אוטומטית
        if started == nil, summary == nil, l.ended == nil, l.src == "phone", !skipLive.contains(l.id),
           let upd = l.upd, Date().timeIntervalSince1970 * 1000 - upd < 10 * 60_000 {
            join(l)
        }
    }
    private func join(_ l: Live) {
        ex = l.ex.map { WEx(name: $0.name, rest: $0.rest, sets: $0.sets.map { WSet(kg: $0.kg, reps: $0.reps) }) }
        done = l.ex.map { $0.sets.map { $0.done } }
        stamps = l.ex.map { $0.sets.map { $0.t } }
        exIds = l.ex.map { $0.id }
        liveId = l.id; liveRev = l.rev ?? 0; liveName = l.name; liveSk = l.sk
        idx = done.firstIndex(where: { $0.contains(false) }) ?? 0
        started = l.startedAt.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
        summary = nil
        save()
        if !workout.running { Task { await workout.start() } }
        counter.begin()
        phoneNote = "מחובר לאימון בטלפון 📱"
        WKInterfaceDevice.current().play(.start)
    }
    /// הטלפון פתח את האפליקציה בשעון כי התחיל אימון: מצטרפים מיד
    func phoneStartedWorkout() {
        if !workout.running { Task { await workout.start() } }
        Task {
            for _ in 0..<8 {
                if started != nil { return }
                await pollLive()
                if started != nil { return }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
            if started == nil { workout.discard() }
        }
    }
    /// לא להצטרף שוב לאימון מהטלפון שבוטל בשעון
    func ignoreLive(_ id: String) { skipLive.insert(id) }
}
