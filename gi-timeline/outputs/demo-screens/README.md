# Native dark / Accessibility Extra Large screenshots

These sanitized iPhone 17e Simulator captures use synthetic brown fixture data, dark mode, and the Accessibility Extra Large Dynamic Type setting. They document the native review-first journey; the deterministic fake provider used by UI tests is not evidence of real Gemma inference.

| Screenshot | State | Test evidence |
| --- | --- | --- |
| `native-01-first-run-dark-axxl.png` | First-run explanation | `GITimelineUITests.testFirstRunExplainsTheReviewBeforeSave` — dark/AXXL passing run |
| `native-02-new-entry-dark-axxl.png` | New Entry after dismissing first-run cover | `GITimelineUITests.testFirstRunExplainsTheReviewBeforeSave` — dark/AXXL passing run |
| `native-03-reading-dark-axxl.png` | Photo-reading progress | `GITimelineUITests.testReadingPhotoKeepsTheAttachedPhotoWhileAnalysisIsActive` — dark/AXXL passing run |
| `native-04-review-dark-axxl.png` | Editable review | `GITimelineUITests.testAutomaticDemoReviewPersistsAndDeletes` — dark/AXXL passing run |
| `native-05-saved-dark-axxl.png` | Saved confirmation | `GITimelineUITests.testAutomaticDemoReviewPersistsAndDeletes` — dark/AXXL passing run |
| `native-06-history-dark-axxl.png` | History, including full readable summary | `GITimelineUITests.testAutomaticDemoReviewPersistsAndDeletes` — focused layout PASS 1/1 |
| `native-07-entry-detail-dark-axxl.png` | Entry Detail, clean top-of-detail capture | `GITimelineUITests.testAutomaticDemoReviewPersistsAndDeletes` — focused capture PASS 1/1 |
| `native-08-error-dark-axxl.png` | Recoverable reading error | `GITimelineUITests.testReadingPhotoKeepsTheAttachedPhotoWhileAnalysisIsActive` — dark/AXXL passing run |

The final current-source UI suite passed 3/3. The focused dark/AXXL History layout run passed 1/1, and the clean top-of-Detail capture rerun passed 1/1 in 66.577 seconds.
