# AI appearance suggestion contract

Status: active for new AI-enabled builds and qualification runs as of 2026-08-31.

This contract supersedes every earlier active instruction that prohibited a
negative red/blood-like or black/tar-like appearance suggestion. Older frozen
campaigns, scorecards, reports, and evaluators remain byte-preserved as
historical evidence only; their negative-suggestion rules are not current
product or qualification requirements.

## Visible suggestions

The AI may suggest **Yes**, **No**, or **Not sure** from the photograph. Each
value is an appearance-only guess, not a diagnosis, clinical blood or melena
detection result, reassurance, urgency decision, or treatment recommendation.

Red or blood-like material uses exactly:

- Yes: `AI suggestion: Possible blood-like red material is visible.`
- No: `AI suggestion: No blood-like red material detected in this photo.`
- Not sure: `AI suggestion: Unable to determine whether blood-like red material is visible.`

Black or tar-like appearance uses exactly:

- Yes: `AI suggestion: Possible black or tar-like appearance is visible.`
- No: `AI suggestion: No black or tar-like appearance detected in this photo.`
- Not sure: `AI suggestion: Unable to determine whether a black or tar-like appearance is visible.`

The current V2 review screen keeps separate unusually-black and tar-like
answers. Both use the same black-or-tar copy family above.

## Review and persistence

- Every suggestion is visibly AI-labelled, editable, and shown before saving.
- There are no per-field confirmation taps.
- The single final whole-entry confirmation adopts all values currently shown.
- Saved entries and clinician PDFs use the person-confirmed values while
  preserving the original model suggestion and edit provenance.
- Invalid, malformed, timed-out, cancelled, or technically unusable analysis
  still falls back to a retained manual draft with **Not sure** values.

## Qualification

- A negative appearance suggestion is allowed and does not automatically fail
  qualification.
- Non-detection may map to **No** when the versioned model and conservative
  visual evidence agree; ambiguity, disagreement, or missing evidence maps to
  **Not sure**.
- Positive recall and false-positive gates remain appearance-level directional
  tests, not clinical-accuracy claims.
- New host evidence uses `score_mild_utility_v3.py`. The frozen v2 evaluator is
  retained only to reproduce historical v2 results.
