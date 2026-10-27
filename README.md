# Welcome Gate — your ABB-Welcome door entry on the Apple Watch

An Apple Watch app that mirrors the iPhone **Welcome App** screens (Controllo
accessi with the Relè, Dispositivi, Home with Preferiti) for **your own** ABB-Welcome
installation, plus a small iPhone companion that sets it up.

The watch asks **Home Assistant** to press the entities of the community
ABB-Welcome integration; Home Assistant handles the pairing and the SIP unlock
(see `docs/abb-welcome-protocol.md` for why). It works from anywhere you can
reach Home Assistant.

## What's here

```
.claude/skills/app-reverse-engineer/   Reusable skill: extract a mobile app's
                                        API by traffic capture (REA-inspired).
docs/home-assistant-setup.md            Start here: HA integration, token, setup.
docs/abb-welcome-protocol.md            What is known / still open.
docs/traffic-capture-playbook.md        Fallback: capture your app's traffic.
project.yml                             XcodeGen manifest (iOS + watchOS apps).
Sources/Shared/                         GateClient, Home Assistant client, Keychain.
Sources/iOS/                            iPhone companion (connect / pick / test / sync).
Sources/Watch/                          The watch app (Home, Dispositivi,
                                        Controllo accessi screens).
```

## How it works

```
Apple Watch ──HTTPS + token──▶ Home Assistant ──SIP on your LAN──▶ ABB gateway
     ▲
     │ WatchConnectivity (encrypted, one-time setup payload)
  iPhone companion  ◀── address + token + entity choices
```

- **iPhone app**: enter the Home Assistant address and token, load its entities,
  choose the entity for each relay (*Cancello-citofono*, *Basculante-citofono*) and
  the station picture, **Prova** each relay, then **Invia al Watch**.
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

Follow [`docs/home-assistant-setup.md`](docs/home-assistant-setup.md): install the
integration in Home Assistant, make it reachable from outside, create a token,
then configure the iPhone app and **Invia al Watch**.

**Status:** the code has not been compiled (no Xcode where it was written) and not
tested against real hardware. Whether the **Relè** appear as Home Assistant
entities on your system is still to be checked.

## Security notes

- The Home Assistant token lives only in the device **Keychain** and is synced to
  the watch over encrypted WatchConnectivity. It is never committed (see
  `.gitignore`). Revoke it in Home Assistant if a device is lost.
- Use HTTPS when reaching Home Assistant from outside your network.
- Everything is for **your** installation. Don't point it at anything you don't own.
