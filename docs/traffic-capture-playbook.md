# One-time capture: extract your ABB-Welcome door-open call

This is the single manual step that turns the placeholders in
`abb-welcome-protocol.md` into real values. ~20 minutes, no jailbreak.
You are recording **your own** app making **your own** door-open request so a
watch client can replay it. Do it on your home Wi-Fi.

## You need
- A Mac or PC on the **same Wi-Fi** as your iPhone.
- `mitmproxy` (`pip install mitmproxy` or `brew install mitmproxy`).
- Your iPhone with the ABB **Welcome App** logged in and able to open the door.

## Steps

1. **Start the proxy** on the computer:
   ```bash
   mitmweb --listen-port 8080
   ```
   Open the web UI it prints (http://127.0.0.1:8080). Note the computer's LAN
   IP: `ipconfig getifaddr en0` (Mac) or `ipconfig` (Windows).

2. **Point the iPhone at it**: Settings → Wi-Fi → (i) on your network →
   Configure Proxy → Manual → Server = computer IP, Port = 8080.

3. **Trust the CA**: Safari → `http://mitm.it` → install the **Apple/iOS**
   profile → Settings → General → VPN & Device Management → install →
   then **Settings → General → About → Certificate Trust Settings → turn ON**
   full trust for the mitmproxy certificate. (Don't skip the last part.)

4. **Record**: in the mitmweb UI clear the list. Open the Welcome App and
   **tap "open door" once**. Then tap it once more. Stop looking after that.

5. **Find the call**: in mitmweb, look at the requests to ABB hosts
   (`*.mybuildings.abb.com` or similar). You're hunting for:
   - a **login / token** request (host contains `auth`/`login`/`token`; a JSON
     response with `access_token`, `refresh_token`, `expires_in`),
   - optionally a **data-model / devices** GET (big JSON listing devices,
     channels, datapoints — find the one named like "door opener"),
   - the **door-open** request itself: a `POST`/`PUT` that happened right when
     you tapped, with a small body like `{"value":"1"}` and IDs in the path.

6. **Fill in** `abb-welcome-protocol.md`'s table from what you see. Export the
   two flows (login + open) as needed — in mitmweb, right-click a flow →
   "Export" → "curl".

7. **Verify by replay** (prove it before writing app code). Paste the token and
   the open request:
   ```bash
   export TOKEN='eyJ...'            # access_token from the login response
   curl -v -X POST "https://<API_BASE>/.../datapoints/<DATAPOINT_ID>" \
     -H "Authorization: Bearer $TOKEN" \
     -H "Content-Type: application/json" \
     -d '{"value":"1"}'
   ```
   If the door opens → the protocol is confirmed. Fill the real values into the
   app's `GateConfiguration` (locally, not committed).

8. **Undo the proxy**: set the iPhone Wi-Fi proxy back to **Off**. You can keep
   the mitmproxy profile installed or remove it.

## If the app's calls don't appear (TLS pinning)
The consumer Welcome App usually does not pin, but if you see handshake errors
for ABB hosts and no readable flows, see Method A step A3 in the skill
(`.claude/skills/app-reverse-engineer/SKILL.md`). Easiest alternative: read
ABB's own `developer.eu.mybuildings.abb.com` Welcome IP cloud API docs, enable
the API in the app, and use the documented endpoints directly.

## Privacy
The capture contains **your** access token and account identifiers. Keep the
exported flows local; never paste the token into the repo, a chat, or an issue.
The app stores it in the iPhone Keychain and syncs only a scoped copy to the
watch.
