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

## Step 2 — after the probe

Depending on the answers: a Swift SIP client in the iPhone app (Network
framework, digest auth), an import of the pairing result from the Mac into the
iPhone Keychain (so pairing does not need to be rewritten in Swift), and the
watch sending "open" requests to the iPhone. If the relays turn out not to be
reachable this way, a capture of the official app's SIP traffic would be needed
next — which TLS makes much harder than an HTTPS capture.
