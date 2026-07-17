import Foundation
import SwiftData

/// The kinds of "About Me" cards the vault distills from memories.
enum ProfileCardKind: String, Codable, CaseIterable, Sendable {
    case voice        // writing style & tone
    case work         // role, company, responsibilities
    case projects     // active projects and their state
    case people       // recurring collaborators & relationships
    case preferences  // tools, habits, likes/dislikes

    var displayName: String {
        switch self {
        case .voice: "Voice"
        case .work: "Work"
        case .projects: "Projects"
        case .people: "People"
        case .preferences: "Preferences"
        }
    }

    var icon: String {
        switch self {
        case .voice: "waveform"
        case .work: "briefcase"
        case .projects: "hammer"
        case .people: "person.2"
        case .preferences: "slider.horizontal.3"
        }
    }

    var distillationFocus: String {
        switch self {
        case .voice: "the user's writing style, tone, vocabulary, and communication patterns"
        case .work: "the user's role, company, responsibilities, and professional context"
        case .projects: "the user's active projects, their goals, and current status"
        case .people: "people who appear repeatedly and the user's relationship to them"
        case .preferences: "the user's preferences: tools, workflows, habits, likes and dislikes"
        }
    }
}

/// A distilled, editable profile card — the on-device answer to persona
/// files like voice.md / professional.md. Raw memories answer "what did I
/// write?"; profile cards answer "who am I?" and are cheap, high-value
/// context for both Siri and the in-app chat.
@Model
final class ProfileCard {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    /// Markdown body. User-editable; distillation never overwrites edits.
    var content: String
    /// A freshly distilled draft awaiting user review when `userEdited` is
    /// set — the user chooses to accept or dismiss it.
    var pendingSuggestion: String?
    var userEdited: Bool
    var siriVisible: Bool
    var lastDistilledAt: Date?

    var kind: ProfileCardKind {
        get { ProfileCardKind(rawValue: kindRaw) ?? .preferences }
        set { kindRaw = newValue.rawValue }
    }

    init(
        id: UUID = UUID(),
        kind: ProfileCardKind,
        content: String = "",
        userEdited: Bool = false,
        siriVisible: Bool = true
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.content = content
        self.userEdited = userEdited
        self.siriVisible = siriVisible
    }
}
