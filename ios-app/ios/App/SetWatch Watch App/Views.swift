import SwiftUI
import WatchKit

// ---------- מסך ראשי ----------
struct RootView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        NavigationStack {
            if let s = app.summary { SummaryView(s: s) }
            else if !app.paired { PairView() }
            else if app.started != nil { WorkoutView() }
            else { TodayView() }
        }
        .environmentObject(app.workout)
        .environmentObject(app.counter)
        .environment(\.layoutDirection, .rightToLeft)
        .tint(Theme.accent)
    }
}

enum Theme {
    static let accent = Color(red: 0.91, green: 0.47, blue: 0.29) // #E8794A
    static func kg(_ v: Double) -> String { v == v.rounded() ? String(Int(v)) : String(format: "%.1f", v) }
    static func clock(_ s: Int) -> String { s >= 3600 ? String(format: "%ld:%02ld:%02ld", s / 3600, s % 3600 / 60, s % 60) : String(format: "%ld:%02ld", s / 60, s % 60) }
}

// ---------- צימוד עם הטלפון ----------
struct PairView: View {
    @EnvironmentObject var app: AppState
    @State private var code: String?
    @State private var err: String?
    @State private var busy = false

    var body: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text("סט").font(.title2.bold()).foregroundStyle(Theme.accent)
                    .onAppear { WatchSync.shared.activate() }
                if code == nil && !busy {
                    Text("פתח את סט באייפון. אם האפליקציה מותקנת גם כאן, השעון יתחבר לבד תוך כמה שניות.").font(.footnote).multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                if let code {
                    Text("הקוד שלך").font(.footnote).foregroundStyle(.secondary)
                    Text(code).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                        .environment(\.layoutDirection, .leftToRight)
                    Text("באפליקציה בטלפון: פרופיל ← Apple Watch ← הקלד את הקוד").font(.footnote).multilineTextAlignment(.center)
                    ProgressView().padding(.top, 4)
                } else {
                    Button(busy ? "רגע..." : "התחבר עם קוד") { Task { await begin() } }.disabled(busy)
                }
                if let err { Text(err).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center) }
            }
        }
    }

    func begin() async {
        busy = true; err = nil
        do {
            let s = try await Api.pairStart()
            code = s.code
            // בודק כל 2 שניות אם הקוד הוזן בטלפון (עד 10 דקות)
            for _ in 0..<300 {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                let st = try await Api.pairStatus(s.pid)
                if st.ok, let t = st.token { WKInterfaceDevice.current().play(.success); app.didPair(token: t, name: st.name); return }
            }
            code = nil; err = "הקוד פג. נסה שוב"
        } catch { code = nil; err = error.localizedDescription }
        busy = false
    }
}

// ---------- אימון היום ----------
struct TodayView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if app.loading && app.plan == nil {
                    ProgressView().frame(maxWidth: .infinity)
                } else if let p = app.plan, p.none != true, let list = p.ex, !list.isEmpty {
                    Text(p.when ?? "היום").font(.footnote).foregroundStyle(Theme.accent)
                    Text(p.name ?? "אימון").font(.headline).lineLimit(2)
                    Text("\(list.count) תרגילים · \(list.reduce(0) { $0 + $1.sets.count }) סטים").font(.footnote).foregroundStyle(.secondary)
                    Button { app.start() } label: { Label("התחל אימון", systemImage: "play.fill").frame(maxWidth: .infinity) }
                        .buttonStyle(.borderedProminent).padding(.vertical, 4)
                    ForEach(Array(list.enumerated()), id: \.offset) { _, e in
                        HStack {
                            Text(e.name).font(.footnote).lineLimit(2)
                            Spacer()
                            Text("\(e.sets.count)×\(e.sets.first?.reps ?? 0)").font(.footnote).foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                } else {
                    Text(app.plan?.msg ?? app.error ?? "אין אימון מתוכנן כרגע").font(.footnote).multilineTextAlignment(.leading)
                    Button("רענן") { Task { await app.loadToday() } }
                }
                if let e = app.error, app.plan != nil { Text(e).font(.footnote).foregroundStyle(.red) }
            }
        }
        .navigationTitle("סט")
        .task { if app.plan == nil { await app.loadToday() } }
        .refreshable { await app.loadToday() }
    }
}

