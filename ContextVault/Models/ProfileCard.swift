import Foundation
import SwiftData

/// The single "About Me" card — an auto-distilled, user-editable portrait of
/// the user built from their memories (the on-device answer to persona files
/// like voice.md / professional.md). Raw memories answer "what did I write?";
/// this card answers "who am I?" and is dense, always-on context for both
/// Siri and the in-app chat.
///
/// Sections live inside one markdown body: identity & work, current
/// projects, writing voice, preferences.
@Model
final class ProfileCard {
    @Attribute(.unique) var id: UUID
    /// Markdown body. User-editable; distillation never overwrites edits.
    var content: String
    /// A freshly distilled draft awaiting review when `userEdited` is set —
    /// the user accepts or dismisses it.
    var pendingSuggestion: String?
    var userEdited: Bool
    var siriVisible: Bool
    var lastDistilledAt: Date?

    init(
        id: UUID = UUID(),
        content: String = "",
        userEdited: Bool = false,
        siriVisible: Bool = true
    ) {
        self.id = id
        self.content = content
        self.userEdited = userEdited
        self.siriVisible = siriVisible
    }
}
