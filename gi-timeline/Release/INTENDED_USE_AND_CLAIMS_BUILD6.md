# Intended use and claims boundary — historical Build 6 with current-tree draft

> **Status:** Draft language for operator and qualified legal/regulatory review. It is not a regulatory classification, App Store submission, or clinical-validation claim.

> **Current-tree supersession — 2026-08-03:** Build 6 remains historical evidence. The current candidate exposes only Log, Journal, and Settings; supports a dated no-bowel-movement marker and editable saved entries; uses one whole-entry confirmation for Gemma-prefilled visible observations; removes treatment-change/Progress UI and the fixed urgent-care banner; and has no V1 journal-transfer feature. Journal data remains local, the app requests automatic-backup exclusion, app or device loss may permanently lose entries and photos, PDFs cannot restore the journal, and there is no developer backend or developer access. This candidate requires new frozen-source, physical-device, legal, and App Store evidence before release.

## Intended use

GI Journal is a private, local tool for a person to document observations and journal information for their own review and optional discussion with a qualified health professional. Gemma may prefill conservative visible observations; the person reviews and may edit them, then chooses whether to confirm and save the whole entry once.

GI Journal is intended as a documentation tool, not as a diagnostic or treatment service. It does not diagnose a condition, determine its cause or severity, recommend treatment, prescribe a care change, or replace professional medical advice. Whether its functionality changes the product's medical-device or regional regulatory classification requires qualified legal/regulatory review before release.

## Current-candidate suggestion boundary

The current Build 8 candidate photo-suggestion route is deliberately bounded:

1. Local code redraws the selected photo as a bounded, metadata-free JPEG and validates that app-created copy and its SHA-256 provenance.
2. The exact validated JPEG bytes are given directly to the embedded Gemma model on the iPhone; the developer, model provider, and any server do not receive them.
3. Gemma returns a strict, conservative appearance-only suggestion. Unsupported, non-stool, mixed, or unclear inputs must abstain instead of forcing a confident value.
4. The app prefills supported visible fields. Red/blood-like and black/tar-like person answers remain independent and initially unselected; the person reviews and may edit or discard the suggestion, then confirms the complete entry once before saving.

This current-candidate description does not retroactively relabel historical Build 6 text-facts-bridge evidence as direct image inference. It also does not establish patient-photo accuracy, diagnosis, physical-device qualification, Airplane Mode behavior, or App Store approval. Those gates require separate final-binary evidence.

## Prohibited or unsupported claims

Do not claim that GI Journal or its Gemma feature:

- diagnoses, screens for, detects, predicts, grades, or clinically validates a condition or symptom;
- uses a photo or Gemma output to infer symptoms, provide medical advice, perform triage, recommend treatment, or generate emergency guidance;
- establishes clinical accuracy, sensitivity, specificity, real-world effectiveness, or raw-photo model performance;
- sends a photo to a developer, model-provider, or remote inference service;
- uses the direct prepared-image-byte route to claim diagnostic, clinical, or patient-photo accuracy;
- has completed App Store review, TestFlight qualification, physical-device accessibility qualification, or regional medical-device analysis.

## Required review before publication

| Review | Status | Owner / evidence |
|---|---|---|
| Product copy matches this conservative intended use | **UNRESOLVED** |  |
| Final binary behavior matches the shipped suggestion boundary | **UNRESOLVED** |  |
| Legal/regulatory regional review of claims and intended use | **UNRESOLVED** |  |
| Store metadata, screenshots, and review notes contain no unsupported claims | **UNRESOLVED** |  |
