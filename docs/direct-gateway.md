# Direct connection to the ABB-Welcome gateway (no Home Assistant)

This is the "option 3" route: the apps talk to your own ABB-Welcome gateway
directly, using the pairing and SIP protocol documented by the MIT-licensed
community integration [rankjie/ha-abb-welcome](https://github.com/rankjie/ha-abb-welcome)
(see `abb-welcome-protocol.md`).

## Why the iPhone has to do the talking

Apple's [TN3135](https://developer.apple.com/documentation/technotes/tn3135-low-level-networking-on-watchos)
blocks low-level networking (TCP/TLS sockets, Network framework) for normal
watchOS apps; only audio-streaming apps while streaming and VoIP apps during a
CallKit call are exempt. Unlocking is SIP over TCP/TLS, so the watch cannot do
it itself. The plan is:

```
Apple Watch ──WatchConnectivity──▶ iPhone app ──SIP (TLS 5061) on home Wi-Fi──▶ gateway ──▶ gate
```

- Works when the iPhone is reachable from the watch and on the home network.
- From outside the home: not expected to work (the community code is LAN-only;
  how the official app unlocks remotely is still unknown).

## Step 1 — probe the real installation (on the Mac, at home)

`tools/abb_probe.py` reuses the community code, without Home Assistant, to
answer what the app depends on before any Swift is written:

1. Does the gateway's SIP TLS port accept settings iOS can offer?
2. Pairing works, and what the gateway's access list contains — in particular
   whether the **Relè** (*Cancello-citofono*, *Basculante-citofono*) appear, or
   only the outdoor station (the community parser keeps only `outdoorstation_*`).
3. Does an unlock open the gate, and which station/body does what?

### Setup (once)

Needs Python 3.10 or newer (`brew install python` if `python3 --version` is older).

```bash
mkdir -p ~/.welcomegate
git clone https://github.com/rankjie/ha-abb-welcome ~/.welcomegate/ha-abb-welcome
git -C ~/.welcomegate/ha-abb-welcome checkout 0ec199be84d0934c7e4f7f6c0ec3019025757786
python3 -m venv ~/.welcomegate/venv
~/.welcomegate/venv/bin/pip install requests cryptography
```

### Run (from the project folder, in your own Terminal)

```bash
PY=~/.welcomegate/venv/bin/python
$PY tools/abb_probe.py tls --ip 192.168.1.169
$PY tools/abb_probe.py pair --ip 192.168.1.169 --gateway-uuid <system UUID from the Welcome App>
$PY tools/abb_probe.py show
$PY tools/abb_probe.py unlock --station <station id from show>
```

- `pair` asks for your MyBuildings email and password in the Terminal. The
  password goes only to ABB and is not stored. It registers a new client named
  `welcomegate-…` on your account; the Welcome App may ask you to accept it.
  If it times out, run `pair --resume` rather than pairing again.
- The result (private key, certificate, SIP password, access list) is saved in
  `~/.welcomegate/state.json`, readable only by your user and outside the repo.
- `unlock` asks you to type `SI` before it sends anything. It really opens the
  gate: run it only when you can see the gate and it is safe to open.
- `show` hides values whose key looks secret; check before sharing its output.

**Undo:** delete `~/.welcomegate/state.json` and remove the `welcomegate-…`
client from the Welcome App's pairing list.

### Relays (Cancello / Basculante)

`unlock --body 1` opens the door lock of the outdoor station. The relays are
switch actuators with their own address (10 and 20 on this installation), and
body `10`/`20` sent to the station is not an actuator command. The outbound
actuator command is not published; the community code only documents the
*inbound* shape `{"cmd":"actuator", … "params":{"addr":"…"}}`. `relay` tries
the plausible variants one at a time and stops when you say the relay clicked:

```bash
$PY tools/abb_probe.py --verbose relay --addr 10
```

**Result on this installation: variant 6 works**, i.e. `text/plain` body
`b:<addr>` to the station, with or without a call (`--no-call` works too and is
quicker). To fire a relay directly:

```bash
$PY tools/abb_probe.py relay --addr 20 --variant 6 --no-call   # Basculante-citofono
$PY tools/abb_probe.py relay --addr 10 --variant 6 --no-call   # Cancello-citofono
```

- Add `--no-call` to send without opening a call to the station first,
  `--target <id>` to send to another SIP id (e.g. an actuator from `show`),
  `--variant N` to repeat only the one that worked.
- `raw --body '<anything>' --content-type application/json` sends one custom
  MESSAGE for further experiments.
- Each MESSAGE's SIP answer is printed (`200 OK`, `400`, `488`…): note it,
  it tells which shapes the gateway understands even if nothing clicks.

### Away from home: the ABB cloud SIP server

The access list has `global-address = <sip:sip.my.busch-jaeger.de:8889;transport=tls>`:
the ABB/Busch-Jaeger SIP server the official app uses outside the home
network. `--via cloud` sends the same REGISTER + MESSAGE there instead of to
the gateway's LAN address, presenting the pairing certificate for TLS
(`--no-client-cert` to try without it):

```bash
$PY tools/abb_probe.py --verbose raw --via cloud --no-call --body b:10
# global-address says 8889, but only 5061 answers from outside:
$PY tools/abb_probe.py --verbose raw --via cloud --cloud-port 5061 --no-call --body b:10
```

**Verified:** on port **5061** (not the 8889 in `global-address`, which
refuses connections) the server accepts the pairing certificate and SIP
credentials, and `b:10` opened the gate. So remote opening needs nothing
running at home.

## Step 2 — the apps

Verified with the probe: everything opens through the ABB cloud SIP server
(`sip.my.busch-jaeger.de:5061`), so the iPhone app does the same, from home or
away, and the watch asks the iPhone (watchOS forbids the sockets).

```
Apple Watch ──WatchConnectivity──▶ iPhone ──SIP/TLS 5061──▶ sip.my.busch-jaeger.de ──▶ gateway ──▶ gate
```

| Opens | SIP MESSAGE to station 100000001 |
|---|---|
| Cancello (relay 10) | `b:10`, no call |
| Basculante (relay 20) | `b:20`, no call |
| Portoncino (door lock) | `1`, inside a call |

1. On the Mac, write the encrypted file for the iPhone (asks for a passphrase):
   ```bash
   $PY tools/abb_probe.py export
   ```
   It lands on the Desktop as `WelcomeGate.welcomegate`.
2. AirDrop it to the iPhone and choose **Salva in File**.
3. Build and install the apps (README), open Welcome Gate on the iPhone,
   **Importa file dal Mac**, pick the file, type the passphrase.
4. Tap each relay → **Prova: apri ora** to check from the iPhone.
5. **Invia al Watch**. On the watch, open from Controllo accessi or Preferiti.
6. Delete the file from Files and from the Mac's Desktop.

The SIP password, certificate and key stay in the iPhone Keychain; the watch
only receives names and commands. If the iPhone is lost: remove the
`welcomegate-…` client from the Welcome App's pairing list.

Not compiled yet (no Xcode in the container that wrote it): the first build
may need small fixes.
