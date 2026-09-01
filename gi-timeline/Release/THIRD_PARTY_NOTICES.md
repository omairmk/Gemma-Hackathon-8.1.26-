# GI Journal third-party notices

> **Release-candidate notice inventory — 2026-08-02:** The direct dependencies and pinned artifacts below are verified from repository configuration and upstream sources. This is not yet a complete legal notice bundle for distribution: the final `CLiteRTLM` binary and AppStore archive still require a transitive license/NOTICE audit and legal approval.

The dated `RUNTIME_NOTICES_GAP_INVENTORY_BUILD8_2026-08-03.md` ledger records the prior LiteRT-LM pin and remains historical evidence. `RUNTIME_NOTICES_GAP_INVENTORY_BUILD8_V015_2026-08-04.md` is the current v0.15 upstream/binary baseline and records unresolved static-component indicators. `Vendor/LiteRTLM/UPSTREAM_PROVENANCE.md` binds the local derivative identity, modified-file notices, and compile-input digest; `BUILD8_PREDECESSOR_FULL_BOOTSTRAP_AND_PREFLIGHT_2026-08-05.md` records current local source/test evidence, `BUILD8_PREDECESSOR_GENERIC_DEVICE_COMPOSITION_2026-08-05.md` records the newest generic-iPhoneOS composition, `BUILD8_V5_GENERATION_CACHE_AND_APPSTORE_SCHEME_2026-08-05.md` retains cache-generation detail and its exact earlier checkpoint, and older generic-device receipts retain their dated historical boundaries. Publisher provenance, a final archive/IPA-bound transitive license/NOTICE inventory, and legal approval remain required; no license text is guessed here.

The public manual-fallback configuration does not bundle a model as of commit `7ff99c6`. The Gemma section below is retained for the separate nonshipping Physical Qualification configuration and its historical evidence; it does not describe a public App Store payload.

GI Journal includes software developed by third parties. Separate nonshipping qualification configurations may also use third-party model material. Those materials remain subject to their respective licenses. The GI Journal name and product-specific code are not licensed by this document.

## LiteRT-LM

- Project: LiteRT-LM
- Author/copyright notice observed in the pinned Swift package: `Copyright 2026 Google LLC`
- Source: <https://github.com/google-ai-edge/LiteRT-LM>
- Pinned source revision: `2117fc4314670e00047bc8469783f02a68c33f0c`
- Swift package product used by GI Journal: `LiteRTLM`
- Shipping source form: reviewed local derivative wrapper at `Vendor/LiteRTLM`; upstream base revision remains the revision above.
- Modification notice: GI Journal removes unused package targets, validates the exposed image-limit and CPU-thread fields, and forwards them to existing v0.15 native setters. The packaged header describes the max-images setter as legacy-only, so it is not evidence of an advanced-engine memory limit; GI Journal separately enforces its one-photo product route. Each modified upstream file carries an inline modification notice.
- Path-independent wrapper compile-input SHA-256: `22c81184a1bad821ea7c890c167fa0a75089ba774beaf8176a0d3b99290d842d`
- iOS binary target: `CLiteRTLM`
- Binary release referenced by the pinned package: `v0.15.0`
- Binary URL: <https://github.com/google-ai-edge/LiteRT-LM/releases/download/v0.15.0/CLiteRTLM.xcframework.zip>
- Swift Package Manager checksum at the pinned revision: `d6ccf6b54362d894ff71a7580c7e446d36767dab908aecfbb16ffca0fa0bc59b`
- License: Apache License 2.0
- License text at the pinned revision: <https://github.com/google-ai-edge/LiteRT-LM/blob/2117fc4314670e00047bc8469783f02a68c33f0c/LICENSE>

LiteRT-LM is licensed under the Apache License, Version 2.0. You may obtain a copy at <https://www.apache.org/licenses/LICENSE-2.0>. Unless required by applicable law or agreed to in writing, software distributed under that license is distributed on an “AS IS” basis, without warranties or conditions of any kind. See the license for the specific language governing permissions and limitations.

The pinned LiteRT-LM v0.15 source tree contains a root `LICENSE` and no root `NOTICE` file. That fact does not establish that the prebuilt `CLiteRTLM` archive has no transitive notice obligations.

## Gemma 4 E4B instruction-tuned LiteRT-LM model

- Distribution repository: `litert-community/gemma-4-E4B-it-litert-lm`
- Immutable source view: <https://huggingface.co/litert-community/gemma-4-E4B-it-litert-lm/tree/28299f30ee4d43294517a4ac93abd6163412f07f>
- Pinned artifact revision: `28299f30ee4d43294517a4ac93abd6163412f07f`
- Artifact: `gemma-4-E4B-it.litertlm`
- Artifact bytes: `3,659,530,240`
- Artifact SHA-256: `0b2a8980ce155fd97673d8e820b4d29d9c7d99b8fa6806f425d969b145bd52e0`
- Base model identified by the distribution repository: `google/gemma-4-E4B-it`
- Model authors identified by the base model card: Google DeepMind
- Distribution repository license metadata at the pinned revision: `apache-2.0`
- Base model license: Apache License 2.0
- Base model license link: <https://ai.google.dev/gemma/docs/gemma_4_license>
- Base model card: <https://huggingface.co/google/gemma-4-E4B-it>

