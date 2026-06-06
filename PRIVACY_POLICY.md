# Beam — Privacy Policy

Last updated: 6 June 2026

Beam is a peer-to-peer file-sharing app developed under the Atman Project, an open-source initiative founded by Youngjoon Lee.

## What we collect

Nothing. Beam has no account system, no sign-in, no telemetry, no analytics, no crash reporting service, and no Beam-operated backend.

## How transfers work

When you send a file with Beam, your device connects directly to the recipient's device using iroh (a peer-to-peer transport built on QUIC). The connection is end-to-end encrypted with TLS 1.3. Files are not uploaded to or stored on any server we control.

If a direct connection between two devices cannot be established (for example, both are behind restrictive NATs), iroh's default public relay is used as a path between them. Even in that case, only encrypted QUIC packets pass through the relay — the relay cannot read the file contents.

## Permissions

- **Local Network.** Used to discover devices on the same Wi-Fi via mDNS so you can transfer without going through the internet.
- **Camera.** Used to scan a QR code shown by another Beam device.
- **Photos (read).** Used so you can pick photos to send while preserving their original encoding (HEIC stays HEIC).
- **Photos (add).** Used to save received photos and videos to your library.

These permissions are used only for the actions you explicitly take in the app. None of the data leaves your device except as part of the transfer you initiated.

## Children

Beam is not directed at children under 13 and we do not knowingly collect data from anyone.

## Contact

If you have a question about this policy, file an issue at <https://github.com/atman-project/beam-ios/issues>.
