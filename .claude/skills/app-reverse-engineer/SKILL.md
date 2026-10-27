---
name: app-reverse-engineer
description: >-
  Reverse-engineer how a mobile app talks to its backend so you can build an
  interoperable client for an account/device you own. Use when the user wants
  to replicate an app's "do X" action (e.g. open their own gate/door, toggle
  their own device) from a new client such as an Apple Watch app, a script, or
  a Home Assistant integration. Covers (1) dynamic HTTPS traffic capture — the
  primary, no-jailbreak method — and (2) static .ipa analysis when a binary is
  available. Inspired by the REA (morluto/rea) reverse-engineering agent
  workflow, adapted to the legitimate interoperability use case.
---

# App reverse-engineering for interoperability

## When this applies / scope guard

Use this ONLY to build a client for a system the user legitimately controls:
their own account, their own gate/door/device, their own data. The goal is
**interoperability** — the same thing Home Assistant integrations and
third-party clients do. Before doing any work, confirm the target belongs to
the user (they already operate it with the official app). Do **not** use this
to bypass authentication, defeat licensing/DRM, access other people's systems,
or evade security controls. If the request drifts toward any of those, stop
and say so.

A useful heuristic: you are replaying the user's *own* authenticated requests
from a different client. You are not breaking auth — you are reusing the
credentials the user already holds.

## The two methods, and which to pick

```
Is the app's action served by a cloud/HTTP(S) API?
├── Yes (most IoT / smart-home / door-entry apps)  → METHOD A: traffic capture  ← START HERE
└── Local-only / binary protocol / no useful HTTPS → METHOD B: static .ipa analysis
```

Prefer **Method A** almost always: it is fast, needs no jailbreak, reveals the
*exact* bytes the server expects, and captures auth tokens you can reuse. Fall
back to Method B only when traffic is absent, pinned beyond unpinning, or the
protocol is a custom binary one.

---

## METHOD A — Dynamic HTTPS traffic capture (primary)

Goal: observe the official app performing the target action and record the
exact request(s) — URL, method, headers (esp. `Authorization`), and body — so
they can be replayed from the new client.

### A1. Set up an intercepting proxy

Use **mitmproxy** (free, scriptable) or Charles/Proxyman (GUI).

```bash
# On a laptop on the SAME Wi-Fi as the phone:
pip install mitmproxy
mitmweb --listen-port 8080          # web UI at http://127.0.0.1:8080
# note the laptop's LAN IP, e.g. 192.168.1.50
```

### A2. Trust the proxy CA on the iPhone

1. iPhone → Wi-Fi → (your network) → Configure Proxy → **Manual**:
   server = laptop IP, port = 8080.
2. Safari → open `http://mitm.it` → install the **iOS** profile.
3. Settings → General → VPN & Device Management → install the profile.
4. **Settings → General → About → Certificate Trust Settings → enable full
   trust** for the mitmproxy cert. (Required, easy to forget.)

### A3. Handle TLS pinning (only if capture shows TLS errors)

Many consumer apps do NOT pin. Try first; if the app's calls fail to appear or
mitmproxy logs handshake errors for the app's domain, the app pins certs.
Options, least invasive first:
- Check whether only *some* domains pin; the target endpoint may not.
- Use a jailbroken test device or a simulator build with SSL-Kill-Switch2 /
  Frida `objection` (`objection ... android sslpinning disable` has an iOS
  equivalent) — requires a device you own and are willing to jailbreak.
- If none of that is acceptable, switch to Method B.

### A4. Capture the action

1. Clear the mitmproxy flow list.
2. In the official app, perform the target action **once** (e.g. tap "open
   door"). Do it a second time to see which parts are stable vs. per-request.
3. Stop capture.

### A5. Isolate and understand the request

Filter flows to the app's API host(s). For the flow(s) that correspond to the
action, record:
- **Full URL** (note path segments that look like IDs/UUIDs — device, channel,
  datapoint).
- **Method** (POST/PUT/PATCH typical for an action).
- **Auth**: `Authorization: Bearer …`, cookies, API keys, HMAC signatures.
- **Body**: exact JSON/XML/form. Identify the single field that represents
  "trigger/open" vs. the parts that are addressing.
- **Preceding calls**: the token endpoint (OAuth `/token`), and any
  "get data model / list devices" call that supplies the IDs.

Produce a short **protocol note** (see `docs/` in this repo for the template)
with: auth flow, how IDs are discovered, and the exact replay request with
placeholders for the captured values.

### A6. Replay to verify

Before writing app code, replay the captured request from `curl` using the
captured token, to prove you understand it:

```bash
curl -v -X POST "https://<host>/<path-with-ids>" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '<captured body>'
```

If the door opens, you have the protocol. Only then write client code.

### A7. Token lifecycle

Capture also reveals token **expiry** and the **refresh** mechanism
(OAuth `refresh_token`, re-login). The new client must implement refresh, or it
will work for an hour and then fail. Record the refresh call too.

---

## METHOD B — Static .ipa analysis (fallback)

Only if Method A is infeasible. Needs a **decrypted** app binary (App Store
binaries are FairPlay-encrypted; decrypt on a jailbroken device with
`frida-ios-dump`, or use a tool the user already has). Work only on a binary
the user is entitled to.

1. Unzip the `.ipa`; the app is in `Payload/<App>.app/`.
2. `strings`, `rabin2 -z`, and `nm` over the main binary to find base URLs,
   path templates, header names, and constants.
3. Inspect `Info.plist` for `ATS` exceptions and URL schemes; inspect bundled
   `.plist`/`.json`/`.cer` resources (pinned certs, config).
4. For logic, load into a decompiler (Ghidra, Hopper, or the REA/`rea` MCP
   agent from morluto/rea which drives this at the binary level) and trace the
   function behind the action button to the networking call.
5. Cross-check findings against a (even partial) traffic capture whenever
   possible — static strings tell you URLs, dynamic capture tells you the live
   values.

Note: static analysis gives structure but not live tokens/IDs; you will still
need one capture or an interactive login to obtain those.

---

## Output of this skill

A `docs/<service>-protocol.md` note containing:
1. **Auth flow** — endpoints, grant type, how to get and refresh a token.
2. **Discovery** — how device/channel/datapoint IDs are obtained.
3. **Action request** — exact method, URL template, headers, body, with a
   worked `curl` that opens the door.
4. **Gaps/placeholders** — any value that must come from the user's capture.

Feed that note into the client implementation (e.g. the `GateClient` in this
repo). Keep secrets (tokens, passwords) OUT of the repo — they live in the
Keychain / a local `.gitignore`d config.
