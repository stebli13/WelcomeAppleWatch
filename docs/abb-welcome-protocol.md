# ABB-Welcome: what is known about the protocol

Everything here concerns **your own** ABB-Welcome installation and **your own**
account — interoperability, as the open-source Home Assistant integrations do.

## Findings (from the source of `rankjie/ha-abb-welcome`)

- **Pairing**: portal username/password → HTTP Digest call to
  `POST https://api.eu.mybuildings.abb.com/certificate/request` with an RSA CSR →
  a client certificate (CN = portal user, valid for mutual TLS). No OAuth client
  id and no bearer token appear anywhere.
- **Portal events**: with that certificate, `GET/POST /event` carry discovery,
  a `welcome.connect` event (with an integrity code derived from the
  certificate fingerprint) and an `acl-update` event. The ACL update carries an
  RSA-encrypted **SIP password** and the door list (`outdoorstation_*` sections).
- **Unlock** = SIP `MESSAGE` with plain-text body `1` to `sip:<station>@<domain>`,
  after a SIP `REGISTER` with digest auth (user `<portal_user>_<gruu>`), over TCP
  5060 or TLS 5061, **straight to the gateway on the LAN**. No cloud relay is
  contacted. A "second lock" uses body `a` inside a targeted call
  (`INVITE → MESSAGE → BYE`).
- **Hardware named**: ABB 83342 IP gateway, M2240x / ASI22 Wi-Fi indoor station.

## Open questions

1. **Remote unlock**: the official app reportedly works from outside, but the
   community code is LAN-only. The route the app uses is unknown (the globe icon
   on the outdoor station hints at an internet path).
2. **Relè** (*Cancello-citofono*, *Basculante-citofono*): how they are triggered
   is not covered by the integration's unlock path.
3. **Your hardware model** — decides which integration variant applies.

## Decision for v1

The watch app calls **Home Assistant** (`HomeAssistantClient`), which already
solves pairing and the SIP unlock; see `home-assistant-setup.md`. The
`GateClient` protocol keeps the UI independent, so a native SIP client could be
added later if answers to the questions above make it worthwhile.

A previous draft assumed an OAuth + "write a datapoint" cloud API. That was a
guess and has been removed; ABB's *Welcome IP cloud API* (developer portal) was
not reachable from the build environment and may target a different product line.
