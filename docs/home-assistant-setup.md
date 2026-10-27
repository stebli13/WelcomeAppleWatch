# Setup: ABB-Welcome → Home Assistant → Apple Watch

The watch app does not talk to ABB directly. It asks **Home Assistant** to press
the entities of the ABB-Welcome integration, and Home Assistant does the pairing
and the SIP unlock. Everything here is for **your own** installation.

```
Apple Watch ──HTTPS + token──▶ Home Assistant ──SIP on your LAN──▶ ABB gateway ──▶ gate
```

## 1. Home Assistant with the ABB-Welcome integration

You need Home Assistant running at home all the time (Raspberry Pi, mini PC,
NAS…). Then install a community integration through HACS:

- `rankjie/ha-abb-welcome` (also `johnnyh1975/ha-abb-welcome`)
- or `aharder3/ha-abb-welcome-smarttouch` if you have a SmartTouch panel

Supported hardware per its README: **ABB 83342 IP gateway** (web admin) or an
**M2240x / ASI22 Wi-Fi indoor station** with SIP-TLS port 5061 reachable.

Pairing needs: your MyBuildings username/password (used once for the
certificate request, not stored), the gateway's local IP, and the gateway admin
password (web-admin gateways) or the MyBuildings system ID (app-managed ones).
Follow the integration's own README.

After pairing, Home Assistant should show entities for your doors (typically
`button.*` unlock buttons, `camera.*`/`image.*` for the pictures).

> **To verify on your system:** the integration documents door **unlocks**. The
> iPhone app's **Relè** list (*Cancello-citofono*, *Basculante-citofono*) may
> or may not appear as entities. Check in Home Assistant → Settings → Devices.
> If a relay is missing, say so: it needs a capture of your app
> (`traffic-capture-playbook.md`) to see how it is triggered.

## 2. Reach Home Assistant from outside (for LTE)

The watch only needs a URL it can open from anywhere:

- **Home Assistant Cloud (Nabu Casa)**: easiest, gives `https://xxxx.ui.nabu.casa`.
- **Tailscale** on the watch's iPhone/network, or your own **HTTPS reverse proxy**.

On home Wi-Fi alone, `http://homeassistant.local:8123` works too (the app allows
plain HTTP on the local network only). Over the internet always use HTTPS.

## 3. Create an access token

Home Assistant → your profile → **Security** → **Long-lived access tokens** →
*Create token*. Copy it once; it is shown only at creation. Anyone with it can
control your Home Assistant, so keep it out of chats, screenshots and git. If
it leaks, delete it there and make a new one.

## 4. Configure the iPhone app

1. **Home Assistant**: enter the address and the token, tap **Collega e carica
   entità**. It should report how many entities were found.
2. **Relè**: for *Cancello-citofono* and *Basculante-citofono* choose the matching
   entity (use the search), then **Prova: attiva ora** — the gate must react.
3. **Posto esterno**: optionally pick the `camera`/`image` entity for the
   picture, and tick which relays appear on that station.
4. **Invia al Watch**.

## 5. Build the apps (Mac with Xcode required)

See the README. Not compiled in the cloud container that wrote this code, so a
first build may need small fixes.
