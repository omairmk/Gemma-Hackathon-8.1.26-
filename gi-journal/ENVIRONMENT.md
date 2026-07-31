# Mac fallback environment inventory

This file records only prompt-independent host facts. It is not a runtime preflight and does not constitute a GO/NO-GO decision.

- Recorded: 2026-07-31, America/New_York
- CPU architecture: `arm64`
- macOS: 26.6 (25G72)
- Xcode: 26.6 (17F113)
- System Python: `/usr/bin/python3` — 3.9.6 (not compliant with Prompt A)
- Available disk at workspace mount: 270 GiB

## Workspace-local compliant runtime

- CPython 3.12.11 source distribution downloaded from `python.org` into `.python-src/`; SHA-256: `7b8d59af8216044d2313de8120bfc2cc00a9bd2e542f15795e1d616c51faf3d6`.
- OpenSSL 3.5.2 source distribution downloaded from `openssl.org` into `.deps-src/`; SHA-256: `c53a47e5e441c930c3928cf7bf6fb00e5d129b630e0aa873b08258656e7345ec`.
- OpenSSL was built workspace-locally in `.openssl/`; CPython was rebuilt against it in `.python-tls/`. The virtual environment is `.venv/` and reports `OpenSSL 3.5.2 5 Aug 2025`.
- All toolchain sources, builds, virtual environments, and Hugging Face caches remain ignored and inside this workspace.
