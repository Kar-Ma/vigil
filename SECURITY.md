# Security

Vigil handles potentially sensitive recordings. Clear threat modeling and careful reporting are essential.

## Supported version

Security work currently targets the latest commit on the `main` branch. No production release is supported yet.

## Report a vulnerability privately

Use **Security → Report a vulnerability** on the GitHub repository when private vulnerability reporting is available.

If that option is unavailable, open a public issue asking the maintainer to establish a private contact channel. Do not include exploit details, private recordings, personal data, device identifiers, or credentials in that issue.

Please include, through the private channel:

- The affected commit or version
- The iPhone model and iOS version
- Reproduction steps and expected behavior
- The security or privacy impact
- Any suggested mitigation

Please allow reasonable time for investigation before public disclosure.

## Current threat model

The MVP aims to:

- Keep every completed recording in an app-controlled Vault by default
- Require iOS owner authentication before displaying Vault contents
- Use iPhone file protection for completed local recordings
- Make an optional additional copy in Photos
- Make an optional additional copy in a folder controlled by the person in Google Drive

The MVP does **not** yet guarantee protection against:

- Force-quitting, power loss, or interruption before a recording is finalized
- Deletion of the Vigil app or erasure of the device
- An attacker who controls the unlocked iPhone or knows its passcode
- Operating-system compromise, advanced forensic extraction, or malicious device management
- Deletion or alteration of a Camera Roll or shared copy
- Failed, interrupted, delayed, or manually deleted Google Drive uploads
- Compromise of the connected Google account or access by the cloud provider
- Fabrication, editing, or disputes about a recording’s time, location, or authenticity
- Loss of the phone before an external copy exists

Security claims should be based on reviewed and tested behavior. Google Drive currently receives completed files, not live encrypted segments. Please do not describe planned iCloud storage, live upload, encryption, segmentation, or integrity features as protection that exists today.

## Development hygiene

- Never commit recordings, credentials, signing certificates, provisioning profiles, or personal test data.
- Keep third-party dependencies to a minimum and explain why each is necessary.
- Treat changes to recording finalization, storage, authentication, sharing, deletion, and cloud transfer as security-sensitive.
- Test failure paths on a physical iPhone, including denied permissions, low storage, backgrounding, interruption, and loss of connectivity.
