import XCTest

private func waitForAccessibilityValue(
  _ expectedValue: String,
  on element: XCUIElement,
  timeout: TimeInterval = 3
) -> Bool {
  let predicate = NSPredicate(format: "value == %@", expectedValue)
  let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
  return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
}

@available(iOS 17.0, *)
private func assertNoAccessibilityAuditIssues(
  in app: XCUIApplication,
  activityName: String,
  file: StaticString = #filePath,
  line: UInt = #line
) throws {
  let auditPasses: [(name: String, types: XCUIAccessibilityAuditType)] = [
    (
      "visual and semantic",
      [.contrast, .elementDetection, .hitRegion, .sufficientElementDescription, .trait]
    ),
    // Run resizing separately. Combining Dynamic Type mutation and pixel
    // contrast sampling lets XCTest sample SwiftUI's size-transition frames,
    // which can report compliant text as faded during the transition.
    ("text resizing", [.dynamicType, .textClipped]),
  ]
  for auditPass in auditPasses {
    try XCTContext.runActivity(named: "\(activityName) — \(auditPass.name)") { _ in
      try app.performAccessibilityAudit(for: auditPass.types) { issue in
        // XCTest flags the private UIKit compact-time-label implementation even
        // when the app supplies no visual styling for it. Keep this exception
        // exact: every app-owned audit issue still fails the test below.
        if isSystemOwnedCompactDatePickerContrastIssue(issue) {
          return true
        }
        // XCTest also samples SwiftUI text that is laid out below the visible
        // scroll viewport, including content covered by the tab bar. Contrast
        // for that text is audited again after the test scrolls it fully into
        // the unobscured viewport. Never waive a visible app-owned element.
        if isContrastIssueForObscuredElement(issue, in: app) {
          return true
        }
        // Element Detection can report the same clipped line without returning
        // an element. Accept only that exact OCR finding while the hierarchy
        // proves that text crosses the tab-bar boundary; visible OCR findings
        // and every finding with an element remain failures.
        if isElementDetectionForObscuredText(issue, in: app) {
          return true
        }
        let elementDetails: String
        if let element = issue.element {
          elementDetails = "type=\(element.elementType) identifier=\(element.identifier) label=\(element.label) value=\(String(describing: element.value)) frame=\(element.frame)"
        } else {
          elementDetails = "element unavailable"
        }
        XCTFail(
          "\(issue.compactDescription): \(issue.detailedDescription) [\(elementDetails)]",
          file: file,
          line: line
        )
        return true
      }
    }
  }
}

@available(iOS 17.0, *)
private func isSystemOwnedCompactDatePickerContrastIssue(_ issue: XCUIAccessibilityAuditIssue) -> Bool {
  issue.auditType == .contrast
    && issue.compactDescription == "Contrast failed"
    && issue.detailedDescription.contains("_UIDatePickerCompactTimeLabel")
    && issue.element?.identifier.isEmpty != false
}

private let scrollEdgeFadeInset: CGFloat = 48

@available(iOS 17.0, *)
private func isContrastIssueForObscuredElement(
  _ issue: XCUIAccessibilityAuditIssue,
  in app: XCUIApplication
) -> Bool {
  guard issue.auditType == .contrast,
    let frame = issue.element?.frame,
    !["saveEntry", "saveEntryDisabledReason"].contains(issue.element?.identifier ?? ""),
    let bounds = unobscuredVerticalBounds(in: app)
  else { return false }
  if frame.minY < bounds.top || frame.maxY > bounds.bottom {
    return true
  }
  // iOS 26 renders content that sits just inside the nav bar/tab bar edges
  // through the scroll-edge effect, fading or glassing it rather than
  // clipping it outright. XCTest still samples that faded pixel band and
  // reports it as a contrast failure even though the element is nominally
  // within the unobscured bounds. Waive it here; any such element is
  // re-audited once the test scrolls it clear of the edge band.
  return frame.minY < bounds.top + scrollEdgeFadeInset
    || frame.maxY > bounds.bottom - scrollEdgeFadeInset
}

@available(iOS 17.0, *)
private func isElementDetectionForObscuredText(
  _ issue: XCUIAccessibilityAuditIssue,
  in app: XCUIApplication
) -> Bool {
  guard issue.auditType == .elementDetection,
    issue.element == nil,
    issue.compactDescription == "Potentially inaccessible text",
    issue.detailedDescription == "This element appears to display text that should be represented using the accessibility API.",
    let bounds = unobscuredVerticalBounds(in: app)
  else { return false }
  return app.staticTexts.allElementsBoundByIndex.contains { element in
    let frame = element.frame
    return (frame.minY < bounds.top || frame.maxY > bounds.bottom)
      && frame.maxY > app.frame.minY
      && frame.minY < app.frame.maxY
  }
}

private func unobscuredVerticalBounds(in app: XCUIApplication) -> (top: CGFloat, bottom: CGFloat)? {
  var top = app.frame.minY
  var bottom = app.frame.maxY
  let navigationBar = app.navigationBars.firstMatch
  if navigationBar.exists, !navigationBar.frame.isEmpty {
    top = max(top, navigationBar.frame.maxY)
  }
  let tabBar = app.tabBars.firstMatch
  if tabBar.exists, !tabBar.frame.isEmpty {
    bottom = min(bottom, tabBar.frame.minY)
  }
  let stickySave = app.buttons["saveEntry"]
  if stickySave.exists, !stickySave.frame.isEmpty {
    bottom = min(bottom, stickySave.frame.minY)
  }
  guard top < bottom else { return nil }
  return (top, bottom)
}

