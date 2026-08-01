# Track B prompt-source recovery history

**Status:** SOURCE BLOCKER RESOLVED on 2026-07-31. This document remains as recovery evidence; current runtime progress is recorded in `PLAN.md` and later `PRECHECK.md`.

## Missing required sources

- `GI_Journal_Preflight_Prompt_v3_2_1.md` (Prompt A)
- `GI_Journal_Build_Prompt_v3_2_1.md` (Prompt B)

Track B is explicitly governed by Prompt A. Its exact artifact names, pinned package versions, model identifiers/revisions, server invocation, production schema, acceptance assertions, and PRECHECK format must come from that frozen text. The orchestration brief is not a substitute.

## Bounded recovery searches completed

1. Workspace inventory: neither filename is present in the supplied workspace; `gi-journal/` was empty.
2. Local document search: searched the workspace documents directory for both exact names and related `GI_Journal*Prompt*v3*` / `GI*Journal*` filenames; no exact source file was found.
3. Codex memory registry and relevant Chronicle summaries: they confirm the two filenames and high-level Mac-fallback intent only. They do not contain either prompt verbatim.
4. Recent-work screen history: showed the filenames in the orchestrator/Drive context but not a readable complete prompt body.
5. Connected Google Drive: searched the exact preflight filename and the concise query `GI Journal Preflight Prompt` among files viewed by the user; both returned zero results.

## Prompt-independent environment inventory

Recorded on 2026-07-31 (America/New_York):

| Item | Result |
| --- | --- |
| Host architecture | `arm64` |
| macOS | 26.6 (25G72) |
| Xcode | 26.6 (17F113) |
| System Python | `/usr/bin/python3`, 3.9.6 |
| Available workspace disk | 270 GiB |

## Original operator ask (resolved)

Please place **unchanged exact copies** of both frozen Markdown prompts in this workspace root (or provide their Google Drive links/file IDs):

```text
GI_Journal_Preflight_Prompt_v3_2_1.md
GI_Journal_Build_Prompt_v3_2_1.md
```

Exact frozen sources are now staged in this directory. Prompt A execution has resumed. The Wi-Fi-off proof remains operator-only.

## Risks if work proceeds without the frozen prompts

- Downloading a plausible Gemma artifact could consume substantial disk/time while failing the prompt's required revision or hash.
- A generic MLX-VLM server command might bind incorrectly or use a non-production request schema.
- Inventing tests or `PRECHECK.md` fields would violate the frozen-scope and honesty contract.
