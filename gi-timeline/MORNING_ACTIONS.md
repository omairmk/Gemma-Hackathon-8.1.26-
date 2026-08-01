# GI Timeline morning owner actions

Updated: 2026-08-01 00:30 EDT (America/New_York)

The Simulator real-Gemma POC and UI acceptance are proven. The fresh physical-iPhone check passed through pre-signing discovery: the phone is booted, Developer Mode is enabled, it is paired and unlocked, developer services are ready, and Xcode sees it as an arm64 destination. The remaining signing step is owner-only; the agent will not enter a Mac password, iPhone passcode, Apple ID password, or other credential.

## One owner action

Unlock the Mac locally if needed. In Xcode, select the GI Timeline **Debug** app target, open **Signing & Capabilities**, and choose your Apple development team. Resolve any Apple credential prompt yourself, then run the physical build/install steps in `DEMO_RUNBOOK.md`. Do not send a password, passcode, certificate, identity detail, or token to Codex.

Status: **CONFIRMED BLOCKER.** The Debug target's `DEVELOPMENT_TEAM` is blank; this is the sole current blocker to starting the physical Debug build.

## Follow-up checks before the model copy

- Connect the iPhone by cable, unlock it, tap **Trust** if asked, and leave it connected. The live transport currently reports `localNetwork`, so cable presence has not been confirmed.
- In **Settings -> General -> iPhone Storage**, confirm roughly 12 GB remains available for the staged model, installed copy, and runtime cache. Available space has not yet been confirmed.

These are follow-up readiness checks, not substitutes for selecting the development team.

No license acceptance, purchase, account creation, TestFlight/App Store submission, security weakening, or access to personal health photos is requested.
