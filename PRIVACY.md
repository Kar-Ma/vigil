# Privacy

This document describes the current open-source Vigil MVP as of July 21, 2026. It is a technical description, not an App Store privacy label or legal privacy policy for a future distributed service.

## Current data flow

Vigil does not currently require an account or send recordings to a developer-operated server. It contains no advertising, analytics, tracking, or third-party SDKs.

Completed recordings are stored in the app’s local Application Support directory. Vigil applies iPhone file protection to the Vault directory and each completed recording. The Vault tab also requires Face ID or the iPhone passcode before showing its contents.

If the Camera Roll option is enabled, Vigil asks iOS for add-only Photos permission and saves an additional copy to Photos. That copy is managed by the Photos app and is not protected by the Vigil Vault screen.

When a person uses the share button, iOS presents the standard share sheet. The person chooses where the recording is sent; the chosen destination’s privacy practices then apply.

## Permissions

- **Camera:** captures video.
- **Microphone:** captures audio with the video.
- **Photos — Add Only:** creates an optional Camera Roll copy. Vigil does not need to read the photo library.
- **Face ID:** unlocks the Vault tab. If Face ID is unavailable, iOS may offer the device passcode.

## Cloud features

iCloud and Google Drive are marked “Coming Soon” and do not receive recordings in the current UI. The repository includes disabled CloudKit experimentation for future development; it is not active in the shipped MVP configuration.

Any future cloud feature must document what is uploaded, when it is uploaded, who can access it, how deletion works, and whether the provider can read the recording before that feature is enabled.

## Deletion and retention

Vault recordings remain on the device until the person deletes them inside Vigil or removes the app. Deleting the app removes its local Vault. Camera Roll and shared copies must be deleted separately from their respective destinations.

## Scope and limitations

Face ID protects access through the Vigil interface; it does not make the files immune to operating-system compromise, device seizure, app deletion, backups, or advanced forensic access. An active recording can also be lost if iOS cannot finalize the file.

If a distributed version of Vigil later adds accounts, cloud storage, diagnostics, or analytics, this document and the applicable App Store disclosures must be updated before release.
