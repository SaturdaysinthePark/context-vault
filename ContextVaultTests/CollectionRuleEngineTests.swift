import Testing
import Foundation
@testable import ContextVault

struct CollectionRuleEngineTests {
    private let accountID = UUID()

    private func driveMemory(fileID: String, idChain: String?) -> Memory {
        let memory = Memory(
            title: "Doc",
            body: "body",
            sourceType: .googleDrive,
            sourceRef: "gdrive:\(accountID.uuidString):\(fileID)"
        )
        memory.sourceFolderPath = idChain
        return memory
    }

    private func obsidianMemory(path: String, folder: String?) -> Memory {
        let memory = Memory(
            title: "Note",
            body: "body",
            sourceType: .obsidian,
            sourceRef: "obsidian:\(accountID.uuidString):\(path)"
        )
        memory.sourcePath = folder
        return memory
    }

    @Test func entireSourceMatchesOnlyThatAccount() {
        let rule = CollectionRule(
            sourceAccountID: accountID,
            sourceTypeRaw: SourceType.googleDrive.rawValue,
            kind: .entireSource,
            displayName: "Entire Drive"
        )
        #expect(CollectionRuleEngine.matches(rule, driveMemory(fileID: "f1", idChain: nil)))

        let other = Memory(title: "x", body: "y", sourceType: .googleDrive,
                           sourceRef: "gdrive:\(UUID().uuidString):f2")
        #expect(!CollectionRuleEngine.matches(rule, other))
    }

    @Test func driveFolderRuleMatchesSubtreeByIDComponent() {
        let rule = CollectionRule(
            sourceAccountID: accountID,
            sourceTypeRaw: SourceType.googleDrive.rawValue,
            kind: .folder,
            folderID: "folderB",
            displayName: "Drive · /A/B"
        )
        // Direct child of B and deeper descendant both match.
        #expect(CollectionRuleEngine.matches(rule, driveMemory(fileID: "f1", idChain: "/folderA/folderB")))
        #expect(CollectionRuleEngine.matches(rule, driveMemory(fileID: "f2", idChain: "/folderA/folderB/folderC")))
        // Sibling and no-chain don't.
        #expect(!CollectionRuleEngine.matches(rule, driveMemory(fileID: "f3", idChain: "/folderA/folderX")))
        #expect(!CollectionRuleEngine.matches(rule, driveMemory(fileID: "f4", idChain: nil)))
        // Partial-ID overlap must not match ("folderBB" contains "folderB").
        #expect(!CollectionRuleEngine.matches(rule, driveMemory(fileID: "f5", idChain: "/folderA/folderBB")))
    }

    @Test func obsidianFolderRuleUsesPathBoundary() {
        let rule = CollectionRule(
            sourceAccountID: accountID,
            sourceTypeRaw: SourceType.obsidian.rawValue,
            kind: .folder,
            folderPath: "/Projects",
            displayName: "Vault · /Projects"
        )
        #expect(CollectionRuleEngine.matches(rule, obsidianMemory(path: "/Projects/a.md", folder: "/Projects")))
        #expect(CollectionRuleEngine.matches(rule, obsidianMemory(path: "/Projects/Sub/b.md", folder: "/Projects/Sub")))
        // Boundary guard: "/ProjectsOld" must not match "/Projects".
        #expect(!CollectionRuleEngine.matches(rule, obsidianMemory(path: "/ProjectsOld/c.md", folder: "/ProjectsOld")))
        #expect(!CollectionRuleEngine.matches(rule, obsidianMemory(path: "/d.md", folder: nil)))
    }

    @Test func wrongSourceTypeNeverMatches() {
        let rule = CollectionRule(
            sourceAccountID: accountID,
            sourceTypeRaw: SourceType.notion.rawValue,
            kind: .entireSource,
            displayName: "Entire Notion"
        )
        #expect(!CollectionRuleEngine.matches(rule, driveMemory(fileID: "f1", idChain: nil)))
    }
}

struct DriveFolderServiceTests {
    private func service() -> DriveFolderService {
        DriveFolderService(nodes: [
            "root": .init(id: "root", name: "My Drive", parent: nil),
            "a": .init(id: "a", name: "Alpha", parent: "root"),
            "b": .init(id: "b", name: "Beta", parent: "a"),
            "c": .init(id: "c", name: "Gamma", parent: "b"),
            "x": .init(id: "x", name: "Other", parent: "root"),
        ])
    }

    @Test func resolvesFullPaths() {
        var s = service()
        let paths = s.paths(for: "c")
        #expect(paths?.path == "/My Drive/Alpha/Beta/Gamma")
        #expect(paths?.idPath == "/root/a/b/c")
    }

    @Test func descendantClosureIncludesSubtree() {
        let s = service()
        let closure = s.descendantClosure(of: ["a"])
        #expect(closure == ["a", "b", "c"])
    }

    @Test func scopeTestWalksAncestors() {
        let s = service()
        let allowed: Set<String> = ["a"]
        #expect(s.isInScope(parentID: "c", allowed: allowed))   // deep child
        #expect(s.isInScope(parentID: "a", allowed: allowed))   // direct
        #expect(!s.isInScope(parentID: "x", allowed: allowed))  // sibling
        #expect(!s.isInScope(parentID: nil, allowed: allowed))  // rootless
    }
}