// ---------- אימון פעיל ----------
struct WorkoutView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var hk: WorkoutManager
    @EnvironmentObject var counter: RepCounter
    @State private var editing: Int?
    @State private var askEnd = false

    var body: some View {
        ZStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    stats
                    if let note = app.phoneNote {
                        Text(note).font(.caption2).foregroundStyle(Theme.accent)
                            .task(id: note) { try? await Task.sleep(nanoseconds: 3_000_000_000); if app.phoneNote == note { app.phoneNote = nil } }
                    } else if app.liveId != nil {
                        Label("מסונכרן עם הטלפון", systemImage: "iphone").font(.caption2).foregroundStyle(.secondary)
                    }
                    if let e = app.current {
                        Text("תרגיל \(app.idx + 1) מתוך \(app.ex.count)").font(.caption2).foregroundStyle(.secondary)
                        Text(e.name).font(.headline).lineLimit(3)
                        ForEach(e.sets.indices, id: \.self) { j in setRow(e, j) }
                        if let n = app.nextSet {
                            if counter.enabled && counter.available && app.restEnd == nil {
                                HStack {
                                    Image(systemName: "waveform.path.ecg").foregroundStyle(Theme.accent)
                                    Text(counter.reps > 0 ? "נספרו \(counter.reps) חזרות" : "סופר חזרות…").font(.caption2).monospacedDigit()
                                    Spacer()
                                }
                            }
                            Button { app.markDone(n) } label: { Label("סט \(n + 1) בוצע", systemImage: "checkmark").frame(maxWidth: .infinity) }
                                .buttonStyle(.borderedProminent)
                        }
                        Button { app.addSet() } label: { Label("הוסף סט", systemImage: "plus") }.font(.footnote)
                        HStack {
                            Button { app.idx = max(0, app.idx - 1) } label: { Image(systemName: "chevron.right") }.disabled(app.idx == 0)
                            Button { app.idx = min(app.ex.count - 1, app.idx + 1) } label: { Image(systemName: "chevron.left") }.disabled(app.idx >= app.ex.count - 1)
                        }
                    }
                    Toggle(isOn: Binding(get: { counter.enabled }, set: { counter.enabled = $0; if $0 { counter.begin() } else { counter.stop() } })) {
                        Text("ספירת חזרות אוטומטית").font(.caption2)
                    }
                    .padding(.top, 4)
                    Button(role: .destructive) { askEnd = true } label: { Label("סיים אימון", systemImage: "flag.checkered").frame(maxWidth: .infinity) }
                        .padding(.top, 6)
                }
            }
            if app.restEnd != nil { RestView().transition(.opacity) }
        }
        .navigationBarBackButtonHidden(true)
        .sheet(item: Binding(get: { editing.map { EditTarget(id: $0) } }, set: { editing = $0?.id })) { t in
            SetEditor(j: t.id)
        }
        .confirmationDialog("לסיים את האימון?", isPresented: $askEnd) {
            Button("סיים ושמור") { Task { await app.finish() } }
            Button("בטל אימון בלי לשמור", role: .destructive) { app.cancelWorkout() }
            Button("המשך להתאמן", role: .cancel) {}
        } message: { Text("בוצעו \(app.doneSets) מתוך \(app.totalSets) סטים") }
    }

    var stats: some View {
        HStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(Theme.clock(Int(Date().timeIntervalSince(app.started ?? Date())))).monospacedDigit().foregroundStyle(.yellow)
            }
            Spacer()
            Label(hk.heartRate > 0 ? "\(Int(hk.heartRate))" : "--", systemImage: "heart.fill").foregroundStyle(.red).monospacedDigit()
            Label("\(Int(hk.calories))", systemImage: "flame.fill").foregroundStyle(.orange).monospacedDigit()
        }
        .font(.caption).labelStyle(TightLabel())
    }

    func setRow(_ e: WEx, _ j: Int) -> some View {
        let isDone = app.isDone(j)
        return Button { editing = j } label: {
            HStack {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle").foregroundStyle(isDone ? .green : .secondary)
                Text("\(Theme.kg(e.sets[j].kg)) ק״ג × \(e.sets[j].reps)").monospacedDigit()
                Spacer()
            }
        }
        .buttonStyle(.bordered)
        .opacity(isDone ? 0.7 : 1)
    }
}

