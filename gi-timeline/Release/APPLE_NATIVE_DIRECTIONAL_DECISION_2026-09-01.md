# Apple-native directional decision — 2026-09-01

Status: `APPLE_NATIVE_DIRECTIONAL_NO_GO`

No Apple-native classifier was integrated into the public app. The decision was made against the complete predeclared development-utility gate, not against clinical accuracy.

## Attempt 1: Vision feature-print references

The smallest predeclared cross-set experiment used Apple Vision feature prints and three out-of-fold reference variants.

Best observed results:

- Subject/nonstool balanced accuracy: `0.75`.
- Broad color macro accuracy: `0.12`.
- Bristol exact: `0.35`.
- Bristol exact-or-adjacent: `0.65`.
- Controls failing closed: `4/8`.
- Usable stool images with at least one useful suggestion: `0.45`.
- Concrete correct versus wrong suggestions: `13/18`.
- Complete gate: `false`.

Local-private evidence:

- Summary SHA-256: `33c18af47b9a755972bfb0e1eeb50e2188258c7254d2352bf8a914774d10a432`.
- Evaluation-plan SHA-256: `39276de3179b708b8033f537576eaf25df40564036ea5acf1c80eda2546d4c9e`.

## Attempt 2: one bounded tiny Create ML transition

The fixed four-fold experiment trained 24 small heads and used the same frozen development boundary.

Observed results:

- Subject/nonstool balanced accuracy: `0.975` — pass.
- Bristol exact: `0.55`; exact-or-adjacent: `0.70` — pass.
- Broad color macro accuracy: `0.2066667` — fail against `0.35`.
- Usable stool images with at least one correct suggestion: `19/20` (`0.95`) — pass.
- Concrete correct versus wrong suggestions: `92/31` — pass.
- Red displayed balanced accuracy: `0.50`; positive recall `0`; no correct displayed `Yes` — fail.
- Black displayed balanced accuracy: `0.50`; positive recall `0`; no correct displayed `Yes` — fail.
- Tar-like displayed balanced accuracy: `0.4333`; positive recall `0`; no correct displayed `Yes`; `2/23` negative examples received false `Yes` — fail.
- Mean runtime across 23 runs: `1.187826 s`.
- Maximum resident memory observed: `379027456` bytes.
- Complete gate: `false`.

Local-private evidence hashes:

- Scorecard: `2cd732db062854aad4347dacb89cdace0c94147a642817562cc7addd404b2248`.
- Confusions: `edf6be6b03ced8b010916009f21ff20b0b87b2abd31363d28ea3a96d7915e68e`.
- Protocol: `eac23dd20165e82e34f7007019e68d87123ffc0b53790354627f6f414d0d501a`.
- Raw predictions: `c902077ea74fe6b9e801440878f232fa55e1e4ac0b34e8ceea079bf9448d6dc0`.

## Fresh synthetic-image attempt

The fresh candidate set was not frozen, scored, or published:

- 24 stable IDs were expected; 23 stable-named files existed.
- Only 18/24 files decoded: all A/B images plus two C controls.
- C05 was missing; C06/C07 were zero-byte placeholders; C03/C04/C08 were undecodable; one extra five-byte byproduct existed.
- Four substantive exact duplicate pairs crossed batches.
- The valid A/B images were neutral stone, paint, organic-form, or similar stand-ins rather than mission-conformant realistic stool scenes.
- No blind review artifact existed.

The image-generation workflow used public-safe, nonidentifying prompts, but explicit stool-photo generation was blocked and the neutral substitutes were not accepted as evidence. Raw files remain local pending clarification.

## Product decision

Because the complete gate was conjunctive, partial passes could not justify photo-prefill integration. The archive therefore ships the narrower manual-first lane:

- no Apple classifier or model asset;
- no ordinary-user analysis or prefill;
- retained original photo and complete manual draft;
- editable Yes / No / Not sure fields;
- one final confirmation;
- save, edit, relaunch, history, and photo-inclusive PDF behavior preserved.

These experiments are synthetic, local, non-device development evidence. They do not establish real-photo performance, clinical accuracy, signed-build behavior, or release readiness.
