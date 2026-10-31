#!/usr/bin/env python3
"""Probe your own ABB-Welcome installation without Home Assistant.

Reuses the protocol code of the MIT-licensed community integration
rankjie/ha-abb-welcome (https://github.com/rankjie/ha-abb-welcome), loaded from
a local clone, to answer the questions the watch app depends on:

  tls     Which TLS settings the gateway's SIP port accepts (no credentials).
  pair    Pair once through MyBuildings and save the result locally.
  show    Print what the gateway exposes: every section of its access list,
          so the relays ("Relè") can be found, not only the outdoor stations.
  unlock  Open one door/relay through the gateway (asks for confirmation).

Run it yourself, from Terminal, on your home network. Your MyBuildings password
is typed into this script only, sent only to ABB, and never stored. The
resulting identity (private key, certificate, SIP password) is stored in
~/.welcomegate/state.json, readable only by your user. Delete that file and
remove the "welcomegate-..." client from the Welcome App to undo the pairing.

Only use this on an installation and account that are yours.
"""

from __future__ import annotations

import argparse
import configparser
import getpass
import importlib
import json
import logging
import os
import socket
import ssl
import sys
import time
import types
from pathlib import Path

# Commit of rankjie/ha-abb-welcome this script was written against.
REF_COMMIT = "0ec199be84d0934c7e4f7f6c0ec3019025757786"
STATE_DIR = Path.home() / ".welcomegate"
STATE_FILE = STATE_DIR / "state.json"
DEFAULT_REF_DIR = STATE_DIR / "ha-abb-welcome"

# ACL keys whose values are never printed.
SECRET_HINTS = ("pass", "secret", "key", "token", "cert")


def load_community(ref_dir: Path) -> tuple[types.ModuleType, types.ModuleType]:
    """Import portal.py and sip_client.py without running the package's
    __init__.py, which needs Home Assistant."""
    pkg_dir = ref_dir / "custom_components" / "abb_welcome"
    if not (pkg_dir / "portal.py").is_file():
        sys.exit(
            f"Community code not found in {ref_dir}.\n"
            f"Run: git clone https://github.com/rankjie/ha-abb-welcome {ref_dir} "
            f"&& git -C {ref_dir} checkout {REF_COMMIT}"
        )
    pkg = types.ModuleType("abb_welcome")
    pkg.__path__ = [str(pkg_dir)]
    sys.modules["abb_welcome"] = pkg
    portal = importlib.import_module("abb_welcome.portal")
    sip = importlib.import_module("abb_welcome.sip_client")
    return portal, sip


# --------------------------------------------------------------------------
# State
# --------------------------------------------------------------------------

