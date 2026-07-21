# Contributing to Vigil

Thank you for helping improve Vigil. This project deals with safety-sensitive recordings, so accuracy and restraint matter as much as new features.

## Before starting

- Search existing issues and pull requests.
- Open an issue before a large architectural, cloud-storage, cryptography, or product-behavior change.
- For a security vulnerability, follow [SECURITY.md](SECURITY.md) instead of posting details publicly.

## Local setup

1. Fork and clone the repository.
2. Open `Vigil.xcodeproj` in Xcode.
3. Choose your own Apple development team and, if needed, a unique bundle identifier.
4. Build on an iPhone running iOS 18 or later. The Simulator cannot validate camera behavior.

## Pull requests

Keep each pull request focused and explain:

- The problem being solved
- The user-visible behavior before and after
- Privacy, security, storage, and failure-mode implications
- Tests performed, including the iPhone model and iOS version for camera-related work
- Screenshots or a short screen recording for interface changes, with personal content removed

Please also:

- Follow the existing Swift and SwiftUI style.
- Use Apple frameworks where practical and justify new dependencies.
- Add or update tests when behavior can be tested automatically.
- Update README, privacy, or security documentation when claims or data flows change.
- Never include real sensitive recordings, secrets, signing files, or provisioning profiles.
- Avoid claiming that an experimental feature guarantees safety, evidence preservation, anonymity, or legal admissibility.

## Design principles

- A completed recording should always remain in the Vigil Vault, regardless of optional destinations.
- Failure must be visible without exposing sensitive details.
- Defaults should minimize data loss and unnecessary data collection.
- People under stress should not need to understand storage architecture.
- Security and privacy claims must stay narrower than the tested behavior.

## License

By contributing, you agree that your contribution may be distributed under the repository’s [MIT License](LICENSE).
