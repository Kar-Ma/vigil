# Vigil

Vigil is an open-source iOS safety app for recording important moments and making the resulting video harder to lose or casually access.

> [!WARNING]
> Vigil is an early prototype, not a finished emergency or evidence-preservation service. Do not rely on it as the only way to protect a recording, contact emergency services, or establish authenticity in a legal proceeding.

## Why Vigil

In a stressful encounter, a person may need to record quickly while worrying that their phone could be taken, damaged, or searched. Vigil is exploring a simple recording experience with protected local storage and optional copies in destinations the person controls.

The project is being developed in public so its privacy and security claims can be inspected rather than taken on trust.

## Current MVP

- One-tap video and audio recording on a physical iPhone
- Rear, front, and simultaneous front-and-rear picture-in-picture recording modes on compatible iPhones
- A saved default recording mode plus a quick mode control before recording begins
- A camera-first interface with Settings and Vault access kept away from the primary record control
- Every completed recording saved to the always-on Vigil Vault
- Face ID or the iPhone passcode required to open the Vault from Settings
- iPhone file protection applied to the Vault directory and recordings
- Playback, sharing, and deletion after the Vault is unlocked
- Optional copies saved to the iPhone Camera Roll
- iCloud and Google Drive destinations shown as “Coming Soon”
- No accounts, ads, analytics, third-party SDKs, or developer-operated server

## Important limitations

- Simultaneous front-and-rear capture depends on Apple MultiCam support and is unavailable on incompatible devices.
- A recording is protected only after iOS finishes writing the video file. Force-quitting the app, losing power, or interrupting an active recording can prevent that file from being finalized.
- Recordings are not currently uploaded while recording. Taking or destroying the phone before another copy is created can still destroy the evidence.
- The Vault authentication screen is an in-app access barrier, not a claim of tamper-proof or forensic-grade storage.
- Deleting Vigil also deletes its local Vault. Camera Roll copies can be viewed and deleted from Photos.
- Vigil does not currently create cryptographic proof of when, where, or by whom a recording was made.
- Recording laws vary by location. The person recording is responsible for understanding the rules that apply to them.
- The iOS Simulator has no usable camera; recording must be tested on an iPhone.

See [PRIVACY.md](PRIVACY.md) and [SECURITY.md](SECURITY.md) for the current data flow and threat model.

## Run the app

### Requirements

- A Mac with Xcode
- An iPhone running iOS 18 or later
- An Apple ID configured in Xcode; a paid Apple Developer membership is not required for basic device testing

### Steps

1. Clone this repository.
2. Open `Vigil.xcodeproj` in Xcode.
3. Select the Vigil target and choose your own Apple development team under **Signing & Capabilities**.
4. If Xcode reports that `com.karma.vigil` is unavailable, change the bundle identifier to a unique value.
5. Connect and select an unlocked iPhone.
6. Press **Run**, then allow camera and microphone access.
7. Enable **Camera Roll** in Vigil Settings if you want an additional Photos copy.

The app uses Apple frameworks and has no package dependencies.

## Roadmap

- Recover interrupted recordings using short, independently playable segments
- Encrypt and upload segments while recording
- Add private iCloud storage
- Add user-controlled Google Drive storage
- Add zoom and lens controls while keeping emergency recording simple
- Add integrity metadata and an exportable chain-of-custody record
- Expand automated tests and physical-device coverage
- Complete accessibility and localization reviews

The repository contains an experimental CloudKit path, but it is disabled and not exposed in the current UI. It must not be described as working protection until its entitlements, failure recovery, and physical-device behavior have been tested.

## Contributing

Thoughtful issues and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) before proposing changes, and avoid overstating the protection offered by an untested feature.

Security concerns should follow the private process in [SECURITY.md](SECURITY.md), not a public issue containing exploit details.

## Built during OpenAI Build Week

The initial prototype was built during OpenAI Build Week with help from Codex using GPT-5.6. Codex assisted with the SwiftUI structure, camera pipeline, protected storage, permissions, crash diagnosis, and build verification. Product decisions and limitations remain documented for public review.

## License

Vigil is available under the [MIT License](LICENSE). See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for the Apple sample-code acknowledgment associated with the multi-camera implementation.