def save_state(state: dict) -> None:
    STATE_DIR.mkdir(mode=0o700, exist_ok=True)
    os.chmod(STATE_DIR, 0o700)
    tmp = STATE_FILE.with_suffix(".tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as fh:
        json.dump(state, fh, indent=2)
    os.replace(tmp, STATE_FILE)


def load_state() -> dict:
    if not STATE_FILE.is_file():
        sys.exit(f"No saved pairing in {STATE_FILE}. Run the 'pair' command first.")
    return json.loads(STATE_FILE.read_text())


# --------------------------------------------------------------------------
# tls
# --------------------------------------------------------------------------

def _try_tls(ip: str, port: int, label: str, ctx: ssl.SSLContext) -> None:
    try:
        with socket.create_connection((ip, port), timeout=5) as raw:
            with ctx.wrap_socket(raw, server_hostname=None) as tls:
                name, version, bits = tls.cipher()
                print(f"  {label}: OK — {tls.version()}, {name} ({bits} bit)")
    except (OSError, ssl.SSLError) as err:
        print(f"  {label}: FAILED — {err}")


def cmd_tls(args: argparse.Namespace) -> None:
    print(f"TLS handshake with {args.ip}:{args.port} (no credentials sent)")

    modern = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    modern.check_hostname = False
    modern.verify_mode = ssl.CERT_NONE
    modern.minimum_version = ssl.TLSVersion.TLSv1_2
    _try_tls(args.ip, args.port, "modern (TLS 1.2+, default ciphers, close to iOS)", modern)

    legacy = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    legacy.check_hostname = False
    legacy.verify_mode = ssl.CERT_NONE
    legacy.minimum_version = ssl.TLSVersion.TLSv1
    try:
        legacy.set_ciphers("DEFAULT:@SECLEVEL=0")
    except ssl.SSLError:
        pass
    _try_tls(args.ip, args.port, "legacy (TLS 1.0+, weak ciphers allowed)", legacy)

    try:
        with socket.create_connection((args.ip, 5060), timeout=3):
            print("  plain TCP 5060: open")
    except OSError as err:
        print(f"  plain TCP 5060: closed ({err})")


# --------------------------------------------------------------------------
# pair
# --------------------------------------------------------------------------

def _poll_and_finish(portal, state: dict, attempts: int) -> None:
    print(
        "\nWaiting for the gateway to accept the pairing "
        f"(up to {max(1, round(attempts * 3 / 60))} min).\n"
        "If the Welcome App shows a new pairing request, accept it there.\n"
        f"Integrity code to compare, if asked: {state['integrity_display']}"
    )
    payload = portal.poll_acl_update(
        state["portal_url"],
        state["cert_pem"].encode(),
        state["key_pem"].encode(),
        state["own_uuid"],
        attempts=attempts,
        interval=3.0,
        on_attempt=lambda n: print(f"  attempt {n}/{attempts}", end="\r", flush=True),
    )
    print()
    if payload is None:
        save_state(state)
        sys.exit(
            "No answer yet. Your pairing request is saved; run "
            "'pair --resume' later instead of pairing again "
            "(each new pairing adds another client to your account)."
        )

    state["acl_ini"] = "\n".join(payload.splitlines()[1:]).replace("\x00", "").rstrip()
    try:
        sip_password, domain, doors = portal.parse_acl_update(
            payload, state["key_pem"].encode()
        )
        state.update(sip_password=sip_password, sip_domain=domain, doors=doors)
    except portal.PortalError as err:
        print(f"Note: community parser could not read doors ({err}).")
    state["paired"] = True
    save_state(state)
    print(f"Paired. Saved to {STATE_FILE} (only your user can read it).\n")
    print_acl(state)


def cmd_pair(args: argparse.Namespace) -> None:
    portal, _ = load_community(args.ref)

    if args.resume:
        state = load_state()
        if state.get("paired"):
            sys.exit("Already paired. Use 'show' or 'unlock'.")
        _poll_and_finish(portal, state, args.attempts)
        return

    if STATE_FILE.is_file() and not args.force:
        sys.exit(
            f"{STATE_FILE} already exists. Use 'pair --resume' to finish a "
            "pending pairing, or 'pair --force' to start over (adds another "
            "client to your account)."
        )

    print("Pairing with your ABB-Welcome installation through MyBuildings.")
    print("Your password is sent only to ABB and is not stored.\n")
    username = input("MyBuildings username (email): ").strip()
    password = getpass.getpass("MyBuildings password (hidden): ")

    priv_pem, csr_pem, _ = portal.generate_keypair_and_csr(username)
    portal_url = portal.resolve_portal_url(username)
    client_name = f"welcomegate-{int(time.time())}"
    cert_pem = portal.request_certificate(
        portal_url, username, password, csr_pem, client_name
    )
    del password
    identity = portal.derive_identity(cert_pem, username)
    integrity_eight, integrity_display = portal.compute_integrity_code(
        identity["fingerprint_sha1"]
    )

    state = {
        "ref_commit": REF_COMMIT,
        "portal_url": portal_url,
        "portal_username": username,
        "client_name": client_name,
        "gateway_uuid": args.gateway_uuid,
        "gateway_ip": args.ip,
        "key_pem": priv_pem.decode(),
        "cert_pem": cert_pem.decode(),
        "sip_username": identity["sip_username"],
        "own_uuid": identity["own_portal_uuid"],
        "integrity_display": integrity_display,
        "paired": False,
    }
    # Save before contacting the gateway so a retry reuses this identity.
    save_state(state)

    portal.send_connect_event(
        portal_url, cert_pem, priv_pem, args.gateway_uuid,
        identity["own_portal_uuid"], integrity_eight,
    )
    print(f"Pairing request sent as client '{client_name}'.")
    _poll_and_finish(portal, state, args.attempts)


# --------------------------------------------------------------------------
# show
# --------------------------------------------------------------------------

def print_acl(state: dict) -> None:
    ini = state.get("acl_ini", "")
    if not ini:
        print("No access list saved yet.")
        return
    print("What the gateway exposes (secrets hidden):")
    config = configparser.ConfigParser(interpolation=None, strict=False)
    try:
        config.read_string(ini)
    except configparser.Error as err:
        print(f"(not a standard INI: {err}; raw lines follow)")
        for line in ini.splitlines():
            key = line.split("=", 1)[0].lower()
            if "=" in line and any(hint in key for hint in SECRET_HINTS):
                line = f"{line.split('=', 1)[0]}= <hidden>"
            print(f"  {line}")
    for section in config.sections():
        print(f"\n[{section}]")
        for key, value in config.items(section):
            if any(hint in key.lower() for hint in SECRET_HINTS):
                value = f"<hidden, {len(value)} chars>"
            print(f"  {key} = {value}")
    doors = state.get("doors") or []
    print(f"\nDoors the community parser can unlock: {len(doors)}")
    for door in doors:
        flags = "" if door.get("can_unlock", True) else " (not unlockable)"
        print(f"  - {door['name']}: station {door['station_id']}{flags}")


def cmd_show(args: argparse.Namespace) -> None:
    state = load_state()
    print(f"Gateway {state['gateway_ip']}, client {state['client_name']}, "
          f"paired: {state.get('paired')}\n")
    print_acl(state)


# --------------------------------------------------------------------------
# unlock
# --------------------------------------------------------------------------

def cmd_unlock(args: argparse.Namespace) -> None:
    _, sip = load_community(args.ref)
    state = load_state()
    if not state.get("paired") or "sip_password" not in state:
        sys.exit("Not paired yet (or no SIP password in the access list).")

    doors = state.get("doors") or []
    door = next((d for d in doors if d["station_id"] == args.station), None)
    target = door or {
        "name": args.station,
        "station_id": args.station,
        "address": f"sip:{args.station}@{state['sip_domain']}",
    }
    answer = input(
        f"This will OPEN '{target['name']}' (station {args.station}, body "
        f"'{args.body}', {args.strategy}/{args.transport}). Type SI to continue: "
    )
    if answer.strip().upper() != "SI":
        sys.exit("Cancelled.")

    client = sip.SIPClient(
        host=state["gateway_ip"],
        username=state["sip_username"],
        password=state["sip_password"],
        domain=state["sip_domain"],
        doors=doors,
        invite_transport=args.transport,
        unlock_strategy=args.strategy,
        legacy_first_door_hybrid=False,
    )
    started = time.monotonic()
    ok = client.unlock_door(target, body=args.body, timeout=args.timeout)
    elapsed = time.monotonic() - started
    print(f"{'OK' if ok else 'FAILED'} after {elapsed:.1f} s"
          + ("" if ok else " — rerun with --verbose for details"))
    if not ok:
        sys.exit(1)


# --------------------------------------------------------------------------
# relay / raw
# --------------------------------------------------------------------------
#
# The relays ("Relè": Cancello-citofono, Basculante-citofono) are switch
# actuators with an address (1–199) on the bus, not outdoor stations. Body
# "10"/"20" sent to the station reaches it but is not a valid actuator
# command. The community code documents only the *inbound* actuator message
# shape (from the indoor panel's programmable buttons):
#     {"cmd": "actuator", "buttons": [{"id": 2, "func": 5, "params": {"addr": "199"}}]}
# so the outbound command is not published anywhere. These variants are the
# plausible shapes derived from it; `relay` tries them one by one and prints
# the gateway's answer so you can see which one clicks the relay.

def relay_variants(addr: str) -> list[tuple[str, str, str]]:
    """(label, content type, body) candidates for switching actuator `addr`."""
    params = json.dumps({"cmd": "actuator", "params": {"addr": addr}}, separators=(",", ":"))
    flat = json.dumps({"cmd": "actuator", "addr": addr}, separators=(",", ":"))
    flat_int = json.dumps({"cmd": "actuator", "addr": int(addr)}, separators=(",", ":"))
    button = json.dumps(
        {"cmd": "actuator", "button": 1, "func": 5, "params": {"addr": addr}},
        separators=(",", ":"),
    )
    return [
        ("json params.addr", "application/json", params),
        ("json params.addr (text/plain)", "text/plain", params),
        ("json addr", "application/json", flat),
        ("json addr (number)", "application/json", flat_int),
        ("json button+func+params.addr", "application/json", button),
        ("text b:<addr>", "text/plain", f"b:{addr}"),
    ]


def send_message(sip, stream, local_ip, local_port, gw, user, password,
                 target_uri: str, body: str, content_type: str):
    """Like the community `_send_plain_message`, with a chosen Content-Type."""
    import uuid

    transport = gw.transport.upper()
    transport_param = f";transport={gw.transport}" if gw.transport == "tls" else ""
    call_id = f"{uuid.uuid4().hex[:16]}@{gw.sip_domain}"
    headers = [
        f"Via: SIP/2.0/{transport} {local_ip}:{local_port};"
        f"branch=z9hG4bK-{uuid.uuid4().hex[:12]};rport",
        "Max-Forwards: 70",
        f"From: <sip:{user}@{gw.sip_domain}{transport_param}>;tag={uuid.uuid4().hex[:8]}",
        f"To: <{target_uri}>",
        f"Call-ID: {call_id}",
        "CSeq: 1 MESSAGE",
        f"Content-Type: {content_type}",
        "User-Agent: ABB-Welcome-HA/1.0",
    ]
    stream.sock.sendall(sip._sip_request("MESSAGE", target_uri, headers, body))
    response = stream.recv_final_response(call_id=call_id, cseq_number=1,
                                          cseq_method="MESSAGE")
    if response.status_code() in (401, 407):
        response, _ = sip._maybe_auth_resend(
            stream, response, "MESSAGE", target_uri, headers, body,
            user, password, transport, local_ip, local_port, 5,
        )
    return response


def run_messages(sip, state: dict, *, station: str, target: str | None,
                 call: bool, transport: str, timeout: float,
                 messages: list[tuple[str, str, str]], pause: float) -> None:
    """Register, optionally open a call to `station`, send each MESSAGE."""
    domain = state["sip_domain"]
    user, password = state["sip_username"], state["sip_password"]
    gw = sip._build_gateway_config(domain, state["gateway_ip"], transport)
    sock, local_ip, local_port = sip._build_socket(gw, timeout)
    stream = sip.SipStream(sock)
    session = None
    try:
        sip._register_client(stream, local_ip, local_port, gw, user, password)
        if target:
            target_uri = target if target.startswith("sip:") else f"sip:{target}@{domain}"
        else:
            target_uri = f"sip:{station}@{domain}"
        if call:
            door = sip.DoorSpec(name=station, station_id=station,
                                address=f"sip:{station}@{domain}",
                                unlock_body="1", index=None)
            session = sip._start_invite_call(
                stream, local_ip, local_port, gw, user, password, door,
                min(timeout, sip.DEFAULT_INVITE_TIMEOUT),
                sip._guess_media_ip(gw.gw_host), "0.0.0.0",
            )
            stream.sock.settimeout(timeout)
            if not target:
                target_uri = session.target_uri
            print(f"Call to station {station} established: {session.established}")

        for n, (label, content_type, body) in enumerate(messages, start=1):
            print(f"\n[{n}/{len(messages)}] {label}\n  to   {target_uri}\n"
                  f"  type {content_type}\n  body {body}")
            try:
                response = send_message(sip, stream, local_ip, local_port, gw,
                                        user, password, target_uri, body, content_type)
                print(f"  -> {response.start_line}")
                if response.body:
                    print(f"     {response.body[:300]!r}")
            except (RuntimeError, TimeoutError, OSError) as err:
                print(f"  -> error: {err}")
            if n < len(messages):
                answer = input("  Did the relay click? [s = yes, stop / Enter = next] ")
                if answer.strip().lower() in ("s", "si", "y", "yes"):
                    print(f"\nWORKING COMMAND: type {content_type}, body {body}, "
                          f"to {target_uri}, call={call}")
                    return
                time.sleep(pause)
    finally:
        if session is not None:
            try:
                if session.established:
                    sip._send_bye(stream, local_ip, local_port, gw, user, password, session)
                else:
                    sip._cancel_invite(stream, local_ip, local_port, gw, session, timeout)
            except (ConnectionError, OSError, TimeoutError, RuntimeError) as err:
                print(f"(call teardown: {err})")
            session.close_media()
        sock.close()


def _confirm(what: str) -> None:
    answer = input(f"This may ACTIVATE {what}. Make sure the gate/garage is safe "
                   "to move. Type SI to continue: ")
    if answer.strip().upper() != "SI":
        sys.exit("Cancelled.")


def _paired_state() -> dict:
    state = load_state()
    if not state.get("paired") or "sip_password" not in state:
        sys.exit("Not paired yet (or no SIP password in the access list).")
    return state


def cmd_relay(args: argparse.Namespace) -> None:
    _, sip = load_community(args.ref)
    state = _paired_state()
    variants = relay_variants(args.addr)
    if args.variant:
        variants = [variants[args.variant - 1]]
    print("Variants:")
    for n, (label, ctype, body) in enumerate(relay_variants(args.addr), start=1):
        print(f"  {n}. {label}: {ctype} {body}")
    _confirm(f"the relay at address {args.addr}")
    run_messages(sip, state, station=args.station, target=args.target,
                 call=not args.no_call, transport=args.transport,
                 timeout=args.timeout, messages=variants, pause=args.pause)


def cmd_raw(args: argparse.Namespace) -> None:
    _, sip = load_community(args.ref)
    state = _paired_state()
    _confirm(f"whatever body '{args.body}' controls")
    run_messages(sip, state, station=args.station, target=args.target,
                 call=not args.no_call, transport=args.transport,
                 timeout=args.timeout,
                 messages=[("raw", args.content_type, args.body)], pause=0)


# --------------------------------------------------------------------------

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--ref", type=Path, default=DEFAULT_REF_DIR,
                        help="clone of rankjie/ha-abb-welcome")
    parser.add_argument("--verbose", action="store_true")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("tls", help="check the gateway's SIP TLS settings")
    p.add_argument("--ip", required=True)
    p.add_argument("--port", type=int, default=5061)
    p.set_defaults(func=cmd_tls)

    p = sub.add_parser("pair", help="pair once through MyBuildings")
    p.add_argument("--ip", help="gateway / indoor station LAN IP")
    p.add_argument("--gateway-uuid", help="system UUID shown in the Welcome App")
    p.add_argument("--attempts", type=int, default=60)
    p.add_argument("--resume", action="store_true")
    p.add_argument("--force", action="store_true")
    p.set_defaults(func=cmd_pair)

    p = sub.add_parser("show", help="print what the gateway exposes")
    p.set_defaults(func=cmd_show)

    p = sub.add_parser("unlock", help="open one door or relay")
    p.add_argument("--station", required=True, help="station id from 'show'")
    p.add_argument("--body", default="1", help="'1' = door, 'a' = second lock")
    p.add_argument("--strategy", choices=("standard", "fast"), default="standard")
    p.add_argument("--transport", choices=("tls", "tcp"), default="tls")
    p.add_argument("--timeout", type=float, default=5.0)
    p.set_defaults(func=cmd_unlock)

    def add_session_args(p: argparse.ArgumentParser) -> None:
        p.add_argument("--station", default="100000001",
                       help="outdoor station to call first (default 100000001)")
        p.add_argument("--target", help="send the MESSAGE to this SIP id/URI "
                       "instead of the station (e.g. an actuator id from 'show')")
        p.add_argument("--no-call", action="store_true",
                       help="send without opening a call to the station first")
        p.add_argument("--transport", choices=("tls", "tcp"), default="tls")
        p.add_argument("--timeout", type=float, default=5.0)

    p = sub.add_parser("relay", help="try actuator commands for one relay address")
    p.add_argument("--addr", required=True, help="relay/actuator address, e.g. 10 or 20")
    p.add_argument("--variant", type=int, choices=range(1, 7),
                   help="send only this variant (1-6); default tries all")
    p.add_argument("--pause", type=float, default=2.0)
    add_session_args(p)
    p.set_defaults(func=cmd_relay)

    p = sub.add_parser("raw", help="send one MESSAGE with any body")
    p.add_argument("--body", required=True)
    p.add_argument("--content-type", default="text/plain")
    add_session_args(p)
    p.set_defaults(func=cmd_raw)

    args = parser.parse_args()
    if args.command == "pair" and not args.resume and not (args.ip and args.gateway_uuid):
        parser.error("pair needs --ip and --gateway-uuid (unless --resume)")
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.WARNING,
        format="%(levelname)s %(name)s: %(message)s",
    )
    args.func(args)


if __name__ == "__main__":
    main()
