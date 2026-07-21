# Vigil

Vigil is an open-source iOS safety app for preserving recordings of important moments. Its goal is to make evidence harder to lose if a phone is taken, lost, or damaged.

This repository is an early prototype built during OpenAI Build Week. It is not yet a finished personal-safety product.

## What works today

- One-tap video and audio recording on a physical iPhone
- Local recordings stored inside the Vigil Vault with iPhone file protection
- Face ID or iPhone passcode required once when opening the Vigil Vault
- Playback, file size, saved date, upload state, and guarded deletion
- Optional Camera Roll copies
- Standard iOS share sheet for unlocked recordings
- A Settings screen for Camera Roll and Vigil Vault, with iCloud and Google Drive marked “Coming soon”
- A local fallback copy when an external save fails

## Important limitations

- The iOS Simulator has no usable camera; recording must be tested on an iPhone.
- CloudKit code is implemented but not exposed yet; iCloud remains “Coming soon” until the project has an Apple Developer membership and iCloud entitlement.
- iCloud upload begins after a recording finishes. A later version should upload encrypted segments while recording.
- This prototype records the back camera. Simultaneous front-and-back recording is planned for supported devices.

## Run the app

1. Open `Vigil.xcodeproj` in Xcode.
2. Select the Vigil target, then choose your Apple development team under Signing & Capabilities.
3. Connect and select an iPhone.
4. Press Run and allow camera and microphone access.

The project targets iOS 18 or later and uses only Apple frameworks.

## Enable CloudKit after membership activation

1. In Signing & Capabilities, add the iCloud capability.
2. Enable CloudKit and select or create `iCloud.com.karma.vigil`.
3. Add `CLOUDKIT_ENABLED` under Swift Active Compilation Conditions for Debug and Release.
4. Run on a signed device, enable iCloud in Vigil Settings, and make a short test recording.

Cloud recordings use each person's private CloudKit database. They are not placed in a developer-owned shared video bucket.

## Built with Codex

Codex using GPT-5.6 helped turn the product idea into the SwiftUI app structure, camera pipeline, protected local storage, CloudKit upload path, settings model, crash diagnosis, and build verification. Development decisions and limitations are documented openly so the project can be reviewed and improved by the community.

## Contributing

Issues and pull requests are welcome. Please avoid presenting this prototype as guaranteed evidence protection until interruption recovery, encrypted segmented uploads, authentication, and extensive device testing are complete.
