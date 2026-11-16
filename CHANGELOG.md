# Changelog

## 0.1.0 — first release

- Menu bar text `MEM NN%` with warning (yellow) and critical (red) levels.
- Notifications when the level goes up.
- Menu with memory numbers, top apps and top processes.
- Command line flags: `--status`, `--test-notify`, `--login-item`.
- Launch at login.
- JSON log in `~/Library/Logs/MemWatch.log`.
- Russian README (README.ru.md).
- Release workflow: pushing a `v*` tag builds the app and publishes a GitHub Release with a zip and its SHA-256.
- The app is a universal binary (arm64 and x86_64).
- `Scripts/bundle.sh`: `--no-install` (or `MEMWATCH_NO_INSTALL=1`) builds the app without installing it; `MEMWATCH_VERSION` sets the app version.
- README: Download and Releasing sections.
