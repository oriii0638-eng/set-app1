import ActivityKit
import WidgetKit
import SwiftUI

// אימון פעיל במסך הנעילה וב-Dynamic Island: התרגיל, הסט, וטיימר המנוחה
struct WorkoutLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SetActivityAttributes.self) { ctx in
            LockView(s: ctx.state)
                .activityBackgroundTint(SetTheme.bg.opacity(0.9))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { ctx in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("סט").font(.headline.bold()).foregroundStyle(SetTheme.accent)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(s: ctx.state).font(.title3.bold()).monospacedDigit()
                        .foregroundStyle(ctx.state.mode == "rest" ? SetTheme.accent : .white)
                        .frame(maxWidth: 90)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(ctx.state.ex).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(ctx.state.set)
                        Spacer()
                        Text(ctx.state.mode == "rest" ? "מנוחה" : ctx.state.load)
                    }
                    .font(.subheadline).foregroundStyle(.secondary)
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: ctx.state.mode == "rest" ? "timer" : "dumbbell.fill").foregroundStyle(SetTheme.accent)
            } compactTrailing: {
                TimerText(s: ctx.state).monospacedDigit().frame(maxWidth: 52)
                    .foregroundStyle(ctx.state.mode == "rest" ? SetTheme.accent : .white)
            } minimal: {
                Image(systemName: "dumbbell.fill").foregroundStyle(SetTheme.accent)
            }
        }
    }
}

struct TimerText: View {
    let s: SetActivityAttributes.ContentState
    var body: some View {
        let end = Date(timeIntervalSince1970: s.restEnd)
        if s.mode == "rest" && end > Date() {
            Text(timerInterval: Date()...end, countsDown: true).multilineTextAlignment(.trailing)
        } else if s.mode == "pause" {
            Text("מושהה")
        } else {
            Text(Date(timeIntervalSince1970: s.start), style: .timer).multilineTextAlignment(.trailing)
        }
    }
}

struct LockView: View {
    let s: SetActivityAttributes.ContentState
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("סט").font(.headline.bold()).foregroundStyle(SetTheme.accent)
                Text(s.name).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
                Text(s.done).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(s.ex).font(.title3.bold()).foregroundStyle(.white).lineLimit(1)
                    Text(s.load.isEmpty ? s.set : "\(s.set) · \(s.load)").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(s.mode == "rest" ? "מנוחה" : s.mode == "pause" ? "האימון מושהה" : "זמן אימון")
                        .font(.caption).foregroundStyle(.secondary)
                    TimerText(s: s)
                        .font(.system(size: 34, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(s.mode == "rest" ? SetTheme.accent : .white)
                        .frame(maxWidth: 130, alignment: .trailing)
                }
            }
        }
        .padding(16)
        .environment(\.layoutDirection, .rightToLeft)
    }
}
