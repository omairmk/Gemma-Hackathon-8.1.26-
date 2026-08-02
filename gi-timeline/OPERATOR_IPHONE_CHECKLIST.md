# Operator iPhone checkpoint

> **Historical snapshot:** This checkpoint predates the final disclosed physical bridge. Use the repository root `README.md` and `DEVICE_INFERENCE_REPORT.md` for current claims.

```text
DEVICE_INFERENCE_STATUS: BLOCKED
APP_END_TO_END_STATUS: NOT_RUN
```

## One action now

- [ ] Reconnect the iPhone by cable, unlock it, and leave it awake on the Home Screen.

Expected result: the phone appears as an available iOS destination in Xcode without an Unlock, Trust, Developer Mode, or developer-profile prompt.

Do not send Codex a passcode, Apple credential, certificate, signing value, token, or device identifier.

## Ready behind this checkpoint

- Current optimized signed `GITimeline Hackathon` app: **PASS**.
- Exact embedded Gemma 4 E4B identity and receipt: **PASS**.
- Current-source real-Gemma arm64 Simulator smoke, normal flow, and relaunch: **PASS**.
- Host 14/14, app 37/37, final UI 3/3, Release isolation: **PASS**.
- Current optimized physical install/launch: **BLOCKED** because the phone is absent.
- Physical brown/green/control inference, review/save/History/relaunch: **BLOCKED**.
- Airplane Mode: **BLOCKED** until the online physical sequence passes.

Once the phone appears, install the current verified app without uninstalling or deleting app data, then run the three synthetic-only commands in `DEMO_RUNBOOK.md`. Airplane Mode is a separate owner action requested only after the online physical sequence passes.
