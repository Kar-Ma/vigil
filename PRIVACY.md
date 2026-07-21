# Privacy

This document describes the current open-source Vigil MVP as of July 21, 2026. It is a technical description, not an App Store privacy label or legal privacy policy for a future distributed service.

## Current data flow

Vigil does not require a Vigil account or send recordings to a developer-operated server. It contains no advertising, analytics, or tracking. Google Sign-In is included only for the optional Google Drive destination.

Completed recordings are stored in the app’s local Application Support directory. Vigil applies iPhone file protection to the Vault directory and each completed recording. Opening the Vault from Settings also requires Face ID or the iPhone passcode before showing its contents.

If the Camera Roll option is enabled, Vigil asks iOS for add-only Photos permission and saves an additional copy to Photos. That copy is managed by the Photos app and is not protected by the Vigil Vault screen.

New recordings contain non-location capture context in the video file: UTC start time, a random recording ID, the selected camera mode, and the Vigil app version. Vigil does not embed the person’s name, account, device identifier, or location.

When a person uses the share button, they can share the untouched Vault original or ask Vigil to create a temporary stamped copy. The stamped copy visibly includes the Vigil mark, a UTC timestamp, and the short recording ID; the original remains unchanged. iOS then presents the standard share sheet. The temporary stamped file is removed after the share sheet closes, while anything the person sends or saves is controlled by the chosen destination and its privacy practices.

Screen Curtain is an optional local display-privacy control. It covers the live camera preview and temporarily dims the iPhone display; it does not change the recorded video, send data anywhere, hide iOS privacy indicators, or remove Vigil’s visible recording status. The previous display brightness is restored when the curtain closes or Vigil leaves the foreground. When VoiceOver is running, Apple’s system Screen Curtain gesture takes priority.

If Google Drive is enabled, Vigil asks the person to sign in with Google and requests the `drive.file` permission. This permission lets Vigil create and manage only the files it creates or that the person explicitly opens with Vigil; it does not give Vigil general read access to the rest of the person’s Drive. After a recording is completed, Vigil creates or finds a visible `Vigil` folder in that account and uploads an additional video copy directly from the iPhone to Google. The recording does not pass through a Vigil-operated server. Google’s privacy practices apply to the sign-in session and uploaded copy.

## Permissions

- **Camera:** captures video.
- **Microphone:** captures audio with the video.
- **Photos — Add Only:** creates an optional Camera Roll copy. Vigil does not need to read the photo library.
- **Face ID:** unlocks the Vigil Vault. If Face ID is unavailable, iOS may offer the device passcode.
- **Google Drive (`drive.file`):** when enabled, signs the person in and lets Vigil create and manage its own uploaded recordings in that account.

Vigil does not currently request location permission or collect location for a recording.

## Cloud features

iCloud is marked “Coming Soon” and does not receive recordings in the current UI. The repository includes disabled CloudKit experimentation for future development; it is not active in the shipped MVP configuration.

Google Drive is optional. Uploading begins only after iOS has finalized a recording; Vigil does not currently stream an in-progress recording or retry uploads durably in the background. Turning Google Drive off signs out the local Google session and stops new uploads. It does not delete copies already uploaded, and it is not represented as revoking the app’s grant from the person’s Google Account.

Any future cloud feature must document what is uploaded, when it is uploaded, who can access it, how deletion works, and whether the provider can read the recording before that feature is enabled.

## Deletion and retention

Vault recordings remain on the device until the person deletes them inside Vigil or removes the app. Deleting the app removes its local Vault. Camera Roll, Google Drive, and shared copies must be deleted separately from their respective destinations. A person can also manage or revoke Vigil’s Google access from their Google Account.

## Scope and limitations

Face ID protects access through the Vigil interface; it does not make the files immune to operating-system compromise, device seizure, app deletion, backups, or advanced forensic access. An active recording can also be lost if iOS cannot finalize the file. Embedded capture context and visible stamps can be altered with editing tools and must not be treated as independent proof of authenticity.

Before public distribution, this document must be reconciled with the final App Store privacy disclosures and Google OAuth consent-screen links. Any future diagnostics, analytics, developer server, or additional account data must be documented before release.
