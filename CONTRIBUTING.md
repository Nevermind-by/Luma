# Contributing to Luma

## Development principles

- Keep domain logic independent from SwiftUI.
- Keep concrete update sources behind source protocols.
- Prefer small, focused changes.
- Add tests for non-trivial parsing and comparison logic.
- Do not commit secrets, credentials, downloaded installers, or local machine state.
- Do not make destructive installation behavior automatic without an explicit design and review.

## Commit style

Use short imperative commit messages that describe the change.

Examples:

- `Initialize Xcode project`
- `Add installed application model`
- `Implement version comparator`
- `Add AppsTorrent parser`
- `Add update detection`

## Branches

Use a short-lived feature branch for meaningful changes and merge through pull requests when practical.
