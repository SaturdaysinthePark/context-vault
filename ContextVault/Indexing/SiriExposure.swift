import Foundation

/// The user's settings for what Siri and Apple Intelligence may see.
/// One place to read them, so the indexer, the entity queries and the
/// privacy screen can never disagree.
///
/// Backed by UserDefaults (the privacy screen binds to the same keys with
/// `@AppStorage`).
enum SiriExposure {
    static let enabledKey = "siriExposureEnabled"
    static let hiddenSourcesKey = "siriHiddenSources"
    static let hiddenKindsKey = "siriHiddenKinds"

    /// Master switch. Off means nothing is indexed and no entity query
    /// returns anything.
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }

    /// Sources whose cards and memories are withheld from Siri.
    static var hiddenSources: Set<SourceType> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: hiddenSourcesKey) ?? []
            return Set(raw.compactMap(SourceType.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: hiddenSourcesKey)
        }
    }

    /// Card kinds withheld from Siri ("never tell Siri about my bills").
    static var hiddenKinds: Set<CardKind> {
        get {
            let raw = UserDefaults.standard.stringArray(forKey: hiddenKindsKey) ?? []
            return Set(raw.compactMap(CardKind.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: hiddenKindsKey)
        }
    }

    static func allows(kind: CardKind, source: SourceType) -> Bool {
        isEnabled && !hiddenKinds.contains(kind) && !hiddenSources.contains(source)
    }
}
