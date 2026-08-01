import XCTest

final class GITimelineUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["--ui-test-fake-gemma"]
    app.launch()
  }

  override func tearDownWithError() throws {
    app?.terminate()
    app = nil
  }

  func testDeterministicDemoReviewPersistsAndResets() throws {
    openTab("History")
    resetSyntheticEntriesIfPresent()

    openTab("New Entry")
    let badge = app.staticTexts["runtimeBadge"]
    XCTAssertTrue(badge.waitForExistence(timeout: 5), "The runtime truth badge must be visible.")
    XCTAssertEqual(badge.label, "UI demo · Gemma not connected")

    let brownDemo = app.buttons["demoBrown"]
    makeHittable(brownDemo, direction: .up)
    brownDemo.tap()

    let analyze = app.buttons["analyzeWithGemma"]
    makeHittable(analyze, direction: .up)
    XCTAssertTrue(analyze.isEnabled, "Fake inference should be ready only under the explicit UI-test launch argument.")
    analyze.tap()

    let imageUsable = app.segmentedControls["reviewImageUsable"]
    XCTAssertTrue(imageUsable.waitForExistence(timeout: 10), "The editable reviewed result should appear after deterministic analysis.")
    makeHittable(imageUsable, direction: .up)
    let noSegment = imageUsable.buttons["No"]
    XCTAssertTrue(noSegment.exists, "Image usable must expose an editable No segment.")
    noSegment.tap()
    XCTAssertTrue(noSegment.isSelected, "The reviewed AI field should record the user's edit.")

    let save = app.buttons["saveEntry"]
    makeHittable(save, direction: .up)
    XCTAssertEqual(save.label, "Save Reviewed Entry")
    XCTAssertTrue(save.isEnabled)
    save.tap()

    openTab("History")
    openNewestHistoryEntry()
    verifyEditedDetail()

    app.terminate()
    app.launch()
    openTab("History")
    openNewestHistoryEntry()
    verifyEditedDetail()

    app.navigationBars["Entry"].buttons["History"].tap()
    resetSyntheticEntriesIfPresent(required: true)
    XCTAssertFalse(app.buttons["resetDemo"].waitForExistence(timeout: 2), "Reset Demo should remove only the synthetic entries created by the smoke test.")
  }

  private func openTab(_ name: String) {
    let tab = app.tabBars.buttons[name]
    XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing \(name) tab.")
    tab.tap()
  }

  private func openNewestHistoryEntry() {
    let entry = app.buttons["historyEntry"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 5), "The saved synthetic entry should appear in History.")
    makeHittable(entry, direction: .down)
    entry.tap()
  }

  private func verifyEditedDetail() {
    XCTAssertTrue(app.navigationBars["Entry"].waitForExistence(timeout: 5), "The saved entry detail should open.")
    let edited = app.staticTexts.matching(NSPredicate(format: "label == %@", "(edited)")).firstMatch
    makeHittable(edited, direction: .up)
    XCTAssertTrue(edited.exists, "The user's review edit must persist as edited provenance.")
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "UI demo observation, reviewed by you")).firstMatch.exists)
    XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label == %@", "UI demo · Gemma not connected")).firstMatch.exists)
  }

  private func resetSyntheticEntriesIfPresent(required: Bool = false) {
    let reset = app.buttons["resetDemo"]
    guard reset.waitForExistence(timeout: required ? 5 : 1) else {
      XCTAssertFalse(required, "The synthetic entry should expose Reset Demo.")
      return
    }
    reset.tap()
    let confirmation = app.sheets.buttons["Reset Demo"]
    XCTAssertTrue(confirmation.waitForExistence(timeout: 3), "Reset Demo should request destructive confirmation.")
    confirmation.tap()
  }

  private enum ScrollDirection { case up, down }

  private func makeHittable(_ element: XCUIElement, direction: ScrollDirection) {
    for _ in 0..<10 where !element.isHittable {
      let scrollable = app.collectionViews.firstMatch
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
