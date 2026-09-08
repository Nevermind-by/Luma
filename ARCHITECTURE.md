# Luma Architecture

## 1. Product boundary

Luma is an updater client, not an application marketplace.

Its responsibilities are:

1. Discover software installed on the local Mac.
2. Identify each application and its installed version.
3. Resolve an update source for an application.
4. Retrieve the source's current version metadata.
5. Compare installed and available versions.
6. Let the user download an update.
7. Eventually support an installation workflow.

Luma must not assume that every application uses the same distribution channel.

## 2. Architectural principle

The central rule is dependency inversion around update sources.

The core knows about the concept of an `UpdateSource`, but it does not know about AppsTorrent, GitHub, Homebrew, or any other concrete source.

Conceptually:

```text
                    +-------------------+
                    |       UI          |
                    +---------+---------+
                              |
                              v
                    +-------------------+
                    |   Core / Services  |
                    |                    |
                    | AppScanner         |
                    | VersionEngine      |
                    | UpdateManager      |
                    +---------+----------+
                              |
                    UpdateSource protocol
                              |
             +----------------+----------------+
             |                                 |
             v                                 v
   +-------------------+              +-------------------+
   | AppsTorrentSource |              | Future Source     |
   +-------------------+              +-------------------+
```

Adding a new source should not require changes to the application's core update logic.

## 3. Proposed modules

### App

The executable entry point and composition root.

### Core/Models

Pure domain models shared by services and UI.

Initial concepts:

- `InstalledApplication`
- `ApplicationIdentity`
- `SoftwareVersion`
- `UpdateCandidate`
- `DownloadOption`
- `UpdateSourceDescriptor`

Models should contain domain data and rules, not network or UI concerns.

### Core/Services

Application-independent business logic.

Initial services:

- `ApplicationScanner`
- `VersionComparator`
- `UpdateManager`
- `DownloadManager`

### Sources

Adapters for external update sources.

The first implementation will be `AppsTorrentSource`.

A source adapter is responsible for fetching source data, parsing source-specific data, converting it into Luma domain models, and reporting source-specific errors.

It must not manipulate SwiftUI state directly.

### Persistence

Local storage for source mappings, user preferences, cached metadata, and update state where needed.

The concrete storage technology will be selected after the domain model is established.

### UI

SwiftUI views and presentation state.

The UI should consume domain/service state and trigger application actions. Network requests and HTML parsing must never live directly inside views.

### Tests

Unit and integration tests for version parsing/comparison, application metadata extraction, source parsing, source-to-application matching, update detection, and download behavior.

## 4. Application identity

A display name is not sufficient to uniquely identify an installed application.

Where available, Luma should use the macOS bundle identifier as the primary local identity and keep the bundle path as installation metadata.

The source mapping layer should support aliases because a source's product name and a bundle's display name may differ.

## 5. Version model

Versions are external data and cannot be assumed to follow one universal semantic-versioning scheme.

Luma should therefore keep version parsing/comparison in a dedicated component instead of scattering string comparisons through the application.

The comparator will support multiple version shapes and explicitly document its comparison policy.

## 6. Networking and source access

Source access is asynchronous and isolated behind service protocols.

For a source that requires browser execution or session state, the adapter may use a specialized implementation later. That complexity must remain inside the source adapter and must not leak into the core.

## 7. Download and installation boundary

Downloading and installing are separate responsibilities.

```text
Update detection
      |
      v
DownloadManager
      |
      v
Downloaded artifact
      |
      v
Installer (future)
```

The first MVP stops at a successfully downloaded artifact and a clear hand-off to the user.

## 8. Error handling

Errors should be typed and meaningful at module boundaries.

Examples:

- application metadata unavailable;
- source unavailable;
- source parsing failed;
- version could not be interpreted;
- matching is ambiguous;
- download failed;
- permission denied.

The UI should turn these into user-facing messages without depending on low-level error strings.

## 9. Security and trust boundaries

Downloaded artifacts are untrusted input.

Luma should not silently execute arbitrary downloaded code. Automatic installation, code-signing validation, quarantine handling, and any privileged operation require an explicit design phase.

## 10. Initial folder structure

The intended source tree is:

```text
Luma/
├── Luma.xcodeproj
├── App/
├── Core/
│   ├── Models/
│   ├── Services/
│   └── Utilities/
├── Sources/
│   └── AppsTorrent/
├── Persistence/
├── UI/
└── Tests/
```

The folders are architectural boundaries, not a requirement to create every directory before it is needed.

## 11. Development strategy

We build from the inside out:

1. Repository and project foundation.
2. Domain models.
3. Installed-app scanner.
4. Version engine.
5. Source abstraction.
6. AppsTorrent source adapter.
7. Matching and update detection.
8. Download manager.
9. SwiftUI interface.
10. Installation workflow.
11. Background checks, notifications, releases, and CI.

Each step should leave the project in a runnable state.
