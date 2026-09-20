# Security

## Trust boundaries

Luma interacts with three kinds of untrusted external data:

1. Web content from update sources.
2. Downloaded installer artifacts.
3. Application metadata discovered on the local Mac.

Network access and HTML parsing remain inside source-specific adapters. UI code does not own network or parsing concerns.

## AppsTorrent session

AppsTorrent authentication is handled through the native WebKit session. Credentials, cookies, and session tokens must not be committed, logged, or copied into ordinary application settings.

Persistent WebKit website data is used so a user can keep an authenticated browser session between launches.

## Downloaded artifacts

Downloaded installers are treated as untrusted. Luma may save them and open them through macOS Launch Services, but it must not silently execute downloaded code.

Luma must not:

- disable Gatekeeper;
- disable or remove quarantine attributes as a shortcut around macOS security;
- delete an existing application automatically to make an external installer succeed;
- install privileged components without an explicit, reviewed design.

## Sandboxing

The app uses App Sandbox with only the file/network capabilities currently required by the implementation:

- network client access;
- Downloads folder read/write access;
- user-selected file read/write access.

When a new capability is needed, prefer the narrowest entitlement that satisfies the user-visible feature.

## Release security

The CI release archive is currently unsigned by design. A distributable release must add proper Apple code signing and notarization before publication. The hardened runtime is already enabled in the app target and is validated by CI.

Security-related changes should include tests or CI validation when practical.
