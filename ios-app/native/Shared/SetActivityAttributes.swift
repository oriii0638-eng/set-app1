import ActivityKit
import Foundation

// המידע של האימון הפעיל במסך הנעילה וב-Dynamic Island. משותף לאפליקציה ולווידג'ט.
@available(iOS 16.1, *)
struct SetActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var name: String      // שם האימון
        var ex: String        // התרגיל הנוכחי
        var set: String       // "סט 2 מתוך 4"
        var load: String      // "40 ק״ג × 10"
        var mode: String      // work | rest | pause
        var restEnd: Double   // סוף המנוחה (שניות מ-1970), 0 אם אין
        var start: Double     // תחילת האימון (שניות מ-1970)
        var done: String      // "12/24"
    }
    var id: String
}
