import Testing
@testable import ContextVault

struct ContextPackExporterTests {
    @Test func aboutMeOnlyPack() {
        let pack = ContextPackExporter.renderAboutMe("## Who I am\n- Founder")
        #expect(pack.contains("# Context Pack — Context Vault"))
        #expect(pack.contains("## About the user"))
        #expect(pack.contains("- Founder"))
    }

    @Test func fullPackIncludesCollectionsAndAspects() {
        let collection = ContextPackExporter.CollectionInput(
            name: "Home Renovation",
            details: "Everything about the house project.",
            aspects: [("topic", "renovation"), ("person", "Dave")],
            memories: [
                .init(title: "Bathroom tile", body: "We chose slate gray."),
                .init(title: "Budget", body: "Cap is $40k.")
            ]
        )
        let pack = ContextPackExporter.render(aboutMe: "- I own a house", collections: [collection])

        #expect(pack.contains("## About the user"))
        #expect(pack.contains("## Collection: Home Renovation"))
        #expect(pack.contains("Everything about the house project."))
        #expect(pack.contains("topic: renovation · person: Dave"))
        #expect(pack.contains("### Bathroom tile"))
        #expect(pack.contains("We chose slate gray."))
        #expect(pack.contains("### Budget"))
    }

    @Test func nilAboutMeIsOmitted() {
        let pack = ContextPackExporter.render(aboutMe: nil, collections: [])
        #expect(!pack.contains("## About the user"))
        #expect(pack.contains("# Context Pack — Context Vault"))
    }

    @Test func emptyAspectsProduceNoAspectLine() {
        let collection = ContextPackExporter.CollectionInput(
            name: "Misc", details: "", aspects: [], memories: []
        )
        let pack = ContextPackExporter.render(aboutMe: nil, collections: [collection])
        #expect(!pack.contains("*Aspects"))
        #expect(pack.contains("## Collection: Misc"))
    }
}

struct SensitivityModelTests {
    @Test func sensitivityRoundTrips() {
        for value in Sensitivity.allCases {
            #expect(Sensitivity(rawValue: value.rawValue) == value)
        }
    }
}