struct EditTarget: Identifiable { let id: Int }

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View { HStack(spacing: 2) { configuration.icon; configuration.title } }
}


// ---------- עריכת סט: כתר דיגיטלי למשקל ----------
struct SetEditor: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) var dismiss
    let j: Int
    @State private var kg: Double = 0
    @State private var reps: Int = 0

    var body: some View {
        let isDone = app.isDone(j)
        ScrollView {
            VStack(spacing: 6) {
                Text("סט \(j + 1)").font(.footnote).foregroundStyle(.secondary)
                Text("\(Theme.kg(kg)) ק״ג").font(.title2.bold()).monospacedDigit()
                    .focusable()
                    .digitalCrownRotation($kg, from: 0, through: 300, by: 2.5, sensitivity: .medium, isContinuous: false, isHapticFeedbackEnabled: true)
                Text("סובב את הכתר לשינוי משקל").font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Button { reps = max(0, reps - 1) } label: { Image(systemName: "minus") }
                    Text("\(reps) חזרות").monospacedDigit().frame(minWidth: 70)
                    Button { reps += 1 } label: { Image(systemName: "plus") }
                }
                Button {
                    app.update(set: j, kg: kg, reps: reps)
                    if !isDone { app.markDone(j) }
                    dismiss()
                } label: { Text(isDone ? "שמור" : "שמור ובוצע ✓").frame(maxWidth: .infinity) }
                .buttonStyle(.borderedProminent)
                if isDone { Button("בטל סימון") { app.unmark(j); dismiss() }.font(.footnote) }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear {
            if app.ex.indices.contains(app.idx), app.ex[app.idx].sets.indices.contains(j) {
                kg = app.ex[app.idx].sets[j].kg; reps = app.ex[app.idx].sets[j].reps
            }
        }
    }
}

// ---------- טיימר מנוחה ----------
struct RestView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            let left = max(0, (app.restEnd ?? Date()).timeIntervalSinceNow)
            VStack(spacing: 6) {
                Text("מנוחה").font(.footnote).foregroundStyle(.secondary)
                ZStack {
                    Circle().stroke(Color.gray.opacity(0.3), lineWidth: 7)
                    Circle().trim(from: 0, to: app.restTotal > 0 ? left / app.restTotal : 0)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    Text(Theme.clock(Int(left.rounded(.up)))).font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                }
                .frame(width: 100, height: 100)
                if let e = app.current { Text("הבא: \(e.name)").font(.caption2).lineLimit(1) }
                HStack {
                    Button("+30") { app.addRest(30) }
                    Button("דלג") { app.skipRest() }.buttonStyle(.borderedProminent)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
        }
    }
}

// ---------- סיכום ----------
struct SummaryView: View {
    @EnvironmentObject var app: AppState
    let s: AppState.Summary
    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Image(systemName: "checkmark.seal.fill").font(.largeTitle).foregroundStyle(Theme.accent)
                Text("כל הכבוד!").font(.headline)
                grid
                Text(s.onPhone ? "האימון הסתיים בטלפון ונשמר שם. הדופק והקלוריות נשמרו ב-Apple Health" : s.saved ? "האימון נשמר ביומן האימונים בטלפון" : "אין חיבור כרגע. האימון יישמר באפליקציה ברגע שיהיה חיבור")
                    .font(.footnote).multilineTextAlignment(.center).foregroundStyle(s.saved ? .green : .orange)
                Button("סגור") { app.closeSummary() }.buttonStyle(.borderedProminent)
            }
        }
    }
    var grid: some View {
        VStack(spacing: 4) {
            row("סטים", "\(s.sets)"); row("נפח", "\(s.volume) ק״ג"); row("זמן", "\(s.minutes) דק׳")
            row("קלוריות", s.kcal > 0 ? "\(s.kcal)" : "--"); row("דופק ממוצע", s.hr > 0 ? "\(s.hr)" : "--")
        }.font(.footnote)
    }
    func row(_ a: String, _ b: String) -> some View { HStack { Text(a).foregroundStyle(.secondary); Spacer(); Text(b).monospacedDigit() } }
}
