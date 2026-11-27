import WidgetKit
import SwiftUI

// ווידג'ט מסך הבית ומסך הנעילה: אימון היום, רצף, והתקדמות השבוע
struct TodayData: Codable {
    var name: String?
    var when: String?
    var ex: Int?
    var mins: Int?
    var streak: Int?
    var wk: Int?
    var goal: Int?
    var doneToday: Bool?
    var user: String?

    static func load() -> TodayData {
        guard let s = UserDefaults(suiteName: "group.com.setapp.workout")?.string(forKey: "today"),
              let data = s.data(using: .utf8),
              let d = try? JSONDecoder().decode(TodayData.self, from: data) else { return TodayData() }
        return d
    }
    static let sample = TodayData(name: "פלג גוף עליון", when: "היום", ex: 6, mins: 45, streak: 4, wk: 2, goal: 4, doneToday: false, user: nil)
}

struct TodayEntry: TimelineEntry {
    let date: Date
    let d: TodayData
}

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { TodayEntry(date: Date(), d: .sample) }
    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(TodayEntry(date: Date(), d: context.isPreview ? .sample : TodayData.load()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let entry = TodayEntry(date: Date(), d: TodayData.load())
        let next = Calendar.current.startOfDay(for: Date().addingTimeInterval(86400)).addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    let d: TodayData

    var title: String {
        if d.doneToday == true { return "האימון של היום בוצע ✓" }
        return d.name?.isEmpty == false ? d.name! : "אין אימון מתוכנן"
    }
    var whenText: String { d.doneToday == true ? "כל הכבוד" : (d.when?.isEmpty == false ? d.when! : "") }
    var wk: Int { d.wk ?? 0 }
    var goal: Int { max(1, d.goal ?? 3) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular:
                Gauge(value: Double(min(wk, goal)), in: 0...Double(goal)) {
                    Image(systemName: "dumbbell.fill")
                } currentValueLabel: {
                    Text("\(wk)/\(goal)")
                }
                .gaugeStyle(.accessoryCircular)
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 1) {
                    Text("סט · \(whenText)").font(.caption2).bold()
                    Text(title).font(.headline).lineLimit(1)
                    Text("🔥 \(d.streak ?? 0) · השבוע \(wk)/\(goal)").font(.caption2)
                }
            case .accessoryInline:
                Text("סט: \(title)")
            case .systemMedium:
                medium
            default:
                small
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .containerBackground(for: .widget) { SetTheme.bg }
    }

    var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("סט").font(.headline.bold()).foregroundStyle(SetTheme.accent)
                Spacer()
                if (d.streak ?? 0) > 0 { Text("🔥\(d.streak!)").font(.caption.bold()).foregroundStyle(.white) }
            }
            Spacer(minLength: 0)
            if !whenText.isEmpty { Text(whenText).font(.caption).foregroundStyle(SetTheme.accent) }
            Text(title).font(.headline).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
            if (d.ex ?? 0) > 0 && d.doneToday != true {
                Text("\(d.ex!) תרגילים").font(.caption2).foregroundStyle(.gray)
            }
            weekBar
        }
    }

    var medium: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("סט").font(.headline.bold()).foregroundStyle(SetTheme.accent)
                Spacer(minLength: 0)
                if !whenText.isEmpty { Text(whenText).font(.caption).foregroundStyle(SetTheme.accent) }
                Text(title).font(.title3.bold()).foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.8)
                if (d.ex ?? 0) > 0 && d.doneToday != true {
                    Text("\(d.ex!) תרגילים · כ-\(d.mins ?? 0) דקות").font(.caption).foregroundStyle(.gray)
                }
            }
            Spacer(minLength: 0)
            VStack(spacing: 8) {
                stat("🔥", "\(d.streak ?? 0)", "רצף")
                stat("📅", "\(wk)/\(goal)", "השבוע")
            }
        }
    }

    func stat(_ icon: String, _ v: String, _ l: String) -> some View {
        VStack(spacing: 0) {
            Text("\(icon) \(v)").font(.headline).foregroundStyle(.white).monospacedDigit()
            Text(l).font(.caption2).foregroundStyle(.gray)
        }
        .frame(width: 76, height: 50)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    var weekBar: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule().fill(SetTheme.accent).frame(width: g.size.width * CGFloat(min(wk, goal)) / CGFloat(goal))
            }
        }
        .frame(height: 5)
    }
}

struct TodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SetToday", provider: TodayProvider()) { entry in
            TodayWidgetView(d: entry.d)
        }
        .configurationDisplayName("האימון של היום")
        .description("האימון הבא, הרצף וההתקדמות השבועית")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}