#if DEBUG
final class GITimelineUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUpWithError() throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-fake-gemma", "--skip-first-run", "--ui-test-ephemeral-store",
      "--ui-preview-dark",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
    ]
    app.launch()
  }

  override func tearDownWithError() throws {
    app?.terminate()
    app = nil
  }

  func testGIJournalUsesCurrentPatientFacingLogAndManualEntryPath() throws {
    XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.tabBars.buttons["Journal"].exists)
    XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    XCTAssertFalse(app.tabBars.buttons["Progress"].exists)
    XCTAssertTrue(app.staticTexts["Add to your journal"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.staticTexts["Add a photo (optional)"].exists)
    XCTAssertTrue(app.buttons["logWithoutPhoto"].exists)

    app.buttons["logWithoutPhoto"].tap()
    XCTAssertTrue(app.staticTexts["Review your entry"].waitForExistence(timeout: 3))
    XCTAssertTrue(app.staticTexts["Details you noticed"].exists)
    XCTAssertTrue(app.staticTexts["Does the photo clearly show the bowel movement?"].exists == false)

    let save = app.buttons["saveEntry"]
    XCTAssertTrue(save.exists)
    XCTAssertFalse(save.isEnabled)

    let type4 = app.buttons["Type 4 — smooth and formed"]
    XCTAssertTrue(scrollUntilHittable(type4, above: save))
    XCTAssertEqual(type4.value as? String, "Not selected")
    type4.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: type4))

    for identifier in ["mixedForm_no", "redMaterial_no", "blackTarry_no"] {
      let answer = app.buttons[identifier]
      XCTAssertTrue(scrollUntilHittable(answer, above: save))
      answer.tap()
      XCTAssertTrue(waitForAccessibilityValue("Selected", on: answer))
    }
    XCTAssertTrue(save.isEnabled)
    XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label == %@", "Save entry")).count, 1)
    capture("manual-entry-dark-axxl")
    save.tap()
    XCTAssertTrue(app.staticTexts["Entry saved"].waitForExistence(timeout: 8))
  }

  func testJournalMarkedEmptyStateAndDatedNoBowelMovementMarkerAreAccessible() throws {
    app.tabBars.buttons["Journal"].tap()
    XCTAssertTrue(app.staticTexts["Journal"].waitForExistence(timeout: 5))
    let filter = app.segmentedControls.firstMatch
    XCTAssertTrue(filter.waitForExistence(timeout: 3))
    filter.buttons["Marked"].tap()
    XCTAssertTrue(app.staticTexts["No marked entries"].waitForExistence(timeout: 3))
    capture("marked-empty-dark-axxl")

    app.tabBars.buttons["Log"].tap()
    let noBowelMovement = app.buttons["recordNoBowelMovement"]
    XCTAssertTrue(noBowelMovement.waitForExistence(timeout: 3))
    noBowelMovement.tap()
    XCTAssertTrue(app.navigationBars["No bowel movement"].waitForExistence(timeout: 3))
    let saveMarker = app.buttons["saveNoBowelMovement"]
    XCTAssertTrue(saveMarker.waitForExistence(timeout: 3))
    saveMarker.tap()
    XCTAssertTrue(app.descendants(matching: .any)["noBowelMovementStatus"].waitForExistence(timeout: 3))

    app.tabBars.buttons["Journal"].tap()
    filter.buttons["All"].tap()
    XCTAssertTrue(app.descendants(matching: .any)["noBowelMovementJournalMarker"].waitForExistence(timeout: 3))
  }

  func testLoadingAndManualFallbackEvidenceAreAccessible() throws {
    relaunch([
      "--ui-test-fake-gemma", "--skip-first-run", "--ui-test-ephemeral-store",
      "--ui-test-slow-fake-gemma", "--ui-preview-analyzing",
      "--ui-preview-dark"
    ])
    let readingStatus = app.descendants(matching: .any)["readingPhotoHero"]
    XCTAssertTrue(readingStatus.waitForExistence(timeout: 5))
    XCTAssertEqual(readingStatus.label, "Preparing a suggestion")
    XCTAssertFalse(app.descendants(matching: .any)["readingObservationSkeletons"].exists)
    capture("loading-photo-dark")

    relaunch([
      "--ui-test-fake-gemma", "--skip-first-run", "--ui-test-ephemeral-store",
      "--ui-test-inference-failure", "--ui-preview-error",
      "--ui-preview-dark"
    ])
    XCTAssertTrue(app.descendants(matching: .any)["manualSuggestionFallback"].waitForExistence(timeout: 8))
    capture("suggestion-fallback-dark")
  }

  func testLowQualityRetakeRecommendationKeepsPhotoForManualContinuation() throws {
    relaunch([
      "--ui-test-fake-gemma", "--skip-first-run", "--ui-test-ephemeral-store",
      "--ui-test-low-quality-retake"
    ])

    let recommendation = app.descendants(matching: .any)[
      "lowPhotoQualityRecommendation"
    ]
    XCTAssertTrue(recommendation.waitForExistence(timeout: 8))
    XCTAssertEqual(
      recommendation.label,
      "This photo may be too dark to provide useful suggestions. Taking another photo in more even light may improve the results."
    )
    XCTAssertTrue(app.descendants(matching: .any)["lowQualityRetainedPhoto"].exists)
    XCTAssertTrue(app.buttons["takeAnotherLowQualityPhoto"].exists)
    XCTAssertEqual(app.buttons["takeAnotherLowQualityPhoto"].label, "Take another photo")

    let manual = app.buttons["keepLowQualityPhotoManual"]
    XCTAssertTrue(manual.exists)
    XCTAssertEqual(manual.label, "Keep photo and continue manually")
    manual.tap()

    XCTAssertTrue(app.staticTexts["Review your entry"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["reviewPhoto"].exists)
    let fallback = app.descendants(matching: .any)["manualSuggestionFallback"]
    XCTAssertTrue(fallback.exists)
    XCTAssertTrue(fallback.label.contains("photo will remain with the saved entry and PDF"))

    let subject = app.descendants(matching: .any)[
      "providerNeutralManualSubject"
    ]
    XCTAssertTrue(scrollUntilHittable(subject))
    XCTAssertEqual(subject.value as? String, "Not sure")

    let color = app.descendants(matching: .any)[
      "providerNeutralManualApparentColor"
    ]
    XCTAssertTrue(scrollUntilHittable(color))
    XCTAssertEqual(color.value as? String, "Unable To Assess")

    let usabilityNo = app.buttons["providerNeutralManualPhotoUsability_no"]
    XCTAssertTrue(scrollUntilHittable(usabilityNo))
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: usabilityNo))

    let retake = app.descendants(matching: .any)[
      "providerNeutralManualRetakeReason"
    ]
    XCTAssertTrue(scrollUntilHittable(retake))
    XCTAssertEqual(retake.value as? String, "Too dark")

    let form = app.descendants(matching: .any)["providerNeutralManualForm"]
    XCTAssertTrue(scrollUntilHittable(form))
    XCTAssertEqual(form.value as? String, "Unable to tell")
    XCTAssertTrue(waitForAccessibilityValue(
      "Selected",
      on: app.buttons.matching(
        NSPredicate(format: "label == %@", "Unable to tell")
      ).firstMatch
    ))
    for identifier in [
      "mixedForm_unsure", "redMaterial_unsure",
      "blackAppearance_unsure", "blackTarry_unsure",
    ] {
      let control = app.buttons[identifier]
      XCTAssertTrue(scrollUntilHittable(control), identifier)
      XCTAssertTrue(waitForAccessibilityValue("Selected", on: control), identifier)
    }

    // Every conservative prefill is editable in the same provider-neutral
    // manual sheet. Clear the retake recommendation, then choose concrete
    // person-entered values across the complete tuple.
    XCTAssertTrue(scrollUntilHittable(retake))
    retake.tap()
    let noRetake = app.buttons["No retake recommended"]
    XCTAssertTrue(noRetake.waitForExistence(timeout: 3))
    noRetake.tap()
    let usabilityYes = app.buttons["providerNeutralManualPhotoUsability_yes"]
    XCTAssertTrue(scrollUntilHittable(usabilityYes))
    usabilityYes.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: usabilityYes))

    XCTAssertTrue(scrollUntilHittable(subject))
    subject.tap()
    XCTAssertTrue(app.buttons["Bowel movement"].waitForExistence(timeout: 3))
    app.buttons["Bowel movement"].tap()

    XCTAssertTrue(scrollUntilHittable(color))
    color.tap()
    XCTAssertTrue(app.buttons["Yellow"].waitForExistence(timeout: 3))
    app.buttons["Yellow"].tap()

    XCTAssertTrue(scrollUntilHittable(form))
    form.tap()
    XCTAssertTrue(app.buttons["Soft Blobs"].waitForExistence(timeout: 3))
    app.buttons["Soft Blobs"].tap()
    XCTAssertTrue(waitForAccessibilityValue("Soft Blobs", on: form))

    for (identifier, value) in [
      ("mixedForm_no", "Selected"),
      ("redMaterial_yes", "Selected"),
      ("blackAppearance_no", "Selected"),
      ("blackTarry_yes", "Selected"),
    ] {
      let control = app.buttons[identifier]
      XCTAssertTrue(scrollUntilHittable(control), identifier)
      control.tap()
      XCTAssertTrue(waitForAccessibilityValue(value, on: control), identifier)
    }
  }

  func testSyntheticEvidenceFlowInLightMode() throws {
    try captureSyntheticEvidenceFlow(style: "Light", suffix: "light")
  }

  func testSyntheticEvidenceFlowInDarkMode() throws {
    try captureSyntheticEvidenceFlow(style: "Dark", suffix: "dark")
  }

  func testGemmaFullPrefillIsEditableBeforeOneSaveAction() throws {
    relaunch([
      "--ui-test-fake-gemma", "--ui-test-full-prefill-candidate",
      "--skip-first-run", "--ui-test-ephemeral-store"
    ])
    let brownFixture = app.buttons["demoBrown"]
    XCTAssertTrue(scrollUntilHittable(brownFixture))
    brownFixture.tap()

    XCTAssertTrue(app.staticTexts["Review your entry"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.descendants(matching: .any)["photoSuggestionDisclosure"].exists)
    XCTAssertTrue(app.staticTexts["Suggested: Type 4 — smooth and formed"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["apparentColor"].exists)
    XCTAssertTrue(app.descendants(matching: .any)["stoolPresenceSuggestion"].exists)
    XCTAssertTrue(scrollUntilHittable(app.descendants(matching: .any)["formSuggestion"]))
    XCTAssertTrue(scrollUntilHittable(app.staticTexts["Possible red/blood-like appearance"]))
    XCTAssertTrue(scrollUntilHittable(app.staticTexts["Possible black/tar-like appearance"]))
    XCTAssertFalse(app.descendants(matching: .any)["subjectConfirmationQuestion"].exists)
    XCTAssertEqual(app.buttons.matching(NSPredicate(
      format: "label == %@", "Accept all suggestions and save"
    )).count, 1)
    let save = app.buttons["saveEntry"]
    XCTAssertTrue(save.isEnabled)
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: app.buttons["redMaterial_yes"]))
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: app.buttons["blackTarry_unsure"]))
    let redNo = app.buttons["redMaterial_no"]
    redNo.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: redNo))
    XCTAssertTrue(save.isEnabled)
  }

  func testFullPrefillCandidateHasNoPerFieldConfirmationGate() throws {
    relaunch([
      "--ui-test-fake-gemma", "--ui-test-full-prefill-candidate",
      "--skip-first-run", "--ui-test-ephemeral-store",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraLarge"
    ])
    let brownFixture = app.buttons["demoBrown"]
    XCTAssertTrue(scrollUntilHittable(brownFixture))
    brownFixture.tap()

    XCTAssertTrue(app.staticTexts["Review your entry"].waitForExistence(timeout: 8))
    XCTAssertFalse(app.descendants(matching: .any)["subjectConfirmationQuestion"].exists)
    for identifier in [
      "subjectConfirmationYes", "subjectConfirmationNo",
      "subjectConfirmationNotClear",
    ] {
      XCTAssertFalse(app.buttons[identifier].exists)
    }
    XCTAssertTrue(scrollUntilHittable(app.buttons["saveEntry"]))
    XCTAssertTrue(app.buttons["saveEntry"].isEnabled)
    XCTAssertEqual(app.buttons["saveEntry"].label, "Accept all suggestions and save")
  }

  func testSeededJournalEntryCanBeEditedThroughOrdinaryUI() throws {
    relaunch([
      "--ui-test-fake-gemma", "--skip-first-run", "--ui-test-ephemeral-store",
      "--ui-test-seed-journal"
    ])

    app.tabBars.buttons["Journal"].tap()
    let entry = app.buttons["journalEntry"].firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 8))
    entry.tap()
    XCTAssertTrue(app.navigationBars["Journal entry"].waitForExistence(timeout: 5))
    let edit = app.buttons["editEntry"]
    XCTAssertTrue(edit.waitForExistence(timeout: 3))
    edit.tap()
    XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
    let type7 = app.buttons["Type 7 — watery, with no solid pieces"]
    XCTAssertTrue(scrollUntilHittable(type7))
    type7.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: type7))
    let save = app.buttons["saveEntryChanges"]
    XCTAssertTrue(scrollUntilHittable(save))
    save.tap()
    let updated = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Type 7 — watery, with no solid pieces")
    ).firstMatch
    XCTAssertTrue(updated.waitForExistence(timeout: 5))
  }

  private func captureSyntheticEvidenceFlow(style: String, suffix: String) throws {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = [
      "--ui-test-fake-gemma", "--skip-first-run", "--ui-test-ephemeral-store",
      "--ui-test-seed-journal", "--show-history",
      style == "Dark" ? "--ui-preview-dark" : "--ui-preview-light",
      "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"
    ]
    app.launch()

    let firstEntry = app.buttons["journalEntry"].firstMatch
    XCTAssertTrue(firstEntry.waitForExistence(timeout: 8))
    capture("after-journal-\(suffix)")

    firstEntry.tap()
    XCTAssertTrue(app.navigationBars["Journal entry"].waitForExistence(timeout: 5))
    capture("after-detail-\(suffix)")
    app.navigationBars["Journal entry"].buttons.firstMatch.tap()

    let journalHelp = app.buttons["Help and About"]
    XCTAssertTrue(journalHelp.waitForExistence(timeout: 4))
    journalHelp.tap()
    XCTAssertTrue(app.navigationBars["Help & About"].waitForExistence(timeout: 4))
    capture("after-help-\(suffix)")
    app.buttons["Done"].tap()

    app.tabBars.buttons["Journal"].tap()
    app.buttons["Export PDF"].tap()
    XCTAssertTrue(app.navigationBars["Export journal"].waitForExistence(timeout: 4))
    capture("after-pdf-export-\(suffix)")
    app.buttons["Create PDF"].tap()
    XCTAssertTrue(app.navigationBars["PDF preview"].waitForExistence(timeout: 10))
    capture("after-pdf-preview-\(suffix)")
    app.buttons["Done"].tap()
    app.buttons["Cancel"].tap()

    app.tabBars.buttons["Log"].tap()
    XCTAssertTrue(app.staticTexts["Add to your journal"].waitForExistence(timeout: 5))
    capture("after-log-\(suffix)")
  }

  private func capture(_ name: String) {
    let attachment = XCTAttachment(screenshot: app.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  private func relaunch(_ arguments: [String]) {
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = arguments
    app.launch()
  }

  @discardableResult
  private func scrollUntilHittable(
    _ element: XCUIElement,
    above footer: XCUIElement? = nil,
    maxSwipes: Int = 12
  ) -> Bool {
    _ = element.waitForExistence(timeout: 2)
    // swipeUp() carries scroll momentum, so a blind swipe loop can jump past
    // a short row between two checks and then keeps scrolling the wrong way
    // forever (the row ends up just above the viewport, exists == true,
    // isHittable == false). But momentum is also what lets twelve iterations
    // cover an accessibility-XXL form several screens tall. So: while the
    // target is far away (or not in the tree yet), keep the momentum swipe,
    // aimed toward the target when its frame is known; once it is within
    // about a screen and a half, switch to a slow momentum-free press-drag
    // that cannot overshoot. Success additionally requires the element to
    // sit near the vertical center of the window: near the edges an element
    // can be AX-hittable through a decorative overlay (the pinned save
    // footer's gradient) while a real synthesized touch never reaches it,
    // which reads as "tap succeeded, value never changed".
    let window = app.windows.firstMatch
    func settled() -> Bool {
      guard element.exists, element.isHittable else { return false }
      let footerFrame: CGRect? = {
        guard let footer, footer.exists, !footer.frame.isEmpty else { return nil }
        return footer.frame
      }()
      if let footerFrame {
        guard !element.frame.isEmpty else { return false }
        guard element.frame.maxY <= footerFrame.minY - 8 else { return false }
      }
      guard !window.frame.isEmpty else { return true }
      let height = window.frame.height
      return abs(element.frame.midY - window.frame.midY) <= 0.35 * height
        || element.frame.height > 0.5 * height
        || (footerFrame.map { element.frame.maxY <= $0.minY - 24 } ?? false)
    }
    if settled() { return true }
    for _ in 0..<maxSwipes {
      if element.exists, !window.frame.isEmpty {
        let delta = element.frame.midY - window.frame.midY
        if abs(delta) <= window.frame.height * 1.5 {
          let start = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
          )
          let dy: CGFloat = delta > 0
            ? -0.35 * window.frame.height
            : 0.35 * window.frame.height
          start.press(
            forDuration: 0.05,
            thenDragTo: start.withOffset(CGVector(dx: 0, dy: dy))
          )
        } else if delta > 0 {
          app.swipeUp()
        } else {
          app.swipeDown()
        }
      } else {
        app.swipeUp()
      }
      if settled() { return true }
    }
    return footer == nil ? (element.exists && element.isHittable) : settled()
  }
}
#elseif RELEASE_FALLBACK_TESTING
/// Exercises the optimized, model-free internal Release configuration. It
/// launches without test hooks and confirms that manual journaling remains
/// reachable when no embedded model is present.
final class GITimelineReleaseFallbackUITests: XCTestCase {
  func testModelFreeReleaseKeepsPublicManualRouteReachableWithoutHooks() throws {
    let app = XCUIApplication()
    app.launchArguments = [
      "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
    ]
    app.launch()

    let continueButton = app.buttons["Continue"]
    if continueButton.waitForExistence(timeout: 3) {
      continueButton.tap()
    }

    XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.tabBars.buttons["Journal"].exists)
    XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    XCTAssertFalse(app.buttons["openDeveloperTools"].exists)

