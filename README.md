# Welcome Gate — open your ABB-Welcome door from your Apple Watch

A personal Apple Watch client for **your own** ABB-Welcome door-entry system.
It replays the authenticated "open door" request your official **Welcome App**
already makes, through ABB's **Welcome IP cloud API**, so the watch works
anywhere it has internet.

This is an interoperability project for a system you control — the same idea as
the open-source Home Assistant ABB-Welcome integrations. It does not bypass any
security: it reuses the token from your own myBUILDINGS account.

## What's here

```
.claude/skills/app-reverse-engineer/   Reusable skill: extract a mobile app's
                                        API by traffic capture (REA-inspired).
docs/abb-welcome-protocol.md            What the door-open call looks like.
docs/traffic-capture-playbook.md        The one manual step: capture it once.
project.yml                             XcodeGen manifest (iOS + watchOS apps).
Sources/Shared/                         GateClient, ABB cloud client, Keychain.
Sources/iOS/                            iPhone companion (pair / test / sync).
Sources/Watch/                          The watch app (the Open button).
```

## How it works

```
Apple Watch ──(Bearer token)──▶ ABB Welcome IP cloud ──▶ your door opener
     ▲                                   (write door-opener datapoint)
     │ WatchConnectivity (encrypted, one-time pairing payload)
  iPhone companion  ◀── you paste values from a one-time traffic capture
```

- **iPhone app**: you enter the endpoint + door-opener IDs + a current token
  from your capture, tap **Test** to confirm the door opens, then **Send to
  Watch**.
- **Watch app**: one big **Open** button; calls the cloud directly and refreshes
  its token automatically. Haptic + checkmark on success.
- Swap in a local-LAN (SIP) fast-path later behind the same `GateClient`.

## Build & install (needs a Mac with Xcode — Apple requirement)

```bash
brew install xcodegen          # one-time
cd WelcomeAppleWatch
xcodegen generate              # creates WelcomeGate.xcodeproj from project.yml
open WelcomeGate.xcodeproj
```

In Xcode: select your **Development Team** under Signing for both targets
(change the `com.example.*` bundle IDs to your own), then build/run the iPhone
target to your phone, and the **Watch App** target to your watch.

> No Mac/Xcode in this repo's build container, so the project can't be compiled
> here — building on macOS is the only path Apple allows for watch apps.

## Get it working (the one manual step)

1. Do the **one-time traffic capture** in
   [`docs/traffic-capture-playbook.md`](docs/traffic-capture-playbook.md) to
   read off your endpoint, door-opener IDs, and a token.
2. Enter those in the iPhone app → **Test** (door should open) → **Send to
   Watch**.
3. Tap **Open** on the watch.

If your access point has firmware ≥ 6.36 you can also enable ABB's documented
Welcome IP cloud API (app → Preferences → Connection & APIs → MyBuildings) and
read the official endpoints instead of capturing — same values, same code.

## Security notes

- Tokens live only in the device **Keychain** and are synced to the watch over
  encrypted WatchConnectivity. They are never committed (see `.gitignore`).
- Everything uses **your** myBUILDINGS account and **your** door. Don't point it
  at anything you don't own.
