import XCTest
@testable import StudyBoxes

@MainActor
final class LaunchReadinessTests: XCTestCase {
    func testMenuBarAgentRecognizesCommandQAsQuitShortcut() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "q",
            charactersIgnoringModifiers: "q",
            isARepeat: false,
            keyCode: 12
        )

        XCTAssertTrue(AppDelegate.isQuitShortcut(event))
    }

    func testMenuBarAgentDoesNotTreatOtherCommandKeysAsQuitShortcut() {
        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        )

        XCTAssertFalse(AppDelegate.isQuitShortcut(event))
    }

    func testOnboardingStatePersistsCompletion() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let state = OnboardingState(userDefaults: defaults)
        XCTAssertFalse(state.hasCompletedOnboarding)

        state.complete()

        let reloaded = OnboardingState(userDefaults: defaults)
        XCTAssertTrue(reloaded.hasCompletedOnboarding)
    }

    func testOnboardingCompletionQueuesMenuBarHintOnce() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let state = OnboardingState(userDefaults: defaults)
        state.complete()

        let reloaded = OnboardingState(userDefaults: defaults)
        XCTAssertTrue(reloaded.consumeMenuBarHintIfNeeded())
        XCTAssertFalse(reloaded.consumeMenuBarHintIfNeeded())

        let consumedAgain = OnboardingState(userDefaults: defaults)
        XCTAssertFalse(consumedAgain.consumeMenuBarHintIfNeeded())
    }

    #if DEBUG
    func testOnboardingStateResetClearsCompletionInDebugBuilds() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let state = OnboardingState(userDefaults: defaults)
        state.complete()
        XCTAssertTrue(state.hasCompletedOnboarding)

        state.reset()

        let reloaded = OnboardingState(userDefaults: defaults)
        XCTAssertFalse(reloaded.hasCompletedOnboarding)
        XCTAssertFalse(reloaded.consumeMenuBarHintIfNeeded())
    }
    #endif

    func testEveryTemplateHasExpectedIdentityAndDefaults() {
        let expectations: [(StudyBoxTemplate, String, StudyBoxType, String, Int, String)] = [
            (.weeklyCourse, "Weekly course", .course, "books.vertical", 50, "#3B82F6"),
            (.examPrep, "Exam prep", .exam, "graduationcap", 50, "#EF4444"),
            (.assignment, "Assignment", .assignment, "doc.text", 45, "#F59E0B"),
            (.codingProject, "Coding project", .project, "chevron.left.forwardslash.chevron.right", 50, "#14B8A6"),
            (.languageStudy, "Language study", .language, "textformat.abc", 30, "#A855F7")
        ]

        XCTAssertEqual(StudyBoxTemplate.allCases.count, expectations.count)

        for (template, title, boxType, icon, minutes, colorHex) in expectations {
            XCTAssertEqual(template.title, title)
            XCTAssertFalse(template.subtitle.isEmpty)
            XCTAssertEqual(template.boxType, boxType)
            XCTAssertEqual(template.systemImage, icon)
            XCTAssertEqual(template.defaultSessionMinutes, minutes)
            XCTAssertEqual(template.colorHex, colorHex)
            XCTAssertFalse(template.defaultTasks.isEmpty)
        }
    }

    func testEveryTemplateCreatesEditableLocalBoxData() {
        for template in StudyBoxTemplate.allCases {
            let box = StudyBoxTemplateService.makeBox(
                template: template,
                name: "\(template.title) Box"
            )

            XCTAssertEqual(box.type, template.boxType)
            XCTAssertEqual(box.icon, template.systemImage)
            XCTAssertEqual(box.colorHex, template.colorHex)
            XCTAssertEqual(box.defaultSessionMinutes, template.defaultSessionMinutes)
            XCTAssertEqual(box.tasks.count, template.defaultTasks.count)
            XCTAssertTrue(box.resources.isEmpty)
            XCTAssertTrue(box.openResourcesOnSessionStart)
            XCTAssertFalse(box.hideDistractionsOnSessionStart)
            XCTAssertFalse(box.restoreWindowLayoutOnSessionStart)
        }
    }

    func testExamPrepTemplateCreatesExpectedLocalData() {
        let box = StudyBoxTemplateService.makeBox(
            template: .examPrep,
            name: "Probability final",
            courseName: "STAT201",
            firstTaskTitle: "Redo Bayes problems",
            resources: [
                OnboardingResourceDraft(
                    title: "Course site",
                    type: .website,
                    urlString: "https://example.com/course"
                )
            ]
        )

        XCTAssertEqual(box.name, "Probability final")
        XCTAssertEqual(box.type, .exam)
        XCTAssertEqual(box.courseName, "STAT201")
        XCTAssertEqual(box.defaultSessionMinutes, 50)
        XCTAssertEqual(box.resources.first?.type, .website)
        XCTAssertTrue(box.tasks.contains { $0.title == "Review weak topics" && $0.priority == 3 })
        XCTAssertTrue(box.tasks.contains { $0.title == "Attempt one past exam section" && $0.type == .pastExam })
        XCTAssertTrue(box.tasks.contains { $0.title == "Redo Bayes problems" })
    }

    func testTemplateTrimsBlankInputsAndUsesSensibleFallbackName() {
        let box = StudyBoxTemplateService.makeBox(
            template: .weeklyCourse,
            name: "   ",
            courseName: "   ",
            firstTaskTitle: "   "
        )

        XCTAssertEqual(box.name, "Weekly course")
        XCTAssertNil(box.courseName)
        XCTAssertEqual(box.tasks.count, StudyBoxTemplate.weeklyCourse.defaultTasks.count)
    }

    func testTemplateStoresOptionalFileFolderAndWebsiteDraftsInOrder() {
        let box = StudyBoxTemplateService.makeBox(
            template: .codingProject,
            name: "Compiler",
            resources: [
                OnboardingResourceDraft(title: "Repo", type: .github, urlString: "https://github.com/example/repo"),
                OnboardingResourceDraft(title: "Spec", type: .file, urlString: "/tmp/spec.pdf"),
                OnboardingResourceDraft(title: "Source", type: .folder, urlString: "/tmp/source")
            ]
        )

        XCTAssertEqual(box.resources.map(\.title), ["Repo", "Spec", "Source"])
        XCTAssertEqual(box.resources.map(\.type), [.github, .file, .folder])
        XCTAssertEqual(box.resources.map(\.orderIndex), [0, 1, 2])
        XCTAssertTrue(box.resources.allSatisfy(\.enabledByDefault))
    }

    func testTemplateStoresOptionalAnkiDraft() {
        let box = StudyBoxTemplateService.makeBox(
            template: .languageStudy,
            name: "French",
            resources: [
                OnboardingResourceDraft(title: "Anki", type: .anki, urlString: "anki://x-callback-url/search?query=verbs")
            ]
        )

        XCTAssertEqual(box.resources.count, 1)
        XCTAssertEqual(box.resources.first?.title, "Anki")
        XCTAssertEqual(box.resources.first?.type, .anki)
        XCTAssertEqual(box.resources.first?.urlString, "anki://x-callback-url/search?query=verbs")
        XCTAssertTrue(box.resources.first?.enabledByDefault == true)
    }

    func testTemplateStoresOptionalAppDraftBundleMetadata() {
        let box = StudyBoxTemplateService.makeBox(
            template: .codingProject,
            name: "Compiler",
            resources: [
                OnboardingResourceDraft(
                    title: "Xcode",
                    type: .app,
                    urlString: "/Applications/Xcode.app",
                    appBundleID: "com.apple.dt.Xcode",
                    appPath: "/Applications/Xcode.app"
                )
            ]
        )

        XCTAssertEqual(box.resources.count, 1)
        XCTAssertEqual(box.resources.first?.title, "Xcode")
        XCTAssertEqual(box.resources.first?.type, .app)
        XCTAssertEqual(box.resources.first?.urlString, "/Applications/Xcode.app")
        XCTAssertEqual(box.resources.first?.appBundleID, "com.apple.dt.Xcode")
        XCTAssertEqual(box.resources.first?.appPath, "/Applications/Xcode.app")
    }

    func testTemplateStoresOptionalAppDraftDesktopSpace() {
        let box = StudyBoxTemplateService.makeBox(
            template: .codingProject,
            name: "Compiler",
            resources: [
                OnboardingResourceDraft(
                    title: "Xcode",
                    type: .app,
                    urlString: "/Applications/Xcode.app",
                    appBundleID: "com.apple.dt.Xcode",
                    appPath: "/Applications/Xcode.app",
                    targetDesktopSpace: 3
                )
            ]
        )

        XCTAssertEqual(box.resources.first?.targetDesktopSpace, 3)
    }

    func testTemplateCreationUsesCustomizedTaskDrafts() {
        let dueDate = Date(timeIntervalSince1970: 1_000)
        let box = StudyBoxTemplateService.makeBox(
            template: .assignment,
            name: "Essay",
            dueDate: dueDate,
            taskDrafts: [
                TemplateTaskDraft(title: "Read the rubric", type: .assignment, priority: 3, estimatedMinutes: 15),
                TemplateTaskDraft(title: "Draft outline", type: .notes, priority: 2, estimatedMinutes: 30)
            ]
        )

        XCTAssertEqual(box.tasks.map(\.title), ["Read the rubric", "Draft outline"])
        XCTAssertEqual(box.tasks.map(\.type), [.assignment, .notes])
        XCTAssertEqual(box.tasks.map(\.priority), [3, 2])
        XCTAssertEqual(box.tasks.map(\.estimatedMinutes), [15, 30])
        XCTAssertTrue(box.tasks.allSatisfy { $0.dueDate == dueDate })
    }

    func testBlankBoxCreationTrimsNameAndFallsBackToUntitled() {
        let named = StudyBoxTemplateService.makeBlankBox(name: "  Physics  ")
        let untitled = StudyBoxTemplateService.makeBlankBox(name: "   ")

        XCTAssertEqual(named.name, "Physics")
        XCTAssertEqual(named.type, .course)
        XCTAssertTrue(named.tasks.isEmpty)
        XCTAssertTrue(named.resources.isEmpty)
        XCTAssertEqual(untitled.name, "Untitled Study Box")
    }

    func testAssignmentTemplateAppliesDueDateToAssignmentTasks() {
        let dueDate = Date(timeIntervalSince1970: 10_000)
        let box = StudyBoxTemplateService.makeBox(
            template: .assignment,
            name: "OS project",
            dueDate: dueDate
        )

        XCTAssertEqual(box.type, .assignment)
        XCTAssertEqual(box.examDate, dueDate)
        XCTAssertTrue(box.tasks.allSatisfy { $0.dueDate == dueDate })
    }

    func testNonAssignmentTemplatesKeepDueDateOnBoxOnlyUnlessFirstTaskProvided() {
        let dueDate = Date(timeIntervalSince1970: 20_000)
        let box = StudyBoxTemplateService.makeBox(
            template: .examPrep,
            name: "Final",
            dueDate: dueDate,
            firstTaskTitle: "Book room"
        )

        XCTAssertEqual(box.examDate, dueDate)
        XCTAssertTrue(box.tasks.filter { $0.title != "Book room" }.allSatisfy { $0.dueDate == nil })
        XCTAssertEqual(box.tasks.first { $0.title == "Book room" }?.dueDate, dueDate)
    }

    func testResumeStudySelectsMostRecentActiveBox() {
        let oldBox = StudyBox(name: "Old")
        let recentBox = StudyBox(name: "Recent")
        let archivedBox = StudyBox(name: "Archived", isArchived: true)

        let oldSession = StudySession(
            box: oldBox,
            startedAt: Date(timeIntervalSince1970: 100),
            plannedMinutes: 25
        )
        let recentSession = StudySession(
            box: recentBox,
            startedAt: Date(timeIntervalSince1970: 300),
            plannedMinutes: 25
        )
        let archivedSession = StudySession(
            box: archivedBox,
            startedAt: Date(timeIntervalSince1970: 500),
            plannedMinutes: 25
        )

        let selected = StudyResumeService.mostRecentlyStudiedBox(
            from: [oldBox, recentBox, archivedBox],
            sessions: [oldSession, recentSession, archivedSession]
        )

        XCTAssertEqual(selected?.id, recentBox.id)
    }

    func testResumeStudyFallsBackToMostRecentlyUpdatedActiveBoxWithoutSessions() {
        let older = StudyBox(
            name: "Older",
            updatedAt: Date(timeIntervalSince1970: 100)
        )
        let newer = StudyBox(
            name: "Newer",
            updatedAt: Date(timeIntervalSince1970: 200)
        )

        let selected = StudyResumeService.mostRecentlyStudiedBox(
            from: [older, newer],
            sessions: []
        )

        XCTAssertEqual(selected?.id, newer.id)
    }

    func testResumeStudyReturnsNilWhenOnlyArchivedBoxesExist() {
        let archived = StudyBox(name: "Archived", isArchived: true)

        XCTAssertNil(StudyResumeService.mostRecentlyStudiedBox(from: [archived], sessions: []))
    }

    func testResumeSnapshotIncludesUnfinishedTasksResourcesAndNotes() throws {
        let box = StudyBox(name: "Calculus")
        box.tasks = [
            StudyTask(box: box, title: "Done", status: .done),
            StudyTask(box: box, title: "Open", status: .pending, priority: 3)
        ]
        box.resources = [
            StudyResource(box: box, title: "PDF", type: .file, orderIndex: 0, enabledByDefault: true),
            StudyResource(box: box, title: "Notes", type: .notes, enabledByDefault: false)
        ]
        let session = StudySession(
            box: box,
            startedAt: Date(timeIntervalSince1970: 200),
            endedAt: Date(timeIntervalSince1970: 3200),
            plannedMinutes: 50,
            notes: "Next time: exercises 4-6."
        )

        let snapshot = try XCTUnwrap(StudyResumeService.snapshot(for: box, sessions: [session]))

        XCTAssertEqual(snapshot.boxID, box.id)
        XCTAssertEqual(snapshot.lastDurationMinutes, 50)
        XCTAssertEqual(snapshot.unfinishedTaskCount, 1)
        XCTAssertEqual(snapshot.enabledResourceCount, 1)
        XCTAssertEqual(snapshot.nextTaskTitle, "Open")
        XCTAssertEqual(snapshot.enabledResourceTitles, ["PDF"])
        XCTAssertEqual(snapshot.notesPreview, "Next time: exercises 4-6.")
    }

    func testResumeSnapshotReturnsNilWithoutSessionsAndDropsBlankNotes() throws {
        let box = StudyBox(name: "History")

        XCTAssertNil(StudyResumeService.snapshot(for: box, sessions: []))

        let session = StudySession(
            box: box,
            startedAt: Date(timeIntervalSince1970: 300),
            plannedMinutes: 25,
            notes: "   "
        )
        let snapshot = try XCTUnwrap(StudyResumeService.snapshot(for: box, sessions: [session]))

        XCTAssertNil(snapshot.notesPreview)
    }

    func testNextSuggestedTaskUsesTaskManagerSorting() {
        let box = StudyBox(name: "Algorithms")
        let low = StudyTask(box: box, title: "Low", priority: 1)
        let high = StudyTask(box: box, title: "High", priority: 3)
        let done = StudyTask(box: box, title: "Done", status: .done, priority: 9)
        box.tasks = [low, done, high]

        XCTAssertEqual(StudyResumeService.nextSuggestedTask(for: box)?.title, "High")
    }

    func testNextSuggestedTaskIgnoresDoneAndSkippedTasks() {
        let box = StudyBox(name: "Biology")
        box.tasks = [
            StudyTask(box: box, title: "Done", status: .done, priority: 9),
            StudyTask(box: box, title: "Skipped", status: .skipped, priority: 8)
        ]

        XCTAssertNil(StudyResumeService.nextSuggestedTask(for: box))
    }

    func testMenuBarDisplayModePersistsAndFallsBack() {
        let suiteName = "StudyBoxesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let preferences = UserPreferencesService(userDefaults: defaults)
        XCTAssertEqual(preferences.menuBarDisplayMode, .timer)

        preferences.menuBarDisplayMode = .boxNameAndTimer

        let reloaded = UserPreferencesService(userDefaults: defaults)
        XCTAssertEqual(reloaded.menuBarDisplayMode, .boxNameAndTimer)

        defaults.set("unknown", forKey: "menuBarDisplayMode")
        let fallback = UserPreferencesService(userDefaults: defaults)
        XCTAssertEqual(fallback.menuBarDisplayMode, .timer)
    }

    func testRestoreOnSessionEndSettingsCopyIsExplicitAndNonConfigurable() {
        XCTAssertEqual(FocusRestoreSettingsPresentation.title, "Restore on session end")
        XCTAssertEqual(
            FocusRestoreSettingsPresentation.body,
            "Study Boxes restores affected apps and window positions automatically after Quit Apps or Strict Focus sessions end. Hide Apps restores window positions best effort when Accessibility is available."
        )
        XCTAssertEqual(FocusRestoreSettingsPresentation.systemImage, "arrow.counterclockwise")
        XCTAssertFalse(FocusRestoreSettingsPresentation.isConfigurable)
    }

    func testProgressSummaryAggregatesLocalSessionAndTaskStats() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let monthStart = calendar.dateInterval(of: .month, for: now)!.start
        let box = StudyBox(name: "Physics")
        box.sessions = [
            StudySession(
                box: box,
                startedAt: weekStart.addingTimeInterval(60),
                endedAt: weekStart.addingTimeInterval(31 * 60),
                plannedMinutes: 25
            ),
            StudySession(
                box: box,
                startedAt: monthStart.addingTimeInterval(60),
                endedAt: monthStart.addingTimeInterval(46 * 60),
                plannedMinutes: 50
            )
        ]
        box.tasks = [
            StudyTask(box: box, title: "Week", status: .done, completedAt: weekStart.addingTimeInterval(120)),
            StudyTask(box: box, title: "Month", status: .done, completedAt: monthStart.addingTimeInterval(120))
        ]

        let summary = StudyProgressService.summary(for: box, now: now, calendar: calendar)

        XCTAssertEqual(summary.totalMinutes, 75)
        XCTAssertEqual(summary.weekMinutes, 30)
        XCTAssertEqual(summary.monthMinutes, 75)
        XCTAssertEqual(summary.completedTasksThisWeek, 1)
        XCTAssertEqual(summary.completedTasksThisMonth, 2)
        XCTAssertEqual(summary.averageSessionMinutes, 37)
        XCTAssertEqual(summary.lastStudiedAt, weekStart.addingTimeInterval(60))
    }

    func testSessionHistoryFiltersUseCurrentWeekAndMonth() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)!.start
        let previousMonth = calendar.date(byAdding: .month, value: -1, to: now)!

        XCTAssertTrue(SessionHistoryFilter.all.includes(previousMonth, now: now, calendar: calendar))
        XCTAssertTrue(SessionHistoryFilter.thisWeek.includes(weekStart.addingTimeInterval(60), now: now, calendar: calendar))
        XCTAssertFalse(SessionHistoryFilter.thisWeek.includes(previousMonth, now: now, calendar: calendar))
        XCTAssertFalse(SessionHistoryFilter.thisMonth.includes(previousMonth, now: now, calendar: calendar))
    }
}