Gemma 4 E4B is made available under the Apache License, Version 2.0. You may obtain a copy at <https://www.apache.org/licenses/LICENSE-2.0>. Unless required by applicable law or agreed to in writing, material distributed under that license is distributed on an “AS IS” basis, without warranties or conditions of any kind. See the license for the specific language governing permissions and limitations.

### Gemma prohibited-use condition

GI Journal's release policy also treats the current [Gemma Prohibited Use Policy](https://ai.google.dev/gemma/prohibited_use_policy) as a governing distribution and use condition. Google states that the policy may be updated. The version observed during this documentation pass says it was last modified February 21, 2024 and, among other restrictions, prohibits unauthorized medical practice, misleading health-expertise claims, automated decisions in healthcare that affect rights or well-being, and processing or inferring sensitive information without the required rights, authorizations, and consents.

Accordingly, the distributed Gemma-powered feature must remain documentation-only:

- It must not use model input or output to make health eligibility, coverage, access, diagnosis, treatment, triage, prognosis, or clinical-severity decisions.
- It must not claim medical expertise or clinical validity for model output.
- It may prepare only conservative, editable visible-field prefills; the user reviews the prefilled entry, changes anything that is not right, and confirms the whole entry once before Save.
- Pain, urgency, dizziness, severe pain, notes, and sharing choices remain human-entered or human-directed.
- It must not use a photo or journal to infer unrelated sensitive traits, monitor another person without authorization, or make an automated decision affecting that person.
- Product terms, App Store claims, help, safety language, and model behavior must remain consistent with the current policy.

The Gemma 4 artifact's published license metadata is Apache-2.0. This notice does not assert that the Prohibited Use Policy is incorporated into the Apache License; it records the additional product distribution/use condition adopted for internal qualification. Legal review must verify the then-current model license, model-card metadata, repository terms, Prohibited Use Policy, and their relationship before any future model-bearing public release.

GI Journal does not claim sponsorship, endorsement, or affiliation with Google, Google DeepMind, Hugging Face, or the LiteRT community.

## Required distribution packaging

Before public distribution:

1. Include an unmodified copy of the Apache License 2.0 text in the app's legal-notices surface or bundled legal resources and make it reasonably accessible to users.
2. Preserve applicable copyright, patent, attribution, and license notices from the exact source and binary artifacts.
3. Extract the exact `CLiteRTLM.xcframework` selected by Swift Package Manager and inventory embedded static libraries, frameworks, resources, `LICENSE`, `NOTICE`, and privacy-manifest files.
4. Determine and include notices for all transitive native components, which may include LiteRT and optimized kernels. Do not infer their complete set from the LiteRT-LM README.
5. Compare upstream license metadata at the pinned revisions with the downloaded files and the final archive; archive the evidence.
6. If a future public candidate admits a model, retrieve and archive its current license, model-card/repository license metadata, and governing use policy on the candidate release date; record retrieval URLs, dates, and content hashes.
7. If a future public candidate admits suggestions, confirm the product and its user-facing terms preserve the documentation-only boundary and do not make health eligibility or diagnostic decisions.
8. Confirm whether any modifications were made to third-party source and, if so, add the notices required by Apache License 2.0 section 4.
9. Have authorized counsel or the legal owner approve redistribution of the binary framework in the paid App Store product and, only for a future model-bearing candidate, the exact model artifact.

## Operator/legal status

- **[LEGAL — BLOCKING]** Approve the Apache 2.0 obligations and final attribution wording.
- **[CONDITIONAL — NOT IN CURRENT PUBLIC PAYLOAD]** If a future public candidate admits the pinned `.litertlm` artifact, confirm that it may be redistributed inside the paid app in every selected territory.
- **[CONDITIONAL — NOT IN CURRENT PUBLIC PAYLOAD]** Before any model-bearing release, verify the then-current model terms and governing use policy and archive the reviewed versions.
- **[CONDITIONAL — NOT IN CURRENT PUBLIC PAYLOAD]** Before any suggestion-enabled release, confirm the feature remains documentation-only and makes no health eligibility, diagnosis, treatment, triage, prognosis, or clinical-severity decision.
- **[RELEASE ENGINEERING — BLOCKING]** Produce the final transitive notice inventory from the exact archive.
- **[IMPLEMENTED — CANDIDATE VERIFICATION REQUIRED]** Settings includes an offline **Licenses and notices** route backed by the bundled notice text; verify it in the final AppStore-condition build and archive.

Do not mark this notice inventory final merely because the direct dependencies above are accurate.
