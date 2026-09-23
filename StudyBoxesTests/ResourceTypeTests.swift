import XCTest
@testable import StudyBoxes

@MainActor
final class ResourceTypeTests: XCTestCase {
    func testYouTubeIsKeptAsLegacyButNotSelectableForNewResources() {
        XCTAssertTrue(ResourceType.allCases.contains(.youtube))
        XCTAssertFalse(ResourceType.selectableCases.contains(.youtube))
    }

    func testLinkTypesHaveEditableDefaultsAndExpectedURLBehavior() {
        XCTAssertEqual(ResourceType.moodleCourse.defaultURLString, "https://your-moodle-site.example/course/view.php?id=")
        XCTAssertEqual(ResourceType.github.defaultURLString, "https://github.com/")
        XCTAssertEqual(ResourceType.chatgpt.defaultURLString, "https://chatgpt.com/")

        XCTAssertTrue(ResourceType.moodleCourse.expectsURL)
        XCTAssertTrue(ResourceType.github.expectsURL)
        XCTAssertFalse(ResourceType.anki.expectsURL)
        XCTAssertFalse(ResourceType.file.expectsURL)
    }

    func testAnkiResourceMetadataAndLinkValidation() {
        XCTAssertTrue(ResourceType.selectableCases.contains(.anki))
        XCTAssertEqual(ResourceType.anki.title, "Anki")
        XCTAssertEqual(AnkiResourceService.normalizedLink("anki://x-callback-url/search?query=vocab"), "anki://x-callback-url/search?query=vocab")
        XCTAssertEqual(AnkiResourceService.normalizedLink("ankiweb.net/shared/info/123"), "https://ankiweb.net/shared/info/123")
        XCTAssertNil(AnkiResourceService.normalizedLink("nota url"))
        XCTAssertNil(AnkiResourceService.normalizedLink("file:///tmp/cards.apkg"))
    }

    func testResourceEditorKeepsWebResourceFieldsEmptyAndUsesPlaceholders() {
        for type in [ResourceType.website, .moodleCourse, .blackboardCourse, .overleaf, .github, .chatgpt] {
            XCTAssertEqual(ResourceEditorDefaults.initialURLString(for: type, existingURLString: nil), "")
            XCTAssertNil(ResourceEditorDefaults.initialSuggestion(for: type, existingURLString: nil))
        }

        XCTAssertEqual(ResourceEditorDefaults.initialURLString(for: .website, existingURLString: "https://example.com"), "https://example.com")
    }

    func testCommandPlaceholdersAreNotLaunchable() {
        XCTAssertFalse(ResourceType.commandPlaceholder.isLaunchable)
        XCTAssertFalse(ResourceType.notes.isLaunchable)
        XCTAssertTrue(ResourceType.anki.isLaunchable)
        XCTAssertTrue(ResourceType.website.isLaunchable)
    }

    func testResourceLauncherSkipsNonLaunchableResources() {
        let resource = StudyResource(
            title: "Terminal command",
            type: .commandPlaceholder,
            urlString: "rm -rf ~/Downloads"
        )

        let result = ResourceLauncher.shared.open(resource)

        XCTAssertEqual(result.status, .skipped)
        XCTAssertEqual(result.message, "Command placeholders are copy-only for now.")
    }

    func testResourceLauncherFailsInvalidURLsAndMissingFiles() {
        let invalidWebsite = StudyResource(title: "Bad URL", type: .website, urlString: "nota url")
        let missingFile = StudyResource(title: "Missing PDF", type: .file, urlString: "/tmp/study-boxes-missing-file.pdf")

        let websiteResult = ResourceLauncher.shared.open(invalidWebsite)
        let fileResult = ResourceLauncher.shared.open(missingFile)

        XCTAssertEqual(websiteResult.status, .failed)
        XCTAssertEqual(websiteResult.message, "That URL does not look right.")
        XCTAssertEqual(fileResult.status, .failed)
        XCTAssertEqual(fileResult.message, "This file or folder is missing. It may have been moved or deleted.")
    }

    func testResourceLauncherFailsInvalidAnkiLinksBeforeOpening() {
        let invalidAnki = StudyResource(title: "Deck", type: .anki, urlString: "nota url")

        let result = ResourceLauncher.shared.open(invalidAnki)

        XCTAssertEqual(result.status, .failed)
        XCTAssertEqual(result.message, "That Anki link does not look right.")
    }

    func testResourceHealthDetectsMissingPathsInvalidURLsAndCopyOnlyResources() {
        let missingFile = StudyResource(title: "Missing PDF", type: .file, urlString: "/tmp/study-boxes-missing-file.pdf")
        let invalidWebsite = StudyResource(title: "Bad URL", type: .website, urlString: "nota url")
        let invalidAnki = StudyResource(title: "Bad Deck", type: .anki, urlString: "nota url")
        let command = StudyResource(title: "Command", type: .commandPlaceholder, urlString: "swift test")

        XCTAssertEqual(ResourceHealthService.status(for: missingFile), .missingPath)
        XCTAssertEqual(ResourceHealthService.status(for: invalidWebsite), .invalidURL)
        XCTAssertEqual(ResourceHealthService.status(for: invalidAnki), .invalidURL)
        XCTAssertEqual(ResourceHealthService.status(for: command), .notLaunchable)
    }

    func testOpenEnabledResourcesSortsByOrderAndIgnoresDisabledItems() {
        let box = StudyBox(name: "Resources")
        box.resources = [
            StudyResource(box: box, title: "Disabled", type: .notes, orderIndex: 0, enabledByDefault: false),
            StudyResource(box: box, title: "Second", type: .notes, orderIndex: 2),
            StudyResource(box: box, title: "First", type: .notes, orderIndex: 1)
        ]

        let results = ResourceLauncher.shared.openEnabledResources(for: box)

        XCTAssertEqual(results.map(\.resourceTitle), ["First", "Second"])
        XCTAssertTrue(results.allSatisfy { $0.status == .skipped })
    }
}