    let manual = app.buttons["logWithoutPhoto"]
    XCTAssertTrue(manual.waitForExistence(timeout: 5))
    manual.tap()
    XCTAssertTrue(app.staticTexts["Review your entry"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["manualSuggestionFallback"].exists)

    let type4 = app.buttons["Type 4 — smooth and formed"]
    XCTAssertTrue(scrollUntilHittable(type4, in: app))
    XCTAssertEqual(type4.value as? String, "Not selected")
    type4.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: type4))
    let save = app.buttons["saveEntry"]
    XCTAssertFalse(save.isEnabled)
    for identifier in ["mixedForm_no", "redMaterial_no", "blackTarry_no"] {
      let answer = app.buttons[identifier]
      XCTAssertTrue(scrollUntilHittable(answer, in: app))
      answer.tap()
      XCTAssertTrue(waitForAccessibilityValue("Selected", on: answer))
    }
    XCTAssertTrue(save.isEnabled)
    XCTAssertEqual(save.label, "Save entry")
    save.tap()
    XCTAssertTrue(app.staticTexts["Entry saved"].waitForExistence(timeout: 8))
  }

  @discardableResult
  private func scrollUntilHittable(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 12
  ) -> Bool {
    if element.waitForExistence(timeout: 2), element.isHittable { return true }
    for _ in 0..<maxSwipes {
      app.swipeUp()
      if element.exists, element.isHittable { return true }
    }
    return element.exists && element.isHittable
  }
}
#elseif APPSTORE_RELEASE_TESTING
/// Exercises the compiled public capability surface without any DEBUG launch
/// arguments, fake provider, seeded records, or ephemeral-store back door.
final class GITimelineAppStoreUITests: XCTestCase {
  func testPublicFirstRunAndManualRouteAreReachableWithoutTestHooks() throws {
    let app = XCUIApplication()
    let removedPortableRecoveryClaims = [
      "encrypted recovery",
      "recovery archive",
      "recovery key",
      "recovery file",
      "separate key",
      "private backup",
      "portable or encrypted",
      "journal-backup archive",
      "cross-install/device",
      "export recovery",
      "import recovery",
      "restore journal",
    ]
    app.launchArguments = [
      "-UIPreferredContentSizeCategoryName",
      "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
    ]
    app.launch()

    let continueButton = app.buttons["Continue"]
    if continueButton.waitForExistence(timeout: 3) {
      continueButton.tap()
    }

    XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 8))
    XCTAssertTrue(app.tabBars.buttons["Journal"].exists)
    XCTAssertTrue(app.tabBars.buttons["Settings"].exists)
    XCTAssertFalse(app.buttons["openDeveloperTools"].exists)
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public Log at accessibility XXXL")

    let help = app.buttons["showInformation"]
    XCTAssertTrue(help.waitForExistence(timeout: 3))
    help.tap()
    XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5))
    for removedFeatureClaim in removedPortableRecoveryClaims {
      let predicate = NSPredicate(format: "label CONTAINS[c] %@", removedFeatureClaim)
      XCTAssertFalse(
        app.descendants(matching: .any).matching(predicate).firstMatch.exists,
        "Help & About must not expose a removed portable-recovery feature: \(removedFeatureClaim)"
      )
    }
    XCTAssertTrue(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS[c] %@", "photo-inclusive PDF")
      ).firstMatch.exists
    )
    app.buttons["Done"].tap()
    XCTAssertTrue(app.tabBars.buttons["Log"].waitForExistence(timeout: 5))

    app.tabBars.buttons["Settings"].tap()
    XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    let restartDurability = app.descendants(matching: .any)["restartDurabilityDisclosure"]
    let restartText = "Saved logs are designed to remain in this app's local container when you close and reopen GI Journal, restart this iPhone and unlock it, or install an in-place app update."
    XCTAssertTrue(scrollIntoUnobscuredViewport(exactLabel: restartText, in: app))
    let restartDetail = app.descendants(matching: .any).matching(
      NSPredicate(format: "label == %@", restartText)
    ).firstMatch
    XCTAssertTrue(restartDetail.waitForExistence(timeout: 2))
    XCTAssertTrue(restartDetail.isHittable)
    XCTAssertTrue(restartDurability.exists)
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public Settings at accessibility XXXL")
    for term in ["recovery", "restore", "backup", "key"] {
      let predicate = NSPredicate(format: "label CONTAINS[c] %@", term)
      XCTAssertFalse(app.buttons.matching(predicate).firstMatch.exists)
    }
    for removedFeatureClaim in removedPortableRecoveryClaims {
      let predicate = NSPredicate(format: "label CONTAINS[c] %@", removedFeatureClaim)
      XCTAssertFalse(
        app.descendants(matching: .any).matching(predicate).firstMatch.exists,
        "Settings must not expose a removed portable-recovery feature: \(removedFeatureClaim)"
      )
    }
    resetScrollToTop(in: app)
    let privacy = app.buttons["privacyPolicy"]
    XCTAssertTrue(scrollUntilHittable(privacy, in: app))
    privacy.tap()
    XCTAssertTrue(app.navigationBars["Privacy policy"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["privacyPolicyOnline"].exists)
    XCTAssertFalse(
      app.staticTexts.matching(
        NSPredicate(format: "label CONTAINS[c] %@", "exported journal")
      ).firstMatch.exists,
      "Privacy policy must describe the remaining shared-PDF surface, not a removed journal export."
    )
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public privacy policy at accessibility XXXL")
    app.navigationBars["Privacy policy"].buttons.firstMatch.tap()

    resetScrollToTop(in: app)
    let support = app.buttons["technicalSupport"]
    XCTAssertTrue(scrollUntilHittable(support, in: app))
    support.tap()
    XCTAssertTrue(app.navigationBars["Technical support"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["supportOnline"].exists)
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public support at accessibility XXXL")
    app.navigationBars["Technical support"].buttons.firstMatch.tap()

    resetScrollToTop(in: app)
    let notices = app.buttons["thirdPartyNotices"]
    XCTAssertTrue(scrollUntilHittable(notices, in: app))
    notices.tap()
    XCTAssertTrue(app.navigationBars["Licenses and notices"].waitForExistence(timeout: 5))
    XCTAssertTrue(app.descendants(matching: .any)["thirdPartyNoticesText"].exists)
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public notices at accessibility XXXL")
    app.navigationBars["Licenses and notices"].buttons.firstMatch.tap()
    app.tabBars.buttons["Log"].tap()

    let reviewTitle = app.staticTexts["Review your entry"]
    let restoredPublicDraft = reviewTitle.waitForExistence(timeout: 1)
    if !restoredPublicDraft {
      let manualButton = app.buttons["logWithoutPhoto"]
      XCTAssertTrue(manualButton.waitForExistence(timeout: 5))
      manualButton.tap()
    }
    XCTAssertTrue(reviewTitle.waitForExistence(timeout: 5))
    XCTAssertFalse(app.descendants(matching: .any)["manualSuggestionFallback"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["photoSuggestionDisclosure"].exists)
    XCTAssertFalse(app.descendants(matching: .any)["suggestionsNotYetConfirmed"].exists)
    for prohibitedPublicClaim in ["Gemma", "prefill", "Accept all suggestions"] {
      XCTAssertFalse(
        app.descendants(matching: .any).matching(
          NSPredicate(format: "label CONTAINS[c] %@", prohibitedPublicClaim)
        ).firstMatch.exists,
        "The public manual entry sheet must not expose an active model/prefill claim: \(prohibitedPublicClaim)"
      )
    }
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public review at accessibility XXXL")

    let subject = app.descendants(matching: .any)["manualEntrySubject"]
    XCTAssertTrue(scrollUntilHittable(subject, in: app))
    subject.tap()
    let bowelMovement = app.buttons["Bowel movement"]
    XCTAssertTrue(bowelMovement.waitForExistence(timeout: 3))
    bowelMovement.tap()

    let apparentColor = app.descendants(matching: .any)["manualApparentColor"]
    XCTAssertTrue(scrollUntilHittable(apparentColor, in: app))
    apparentColor.tap()
    let brown = app.buttons["Brown"]
    XCTAssertTrue(brown.waitForExistence(timeout: 3))
    brown.tap()

    let type4 = app.buttons["Type 4 — smooth and formed"]
    XCTAssertTrue(scrollUntilHittable(type4, in: app))
    type4.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: type4))
    XCTAssertTrue(app.descendants(matching: .any)["manualForm"].exists)

    // Complete every remaining public manual value. Photo attachment and
    // zero-inference persistence/PDF behavior are covered by the focused unit
    // receipt without exposing a test-only provider in this public UI run.
    let save = app.buttons["saveEntry"]
    XCTAssertTrue(save.exists)

    let mixedNo = app.buttons["mixedForm_no"]
    XCTAssertTrue(scrollAboveSave(mixedNo, save: save, in: app, maxSwipes: 12))
    mixedNo.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: mixedNo))

    let redNo = app.buttons["redMaterial_no"]
    XCTAssertTrue(scrollAboveSave(redNo, save: save, in: app, maxSwipes: 12))
    XCTAssertTrue(
      app.staticTexts[
        "This records an appearance only and does not confirm blood or bleeding."
      ].exists
    )
    redNo.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: redNo))

    let blackAppearanceNo = app.buttons["blackAppearance_no"]
    XCTAssertTrue(scrollAboveSave(blackAppearanceNo, save: save, in: app, maxSwipes: 12))
    blackAppearanceNo.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: blackAppearanceNo))

    let blackNo = app.buttons["blackTarry_no"]
    XCTAssertTrue(scrollAboveSave(blackNo, save: save, in: app, maxSwipes: 12))
    blackNo.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: blackNo))

    // Re-audit the lower review card after its final choice is genuinely
    // visible above the tab bar/sticky Save region. Offscreen contrast reports
    // ignored above can therefore never substitute for visible qualification.
    XCTAssertTrue(scrollAboveSave(blackNo, save: save, in: app))
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public lower review at accessibility XXXL")

    // The test never sets a pain score, so "Set pain score" remains on
    // screen. Scroll it fully clear of the nav/tab-bar scroll-edge fade band
    // and re-audit contrast on it directly, so the waiver above never
    // substitutes for a positive, visible contrast check on this control.
    let setPainScore = app.buttons["Set pain score"]
    guard setPainScore.waitForExistence(timeout: 3) else {
      XCTFail("\"Set pain score\" button not found; cannot verify its contrast while visible.")
      return
    }
    XCTAssertTrue(scrollIntoUnobscuredViewport(exactLabel: "Set pain score", in: app))
    try assertNoAccessibilityAuditIssues(in: app, activityName: "Public pain control at accessibility XXXL")

    XCTAssertTrue(save.isEnabled)
    XCTAssertEqual(save.label, "Save entry")
    save.tap()
    XCTAssertTrue(app.staticTexts["Entry saved"].waitForExistence(timeout: 8))

    // Exercise the ordinary public edit path before relaunch. This remains a
    // production-condition flow: no seeded record, fake provider, or private
    // container access is involved.
    let viewSavedEntry = app.buttons["viewSavedEntry"]
    XCTAssertTrue(viewSavedEntry.waitForExistence(timeout: 5))
    viewSavedEntry.tap()
    XCTAssertTrue(app.descendants(matching: .any)["entryDetail"].waitForExistence(timeout: 8))
    let editEntry = app.buttons["editEntry"]
    XCTAssertTrue(editEntry.waitForExistence(timeout: 3))
    editEntry.tap()
    XCTAssertTrue(app.navigationBars["Edit entry"].waitForExistence(timeout: 5))
    let type7 = app.buttons["Type 7 — watery, with no solid pieces"]
    XCTAssertTrue(scrollUntilHittable(type7, in: app))
    type7.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: type7))
    let saveChanges = app.buttons["saveEntryChanges"]
    XCTAssertTrue(scrollUntilHittable(saveChanges, in: app))
    saveChanges.tap()
    let updatedType7 = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Type 7 — watery, with no solid pieces")
    ).firstMatch
    XCTAssertTrue(updatedType7.waitForExistence(timeout: 5))

    // This uses the ordinary public store and no test-only launch arguments.
    // It proves save/edit/detail-refresh/close/relaunch retention in the
    // simulator, not a device reboot or migration between App Store builds.
    app.terminate()
    app.launch()
    let relaunchContinue = app.buttons["Continue"]
    if relaunchContinue.waitForExistence(timeout: 3) {
      relaunchContinue.tap()
    }
    XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 8))
    app.tabBars.buttons["Journal"].tap()
    let reopenedEntry = app.buttons["journalEntry"].firstMatch
    XCTAssertTrue(reopenedEntry.waitForExistence(timeout: 8))
    reopenedEntry.tap()
    XCTAssertTrue(app.descendants(matching: .any)["entryDetail"].waitForExistence(timeout: 5))
    let reopenedType7 = app.staticTexts.matching(
      NSPredicate(format: "label CONTAINS %@", "Type 7 — watery, with no solid pieces")
    ).firstMatch
    XCTAssertTrue(reopenedType7.waitForExistence(timeout: 5))
  }

  @discardableResult
  private func scrollUntilHittable(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 12
  ) -> Bool {
    if element.waitForExistence(timeout: 2), element.isHittable { return true }
    for _ in 0..<maxSwipes {
      app.swipeUp()
      if element.exists, element.isHittable { return true }
    }
    return element.exists && element.isHittable
  }

  private func resetScrollToTop(in app: XCUIApplication, maxSwipes: Int = 12) {
    for _ in 0..<maxSwipes { app.swipeDown() }
  }

  private func scrollIntoUnobscuredViewport(
    exactLabel: String,
    in app: XCUIApplication,
    maxSteps: Int = 12
  ) -> Bool {
    let predicate = NSPredicate(format: "label == %@", exactLabel)
    var lastFingerDeltaY: CGFloat?
    var usedReverseRecovery = false

    func exactElement() -> XCUIElement {
      app.descendants(matching: .any).matching(predicate).firstMatch
    }

    func performBoundedDrag(fingerDeltaY: CGFloat) {
      let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
      let destination = start.withOffset(CGVector(dx: 0, dy: fingerDeltaY))
      start.press(
        forDuration: 0.1,
        thenDragTo: destination,
        withVelocity: .slow,
        thenHoldForDuration: 0.1
      )
    }

    for attempt in 0...maxSteps {
      let element = exactElement()
      guard element.waitForExistence(timeout: attempt == 0 ? 2 : 1) else {
        guard !usedReverseRecovery,
          let previousFingerDeltaY = lastFingerDeltaY,
          attempt < maxSteps
        else { return false }
        performBoundedDrag(fingerDeltaY: -previousFingerDeltaY)
        usedReverseRecovery = true
        lastFingerDeltaY = nil
        continue
      }

      guard let bounds = unobscuredVerticalBounds(in: app) else { return false }
      // iOS 26's scroll-edge fade/glass region can still visually obscure an
      // element that is nominally inside the unobscured bounds if it hugs
      // the nav bar or tab bar edge. Require a safety margin inside the
      // bounds — capped so short screens still make progress — before
      // accepting the element's position.
      let unobscuredHeight = bounds.bottom - bounds.top
      let margin = min(120, unobscuredHeight * 0.2)
      let safeTop = bounds.top + margin
      let safeBottom = bounds.bottom - margin
      guard safeTop <= safeBottom else { return false }
      let frame = element.frame
      if frame.minY >= safeTop, frame.maxY <= safeBottom { return true }
      guard attempt < maxSteps else { return false }

      // Drive toward the vertical centre of the unobscured region rather
      // than just barely inside the margin, so the element lands well clear
      // of the edge fade instead of hugging the boundary again next step.
      let targetCenterY = (bounds.top + bounds.bottom) / 2
      let centerDelta = targetCenterY - frame.midY
      let direction: CGFloat = centerDelta >= 0 ? 1 : -1
      let distance = min(96, max(24, abs(centerDelta)))
      let fingerDeltaY = direction * distance
      performBoundedDrag(fingerDeltaY: fingerDeltaY)
      lastFingerDeltaY = fingerDeltaY
    }
    return false
  }

  private func scrollAboveSave(
    _ element: XCUIElement,
    save: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 8
  ) -> Bool {
    for _ in 0..<maxSwipes {
      if element.exists, element.frame.maxY < save.frame.minY { return true }
      app.swipeUp()
    }
    return element.exists && element.frame.maxY < save.frame.minY
  }
}
#elseif INTERNAL_QWEN3_QA_TESTING
/// Drives the internal Qwen3-VL-2B QA journey end-to-end on device: a
/// synthetic embedded fixture is attached and automatically analyzed (see
/// the `--qwen3-qa-attach-fixture=` branch added to
/// `Qwen3QAAutorunCoordinator.run()` in
/// GITimeline/Qwen3HybridPhotoSuggestionEngine.swift, which attaches the one
/// named fixture and returns without exiting so this test can drive the rest
/// of the journey), then the test itself confirms the review state is
/// genuinely unconfirmed and editable, accepts-all-and-saves after editing
/// one field, terminates and relaunches, confirms both the edit and the
/// photo persisted, and exports a clinician PDF. Synthetic fixture only —
/// this never touches real patient data.
final class GITimelineQwen3QAUITests: XCTestCase {
  private static let attachArguments = [
    "--qwen3-decomposed-internal-qa",
    "--qwen3-decomposed-preprocess=512",
    "--qwen3-physical-evidence-jsonl",
    "--qwen3-qa-autorun",
    "--qwen3-qa-attach-fixture=formed-brown",
  ]
  private static let relaunchArguments = [
    "--qwen3-decomposed-internal-qa",
    "--qwen3-decomposed-preprocess=512",
  ]

