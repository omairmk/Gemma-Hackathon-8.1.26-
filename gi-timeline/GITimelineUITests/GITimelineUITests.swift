import XCTest

final class GITimelineUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    launchFakeGemma(withDeveloperTools: true)
    resetSyntheticEntriesIfPresent()
    app.terminate()
    launchFakeGemma(visualAccessibility: true)
  }

  override func tearDownWithError() throws {
    app?.terminate()
    app = nil
  }

  func testFirstRunExplainsTheReviewBeforeSave() throws {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-first-run",
      "-AppleInterfaceStyle", "Dark",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
    ]
    app.launch()

    XCTAssertTrue(app.staticTexts["GI Timeline"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.staticTexts["You review before saving"].exists)
    capture("01-first-run")
    let continueButton = app.buttons["firstRunContinue"]
    scrollToHittable(continueButton, direction: .up)
    continueButton.tap()
    let choosePhoto = app.buttons["choosePhoto"]
    XCTAssertTrue(choosePhoto.waitForExistence(timeout: 5), "Continuing should reveal the actual New Entry controls, not the view behind the first-run cover.")
    let coverDismissed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: continueButton)
    XCTAssertEqual(XCTWaiter.wait(for: [coverDismissed], timeout: 3), .completed, "The first-run cover should be dismissed before documenting New Entry.")
    scrollToHittable(choosePhoto, direction: .up)
    capture("02-new-entry")
  }

  func testReadingPhotoKeepsTheAttachedPhotoWhileAnalysisIsActive() throws {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-fake-gemma", "--ui-test-slow-fake-gemma",
      "-AppleInterfaceStyle", "Dark",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
    ]
    app.launch()

    let brownDemo = app.buttons["demoBrown"]
    XCTAssertTrue(brownDemo.waitForExistence(timeout: 5))
    brownDemo.tap()

    XCTAssertTrue(app.staticTexts["Reading photo"].waitForExistence(timeout: 3), "Attaching a photo should move directly into the reading state.")
    capture("03-reading-photo")

    let cancel = app.buttons["cancelReading"]
    XCTAssertTrue(cancel.isHittable)
    cancel.tap()
    XCTAssertTrue(app.staticTexts["Couldn’t read photo"].waitForExistence(timeout: 3))
    capture("08-reading-error")
    let retry = app.buttons["retryReading"]
    scrollToHittable(retry, direction: .up)
    XCTAssertTrue(retry.isHittable, "Cancelling should preserve the selected photo and a reachable retry path.")
  }

  func testAutomaticDemoReviewPersistsAndDeletes() throws {
    app.terminate()
    app = XCUIApplication()
    launchFakeGemma(visualAccessibility: true)

    assertNormalEntryUIHasNoInferenceControls()

    let brownDemo = app.buttons["demoBrown"]
    XCTAssertTrue(brownDemo.waitForExistence(timeout: 5), "The deterministic Brown fixture should be available only to the UI test provider.")
    brownDemo.tap()

    XCTAssertFalse(app.buttons["Analyze with Gemma"].exists, "There must be no manual inference action between choosing the photo and reviewing it.")
    XCTAssertTrue(app.staticTexts["Review entry"].waitForExistence(timeout: 12), "The fake provider should move automatically from the reading state to review.")
    capture("04-review-entry")

    let save = app.buttons["saveEntry"]
    scrollToHittable(save, direction: .up)
    XCTAssertFalse(save.isEnabled, "All five suggested fields must be explicitly reviewed before Save is enabled.")

    editApparentColorToGreen()
    XCTAssertTrue(app.staticTexts["Edited"].waitForExistence(timeout: 3), "Changing a suggested value must visibly mark that field as edited.")

    let confirmRemaining = app.buttons["uiTestConfirmRemaining"]
    scrollToHittable(confirmRemaining, direction: .up)
    confirmRemaining.tap()

    scrollToHittable(save, direction: .up)
    XCTAssertTrue(save.isEnabled, "Save should become available only after the fifth review decision.")
    save.tap()

    XCTAssertTrue(app.staticTexts["Entry saved"].waitForExistence(timeout: 5))
    capture("05-saved")
    let viewEntry = app.buttons["viewSavedEntry"]
    XCTAssertTrue(viewEntry.isHittable)
    viewEntry.tap()
    verifyEditedDetail()

    app.terminate()
    launchFakeGemma()
    openTab("History")
    XCTAssertTrue(app.staticTexts["History"].waitForExistence(timeout: 5))
    let persistedSummary = app.staticTexts["historyEntrySummary"].firstMatch
    XCTAssertTrue(persistedSummary.waitForExistence(timeout: 5), "The relaunched History row should retain the reviewed observation.")
    XCTAssertTrue(persistedSummary.isHittable, "The History summary must remain readable at the configured Dynamic Type size.")
    XCTAssertTrue(persistedSummary.label.localizedCaseInsensitiveContains("green"), "The edited color must survive save and relaunch.")
    capture("06-history")
    openNewestHistoryEntry()
    verifyEditedDetail()
    let apparentColor = app.staticTexts["detailValue.Apparent color"]
    XCTAssertTrue(apparentColor.waitForExistence(timeout: 5), "The saved observation value should remain exposed as its own readable detail row.")
    scrollToHittable(apparentColor, direction: .up)
    scrollDetailToTop()
    capture("07-entry-detail")

    let delete = app.buttons["deleteEntry"]
    XCTAssertTrue(delete.waitForExistence(timeout: 5))
    delete.tap()
    let confirmation = app.buttons.matching(NSPredicate(format: "label == %@", "Delete")).firstMatch
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3), "Deleting an entry should require confirmation.")
    confirmation.tap()
    XCTAssertTrue(app.staticTexts["No entries yet"].waitForExistence(timeout: 5), "The test must remove its synthetic entry before finishing.")
  }

  private func launchFakeGemma(withDeveloperTools: Bool = false, visualAccessibility: Bool = false) {
    app.launchArguments = ["--ui-test-fake-gemma"]
      + (withDeveloperTools ? ["--show-developer-tools"] : [])
      + (visualAccessibility ? [
        "-AppleInterfaceStyle", "Dark",
        "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
      ] : [])
    app.launch()
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func assertNormalEntryUIHasNoInferenceControls() {
    XCTAssertFalse(app.buttons["Analyze with Gemma"].exists)
    XCTAssertFalse(app.buttons["analyzeWithGemma"].exists)
    XCTAssertFalse(app.buttons["Prepare Gemma"].exists)
    XCTAssertFalse(app.buttons["Import model"].exists)
    XCTAssertFalse(app.staticTexts["runtimeBadge"].exists)
    XCTAssertFalse(app.staticTexts["Gemma"].exists)
  }

  private func editApparentColorToGreen() {
    let field = app.buttons["reviewField.apparentColor"]
    scrollToHittable(field, direction: .down)
    field.tap()

    let colorPicker = app.descendants(matching: .any)["reviewPicker.apparentColor"]
    XCTAssertTrue(colorPicker.waitForExistence(timeout: 3), "The Apparent color review card should expose its native picker.")
    colorPicker.tap()

    let green = app.buttons.matching(NSPredicate(format: "label ==[c] %@", "Green")).firstMatch
    XCTAssertTrue(green.waitForExistence(timeout: 3), "The native picker should include Green as a distinct reviewed value.")
    green.tap()
  }

  private func openTab(_ name: String) {
    let tab = app.tabBars.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing \(name) tab.")
    tab.tap()
  }

  private func openNewestHistoryEntry() {
    let entry = app.buttons["historyEntry"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 5), "The saved synthetic entry should appear in History.")
    scrollToHittable(entry, direction: .down)
    entry.tap()
  }

  private func verifyEditedDetail() {
    XCTAssertTrue(app.navigationBars["Entry detail"].waitForExistence(timeout: 5), "The saved entry detail should open.")
    let edited = app.staticTexts["Edited during review"]
    scrollToHittable(edited, direction: .up)
    XCTAssertTrue(edited.exists, "The user's review edit must persist as edited provenance.")
  }

  private func scrollDetailToTop() {
    let detail = app.scrollViews["entryDetail"]
    XCTAssertTrue(detail.waitForExistence(timeout: 3), "The entry detail should remain scrollable at the configured Dynamic Type size.")
    for _ in 0..<4 { detail.swipeDown() }
  }

  private func resetSyntheticEntriesIfPresent() {
    openTab("History")
    let reset = app.buttons["resetDemo"]
    guard reset.waitForExistence(timeout: 2) else { return }
    reset.tap()
    let confirmation = app.sheets.buttons["Reset Demo"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3), "Reset Demo should request destructive confirmation.")
    confirmation.tap()
  }

  private enum ScrollDirection { case up, down }

  private func scrollToHittable(_ element: XCUIElement, direction: ScrollDirection) {
    for _ in 0..<12 where !element.isHittable {
      let scrollable = app.scrollViews.firstMatch.exists
        ? app.scrollViews.firstMatch
        : app.collectionViews.firstMatch
      switch direction {
      case .up:
        if scrollable.exists { scrollable.swipeUp() } else { app.swipeUp() }
      case .down:
        if scrollable.exists { scrollable.swipeDown() } else { app.swipeDown() }
      }
    }
    XCTAssertTrue(element.isHittable, "Element \(element.identifier) exists but could not be scrolled into view.")
  }
}
