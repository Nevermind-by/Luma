# Luma

Luma is a native macOS application for keeping installed applications up to date from configurable software sources.

The initial goal is simple: detect applications installed on a Mac, determine their installed versions, compare them with versions available from supported sources, and present actionable updates in one place.

## Project status

Working MVP with release-hardening in progress.

The current implementation includes:

- Discovery of installed `.app` bundles.
- Application identity and installed-version extraction.
- Dedicated version comparison.
- AppsTorrent source integration with a native `WKWebView` session.
- AppsTorrent release parsing and distribution-variant matching.
- Update detection.
- Download management with persisted download-location access.
- Persisted pending installer state.
- External installer hand-off for `.dmg`, `.pkg`, and other installer artifacts.
- Post-installer version monitoring so Luma can detect completion without modifying the existing app automatically.
- Unit tests and GitHub Actions build/test/archive packaging.

The current GitHub Actions release artifact is intentionally **unsigned**. Developer ID signing and notarization are the next distribution step. Release ZIP/DMG artifacts are accompanied by a SHA-256 checksum manifest.

## Update lifecycle

```text
Installed app
    ↓
Check source
    ↓
Update available
    ↓
Download artifact
    ↓
Open external installer
    ↓
User completes installation in macOS
    ↓
Luma detects the installed version
```

Luma does not silently remove the currently installed application and does not disable macOS security controls such as Gatekeeper or quarantine handling.

## Architecture

Luma is organized around a small core and pluggable update sources. The core must not depend on a specific website or distribution channel.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the current design.

## Security boundary

Downloaded artifacts are treated as untrusted input. Luma keeps source-session state inside the persistent WebKit data store, does not store credentials or cookies in the repository, and uses App Sandbox file-access entitlements for its documented file operations.

The external installer remains responsible for its own installation UX and macOS security prompts.

## Technology

- Swift
- SwiftUI
- macOS
- Xcode

The UI is built with SwiftUI, while macOS-specific capabilities can use AppKit and other system frameworks where appropriate.

## Development

The repository is intentionally kept small. New functionality should be introduced in focused changes with tests for non-trivial parsing, comparison, persistence, and lifecycle behavior.

Run the Xcode scheme `Luma` locally to build and test. GitHub Actions runs the same project build and test flow on macOS.
