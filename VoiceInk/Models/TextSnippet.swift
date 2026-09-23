import Foundation
import SwiftData

@Model
final class TextSnippet {
    var id: UUID = UUID()
    var trigger: String = ""
    var expansion: String = ""
    var dateAdded: Date = Date()
    var isEnabled: Bool = true

    init(trigger: String, expansion: String, dateAdded: Date = Date(), isEnabled: Bool = true) {
        self.trigger = trigger
        self.expansion = expansion
        self.dateAdded = dateAdded
        self.isEnabled = isEnabled
    }
}
