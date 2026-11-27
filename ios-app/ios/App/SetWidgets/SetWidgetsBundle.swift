import WidgetKit
import SwiftUI

@main
struct SetWidgetsBundle: WidgetBundle {
    var body: some Widget {
        TodayWidget()
        WorkoutLiveActivity()
    }
}

enum SetTheme {
    static let accent = Color(red: 0.91, green: 0.47, blue: 0.29) // #E8794A
    static let bg = Color(red: 0.04, green: 0.04, blue: 0.04)     // #0A0A0A
}