  func testQwen3FixtureJourneyAcceptAllEditSaveRelaunchAndExportPDF() throws {
    var app = XCUIApplication()
    app.launchArguments = Self.attachArguments
    app.launch()

    tapFirstRunContinueIfPresent(in: app)

    // The embedded Qwen3-VL-2B snapshot can take minutes to load and run on
    // its first call; the coordinator's own budget for the first fixture is
    // 600s (Qwen3QAAutorunCoordinator.run(), Qwen3HybridPhotoSuggestionEngine.swift).
    // Give automatic analysis at least that long before failing.
    let disclosure = app.descendants(matching: .any)["photoSuggestionDisclosure"]
    XCTAssertTrue(
      disclosure.waitForExistence(timeout: 600),
      "photoSuggestionDisclosure never appeared; automatic analysis of the attached synthetic fixture did not complete."
    )

    let save = app.buttons["saveEntry"]
    XCTAssertTrue(save.waitForExistence(timeout: 5))
    XCTAssertEqual(
      save.label, "Accept all suggestions and save",
      "The review state must offer the single accept-all save action, not a manual save."
    )
    XCTAssertTrue(
      app.descendants(matching: .any)["suggestionsNotYetConfirmed"].exists,
      "The review screen must visibly disclose that suggestions are not yet confirmed."
    )

    // Each appearance field carries exactly one editable Yes/No/Not sure
    // suggestion plus stable AI-labelled copy before the single whole-entry
    // confirmation action.
    var uneditedAppearanceValues: [String: String] = [:]
    for prefix in ["redMaterial", "blackTarry", "blackAppearance"] {
      let options = [("yes", "Yes"), ("no", "No"), ("unsure", "Not sure")]
      let controls = options.map { app.buttons["\(prefix)_\($0.0)"] }
      for control in controls {
        XCTAssertTrue(scrollUntilHittable(control, in: app), "\(control.identifier) control not found.")
      }
      let selectedIndices = controls.indices.filter {
        (controls[$0].value as? String) == "Selected"
      }
      XCTAssertEqual(
        selectedIndices.count,
        1,
        "\(prefix) must display exactly one editable AI suggestion."
      )
      if prefix != "redMaterial", let selectedIndex = selectedIndices.first {
        uneditedAppearanceValues[prefix] = options[selectedIndex].1
      }
      let suggestion = app.staticTexts["aiReadHint_\(prefix)"]
      XCTAssertTrue(suggestion.exists)
      XCTAssertTrue(suggestion.label.hasPrefix("AI suggestion:"))
    }

    // Prove the fields are genuinely editable before the one save action:
    // change the red/blood-like appearance answer to Yes and confirm the UI
    // reflects the edit. Editing morphology (mixed form, Bristol, form) is
    // intentionally impossible here: the subject is forced .uncertain, and
    // NewEntryViewModel.fullPrefillReviewIsConsistent
    // (NewEntryViewModel.swift:665-706) requires mixedForm == .unsure
    // whenever confirmedStoolPresence != .stool, so editing mixed form would
    // make canSave false and leave the save button disabled. Red and black
    // remain independently editable under that same consistency contract, so
    // this edit also exercises the person-override path. (Edited field for
    // this journey: redBlood -> yes.)
    let redYes = app.buttons["redMaterial_yes"]
    XCTAssertTrue(scrollUntilHittable(redYes, in: app), "redMaterial_yes control not found.")
    redYes.tap()
    XCTAssertTrue(waitForAccessibilityValue("Selected", on: redYes))

    XCTAssertTrue(scrollUntilHittable(save, in: app))
    XCTAssertTrue(
      save.isEnabled,
      "saveEntry must stay enabled after editing red material only; disabled-reason text "
        + "(NewEntryView.swift:1019 saveEntryDisabledReason): "
        + (app.staticTexts["saveEntryDisabledReason"].exists
          ? app.staticTexts["saveEntryDisabledReason"].label
          : "<saveEntryDisabledReason not found>")
    )
    save.tap()
    XCTAssertTrue(app.staticTexts["Entry saved"].waitForExistence(timeout: 15))

    // Terminate and relaunch without the attach/autorun arguments, proving
    // persistence rather than in-memory state surviving the same process.
    app.terminate()
    app = XCUIApplication()
    app.launchArguments = Self.relaunchArguments
    app.launch()
    tapFirstRunContinueIfPresent(in: app)

    XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 10))
    app.tabBars.buttons["Journal"].tap()
    // HistoryView.swift:241 applies the "journalEntry" identifier to a
    // NavigationLink-backed row that may not surface as a `.button` element;
    // query descendants of any type rather than `app.buttons`.
    let entry = app.descendants(matching: .any).matching(identifier: "journalEntry").firstMatch
    XCTAssertTrue(entry.waitForExistence(timeout: 8))
    entry.tap()
    XCTAssertTrue(app.descendants(matching: .any)["entryDetail"].waitForExistence(timeout: 8))

    // The photo persisted: the entry detail's photo view carries this exact
    // accessibility label only when a photo file was found and decoded
    // (EntryDetailView.photo, HistoryView.swift:432).
    XCTAssertTrue(
      app.images["Photo attached to this journal entry"].waitForExistence(timeout: 5),
      "The saved entry must still show its attached photo after relaunch."
    )

    // The edit persisted: EntryDetailView renders the red/blood-like
    // appearance answer as a labeled detail row whose value is the
    // human-readable form of the stored raw value — HistoryView.swift:367
    // (`detailRow("Possible red/blood-like appearance",
    // HistoryPresentation.reportedValue(entry.redBlood))`) together with
    // HistoryView.swift:1019 (humanReadableHistoryValue capitalizes the
    // stored "yes" to "Yes"). Require both the row's title and its value in
    // the same matched label so an unrelated "Yes" elsewhere on the screen
    // (e.g. the photo-usable row) cannot satisfy this assertion.
    let redMaterialDetail = app.staticTexts.matching(NSPredicate(
      format: "label CONTAINS %@ AND label CONTAINS %@",
      "Possible red/blood-like appearance", "Yes"
    )).firstMatch
    XCTAssertTrue(
      redMaterialDetail.waitForExistence(timeout: 5),
      "The edited red-material=Yes answer must survive terminate/relaunch."
    )

    for (prefix, title) in [
      ("blackAppearance", "Possible unusually black appearance"),
      ("blackTarry", "Possible tar-like appearance"),
    ] {
      let expected = try XCTUnwrap(
        uneditedAppearanceValues[prefix],
        "The pre-save review must expose one selected \(prefix) value."
      )
      let detail = app.staticTexts.matching(NSPredicate(
        format: "label CONTAINS %@ AND label CONTAINS %@",
        title, expected
      )).firstMatch
      XCTAssertTrue(
        detail.waitForExistence(timeout: 5),
        "The person-confirmed \(prefix)=\(expected) answer must survive terminate/relaunch."
      )
    }

    // Export a clinician PDF for this entry and confirm success.
    XCTAssertTrue(app.navigationBars["Journal entry"].waitForExistence(timeout: 5))
    app.navigationBars["Journal entry"].buttons.firstMatch.tap()
    XCTAssertTrue(app.tabBars.buttons["Journal"].waitForExistence(timeout: 5))
    app.tabBars.buttons["Journal"].tap()
    let exportPDF = app.buttons["Export PDF"]
    XCTAssertTrue(scrollUntilHittable(exportPDF, in: app))
    exportPDF.tap()
    XCTAssertTrue(app.navigationBars["Export journal"].waitForExistence(timeout: 5))
    let createPDF = app.buttons["Create PDF"]
    XCTAssertTrue(scrollUntilHittable(createPDF, in: app))
    createPDF.tap()
    XCTAssertTrue(
      app.navigationBars["PDF preview"].waitForExistence(timeout: 20),
      "Clinician PDF export must succeed for the saved, photo-inclusive entry."
    )
    app.buttons["Done"].tap()
  }

  /// Taps the first-run cover's Continue button if it is currently showing.
  /// The QA attach-only flow can dismiss or re-render this cover concurrently
  /// with this check, so a naive "wait then tap" races: the button can exist
  /// at the check and vanish before the tap lands (see the "firstRunContinue"
  /// accessibilityIdentifier at NewEntryView.swift:1301). Re-verify existence
  /// immediately before each tap, and retry a few times in case a tap lands
  /// while the cover is mid-transition and is ignored. This helper never
  /// asserts: it only clears an optional first-run cover, so it must tolerate
  /// the element disappearing at any point without failing the test.
  private func tapFirstRunContinueIfPresent(in app: XCUIApplication) {
    let continueButton = app.buttons["firstRunContinue"]
    // The first-run cover is a SCROLLABLE welcome page taller than the
    // screen, and its Continue button sits at the bottom of that content —
    // below the fold at launch (E2E run 12 failure hierarchy: cover content
    // 1266pt in a 956pt viewport, firstRunContinue only on-screen once the
    // cover is scrolled to the end). exists is true from launch but
    // isHittable only becomes true after scrolling, so tapping without
    // scrolling can never dismiss the cover. Do what a person does: scroll
    // the welcome page until Continue is hittable, then tap. The embedded
    // model load can also stall the main thread for ~50s and swallow input,
    // so success is only "the button is gone" — keep working the page until
    // it disappears or the deadline passes. This helper never asserts.
    let deadline = Date(timeIntervalSinceNow: 90)
    while Date() < deadline {
      guard continueButton.waitForExistence(timeout: 2) else { return }
      if continueButton.isHittable {
        continueButton.tap()
        Thread.sleep(forTimeInterval: 1.0)
        if !continueButton.exists { return }
      } else {
        app.swipeUp()
        Thread.sleep(forTimeInterval: 0.5)
      }
    }
  }

  /// Reproduces the owner-reported real-use path the fixture journey
  /// bypasses: choosing a photo through the REAL system photo library picker
  /// (no attach fixture, no autorun). The report was "photo selection
  /// crashes without doing anything" — the picker's remote sheet dying, or
  /// the app aborting when the engine's GPU work overlaps the picker
  /// transition (device crash log 2026-08-23-105415: MLX
  /// mlx::core::gpu::check_error → abort 12 s after launch). Requires at
  /// least one photo in the device's library.
  func testChoosePhotoFromRealLibraryReachesReviewWithoutCrashing() throws {
    let app = XCUIApplication()
    app.launchArguments = Self.relaunchArguments
    app.launch()

    tapFirstRunContinueIfPresent(in: app)

    // The app restores its last tab across launches; choosePhoto lives on
    // the Log tab, so select it explicitly instead of assuming launch state.
    let logTab = app.tabBars.buttons["Log"]
    if logTab.waitForExistence(timeout: 5) { logTab.tap() }

    let choose = app.buttons["choosePhoto"]
    XCTAssertTrue(scrollUntilHittable(choose, in: app), "choosePhoto button not reachable")
    choose.tap()

    // The PhotosPicker remote content surfaces inside the app's element
    // tree. Wait generously: the sheet's remote process can take seconds on
    // first use, and its death is exactly one of the failure modes under
    // test (the tree then never shows any photo cell). Tiny decorative
    // glyphs also match `images`, so require a thumbnail-sized frame.
    // Remote-view elements routinely report isHittable == false across the
    // process boundary even while fully visible (screen recording of run
    // photopick-4 shows the grid on screen at the moment the query failed),
    // so gate only on frame size and tap by coordinate, which does not
    // re-run the hit test.
    let deadline = Date(timeIntervalSinceNow: 30)
    var photoCell: XCUIElement?
    while Date() < deadline, photoCell == nil {
      for candidate in app.images.allElementsBoundByIndex
      where candidate.frame.width >= 60 && candidate.frame.height >= 60
        && candidate.frame.minY > 0 {
        photoCell = candidate
        break
      }
      if photoCell == nil { Thread.sleep(forTimeInterval: 1.0) }
    }
    let firstPhoto = try XCTUnwrap(
      photoCell,
      "The system photo picker never showed a thumbnail-sized photo cell; the picker sheet likely died."
    )
    firstPhoto.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

    // Selecting a photo dismisses the picker, then the app sanitizes the
    // image, loads the embedded model, and runs the real analysis. The app
    // must stay alive the whole way to the review state.
    let disclosure = app.descendants(matching: .any)["photoSuggestionDisclosure"]
    let reviewReached = disclosure.waitForExistence(timeout: 600)
    XCTAssertEqual(
      app.state, .runningForeground,
      "The app must survive photo selection and analysis; a crash here matches the owner-reported failure."
    )
    XCTAssertTrue(
      reviewReached,
      "Review never appeared after choosing a real library photo."
    )
  }

  @discardableResult
  private func scrollUntilHittable(
    _ element: XCUIElement,
    in app: XCUIApplication,
    maxSwipes: Int = 12
  ) -> Bool {
    if element.waitForExistence(timeout: 2), element.isHittable { return true }
    for _ in 0..<maxSwipes {
      app.swipeUp()
      if element.exists, element.isHittable { return true }
    }
    return element.exists && element.isHittable
  }
}
#else
#error("GITimelineUITests requires DEBUG, RELEASE_FALLBACK_TESTING, APPSTORE_RELEASE_TESTING, or INTERNAL_QWEN3_QA_TESTING")
#endif
