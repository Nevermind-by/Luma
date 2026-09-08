# Luma

Luma is a native macOS application for keeping installed applications up to date from configurable software sources.

The initial goal is simple: detect applications installed on a Mac, determine their installed versions, compare them with versions available from supported sources, and present actionable updates in one place.

## Project status

Early development — architecture and project foundation.

## Initial MVP

- Discover installed `.app` bundles on macOS.
- Read application metadata and installed versions.
- Normalize and compare software versions.
- Connect an application to one or more update sources.
- Fetch the latest available version from a source.
- Show whether an update is available.
- Allow the user to start a download for an available update.

Installation and fully automatic updating are intentionally outside the first MVP and will be designed after download handling is stable.

## Architecture

Luma is organized around a small core and pluggable update sources. The core must not depend on a specific website or distribution channel.

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the current design.

## Technology

- Swift
- SwiftUI
- macOS
- Xcode

The UI is built with SwiftUI, while macOS-specific capabilities can use AppKit and other system frameworks where appropriate.

## Development

The repository is intentionally kept small at the beginning. New functionality should be introduced in small, focused changes with tests where practical.
