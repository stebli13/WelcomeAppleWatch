# ABB-Welcome door-opener protocol notes

Status: **partially known from public sources; exact IDs/endpoints to be
confirmed by a one-time traffic capture of your own app** (see
`traffic-capture-playbook.md`). This drives the `GateClient` implementation.

Everything here targets **your own** ABB-Welcome system via **your own**
myBUILDINGS account — interoperability, not bypassing anything.

---

## Two transports

### 1. Cloud — "Welcome IP Cloud API" (recommended for the watch)

- Portal/docs: `developer.eu.mybuildings.abb.com` (Welcome IP cloud API).
  Could not be fetched from the build container (network-policy blocked); read
  it from your own machine and fill the `??` below, or just capture the app.
- **Prerequisites** (from ABB docs summary):
  - Access Point firmware **≥ 6.36**.
  - A myBUILDINGS / myBUSCH-Jaeger account (the one your app uses).
  - In the app: **Preferences → Connection & APIs → MyBuildings connection →
    enable the Welcome IP API** support setting.
  - For the *official developer* API you register/subscribe an app in the
    portal and await approval. **You do not strictly need this** if you simply
    replay the mobile app's own cloud calls (Method A capture) — those use the
    app's existing OAuth client.
- **Data model** (confirmed shape):
  - `SmartAP` (your access point) identified by a **UUID**.
  - A SmartAP has **devices**; a device has **channels**; a channel exposes
    **datapoints** (inputs you write, outputs you read).
  - The **"door opener"** is a channel. **Opening the door = writing its input
    datapoint** (typically a momentary `1`/pressed value).
  - Change notifications available via **WebSocket** or **WebHook** (we only
    need write, so WebSocket is optional — useful later for "door is open"
    state or ring events).

#### Values to capture (fill these in)

| Name | Placeholder | Where it comes from |
|---|---|---|
| OAuth token endpoint | `OAUTH_TOKEN_URL = ??` | capture of app login / `/token` call |
| OAuth client_id | `CLIENT_ID = ??` | login request body/header |
| Access token | (runtime, Keychain) | token response |
| Refresh token + refresh call | `REFRESH_URL = ??` | token response + refresh call |
| API base URL | `API_BASE = ??` | the door-open request host |
| SmartAP UUID | `SMARTAP_UUID = ??` | "get data model" call, or door-open URL |
| Device id | `DEVICE_ID = ??` | door-open URL/body |
| Door-opener channel id | `CHANNEL_ID = ??` | door-open URL/body |
| Door-opener datapoint id | `DATAPOINT_ID = ??` | door-open body |
| "pressed/open" value | `OPEN_VALUE = ??` (often `"1"`) | door-open body |

#### Action request (template — confirm with capture)

```
POST  {API_BASE}/.../{SMARTAP_UUID}/devices/{DEVICE_ID}/channels/{CHANNEL_ID}/datapoints/{DATAPOINT_ID}
Authorization: Bearer {access_token}
Content-Type: application/json

{ "value": "{OPEN_VALUE}" }
```

Verify with the `curl` in the playbook before writing Swift. The exact path
segments differ between ABB firmware/API versions — the capture is
authoritative.

### 2. Local LAN — SIP (community reverse-engineered; home-only fast path)

From the open-source Home Assistant integrations (`rankjie/ha-abb-welcome`,
`johnnyh1975/ha-abb-welcome`, `aharder3/ha-abb-welcome-smarttouch`):

- The IP gateway runs a **SIP server**; indoor stations are SIP endpoints.
- **Pairing**: one-time, via the MyBuildings portal — generate an RSA keypair,
  request a client certificate, compute a gateway integrity code from the cert
  fingerprint, send a `welcome.connect` event, then poll for the gateway ACL
  update and **decrypt the SIP password**. Credentials then live locally.
- **Unlock = a SIP `MESSAGE`** to the target station over **SIP-TLS on port
  5061** (app-managed gateways). Strategies: *Standard* (INVITE→MESSAGE→BYE),
  *Fast* (plain MESSAGE), *Hybrid*. Second lock = MRANGE command `a` inside a
  targeted call.
- Pros: ~50 ms, no cloud round-trip. Cons: **home Wi-Fi only** — not useful
  when the watch is on LTE. Treat as a later optimization behind the same
  `GateClient` interface.

---

## Decision for v1

Implement the **cloud** transport in `ABBWelcomeCloudClient` (works anywhere).
Keep `GateClient` abstract so a `ABBWelcomeLocalSIPClient` can be added later
for the home fast-path. Do the capture to fill the table above; until then the
cloud client reads its values from `GateConfiguration`, which is seeded with
placeholders and overridden by the real captured values (never committed).
