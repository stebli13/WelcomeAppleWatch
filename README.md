# Welcome Gate — your ABB-Welcome door entry on the Apple Watch

An Apple Watch app that mirrors the iPhone **Welcome App** screens (Controllo
accessi with the Relè, Dispositivi, Home with Preferiti) for **your own** ABB-Welcome
installation, plus a small iPhone companion that sets it up.

The iPhone sends the commands itself, over SIP/TLS to the ABB cloud server,
exactly as verified with `tools/abb_probe.py` (see `docs/direct-gateway.md`).
The watch asks the iPhone. It works at home and away, with nothing running at
home.

## What's here

```
.claude/skills/app-reverse-engineer/   Reusable skill: extract a mobile app's
                                        API by traffic capture (REA-inspired).
docs/direct-gateway.md                  Start here: probe, export, import, use.
docs/abb-welcome-protocol.md            What is known / still open.
docs/traffic-capture-playbook.md        Fallback: capture your app's traffic.
project.yml                             XcodeGen manifest (iOS + watchOS apps).
Sources/Shared/                         Models, GateClient, Keychain.
Sources/iOS/SIPClient.swift             SIP/TLS client for the ABB cloud server.
Sources/iOS/                            iPhone companion (connect / pick / test / sync).
Sources/Watch/                          The watch app (Home, Dispositivi,
                                        Controllo accessi screens).
```

## How it works

```
Apple Watch ──WatchConnectivity──▶ iPhone ──SIP/TLS──▶ sip.my.busch-jaeger.de:5061 ──▶ gateway
                                     ▲
                                     └─ one-time import of the pairing file made on the Mac
```

- **iPhone app**: **Importa file dal Mac** (made by `abb_probe.py export`),
  **Prova** each relay (Cancello, Basculante, Portoncino), then **Invia al Watch**.
- **Watch app**: **Controllo accessi** opens first (Relè + Posto esterno),
  **Dispositivi** shows the station tile with its picture, **Home** has your
  **Preferiti** for one-tap opening. Switch screens with the Digital Crown. Tap a
  relay for its big **Apri** button, or swipe it left to open from the list.
  Haptic + green check on success.

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

## Get it working

Follow [`docs/direct-gateway.md`](docs/direct-gateway.md): pair with the probe on
the Mac, `export`, import the file in the iPhone app, then **Invia al Watch**.

**Status:** the commands are verified with the probe on the real installation
(all three, through the ABB cloud server). The Swift code has not been compiled
yet (no Xcode where it was written).

## Security notes

- The SIP password, certificate and key live only in the iPhone **Keychain**;
  the watch gets names and commands only. The export file is encrypted with
  your passphrase; delete it after the import. If a phone is lost, remove its
  `welcomegate-…` client from the Welcome App.
- Everything is for **your** installation. Don't point it at anything you don't own.
