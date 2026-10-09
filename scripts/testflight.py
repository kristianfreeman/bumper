#!/usr/bin/env python3
"""After an upload: the build's What to Test from CHANGELOG.md, the build in
the external group, and the build submitted for Beta App Review — App Store
Connect's API, with the same API key release.sh uploads with.

    scripts/testflight.py --build 202610081630 [--platforms ios tvos macos]

Waits for each build to finish processing (up to 45 min). The key is read by
openssl to sign the token and never printed. Needs ASC_KEY_ID and ASC_ISSUER_ID.
"""
import argparse, base64, json, os, re, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

APP_ID = "6819710514"                                   # Bumper - Jellyfin Player
GROUP_ID = "6e26569d-f04a-422b-88cb-3a69b0005cd3"       # Friends & Family (public link)
PLATFORMS = {"ios": "IOS", "tvos": "TV_OS", "macos": "MAC_OS"}
API = "https://api.appstoreconnect.apple.com/v1"
ROOT = Path(__file__).resolve().parent.parent


def b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()


def der_to_raw(sig: bytes) -> bytes:
    """openssl signs ES256 as DER (SEQUENCE of two INTEGERs); JWT wants r‖s, 32 bytes each."""
    assert sig[0] == 0x30
    i = 2 if sig[1] < 0x80 else 2 + (sig[1] & 0x7F)
    out = b""
    for _ in range(2):
        assert sig[i] == 0x02
        n = sig[i + 1]
        out += sig[i + 2:i + 2 + n].lstrip(b"\x00").rjust(32, b"\x00")
        i += 2 + n
    return out


def token(key_id: str, issuer: str) -> str:
    key = Path.home() / f".appstoreconnect/private_keys/AuthKey_{key_id}.p8"
    if not key.exists():
        sys.exit(f"no API key at {key}")
    header = b64(json.dumps({"alg": "ES256", "kid": key_id, "typ": "JWT"}).encode())
    now = int(time.time())
    payload = b64(json.dumps({"iss": issuer, "iat": now, "exp": now + 1100, "aud": "appstoreconnect-v1"}).encode())
    signing = f"{header}.{payload}".encode()
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", str(key)], input=signing, capture_output=True, check=True).stdout
    return f"{header}.{payload}.{b64(der_to_raw(der))}"


class ASC:
    def __init__(self, key_id, issuer):
        self.key_id, self.issuer, self.made = key_id, issuer, 0
        self._token = None

    def call(self, method, path, body=None):
        if not self._token or time.time() - self.made > 900:          # tokens last 20 min
            self._token, self.made = token(self.key_id, self.issuer), time.time()
        req = urllib.request.Request(API + path, method=method, data=json.dumps(body).encode() if body else None,
                                     headers={"Authorization": f"Bearer {self._token}", "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                text = r.read()
                return r.status, json.loads(text) if text else {}
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read() or b"{}")


def notes_for(version: str) -> str:
    """The CHANGELOG.md section for this version, as plain text for TestFlight (4000 characters at most)."""
    text = (ROOT / "CHANGELOG.md").read_text()
    m = re.search(rf"^## {re.escape(version)}\s*\n(.*?)(?=^## |\Z)", text, flags=re.M | re.S)
    if not m or not m.group(1).strip():
        sys.exit(f"CHANGELOG.md has no entry for {version}")
    lines = []
    for line in m.group(1).strip().splitlines():
        line = line.rstrip()
        if line.startswith("- "):
            lines.append("• " + line[2:])
        elif line.startswith("  ") and lines:
            lines[-1] += " " + line.strip()
        elif line:
            lines.append(line)
        elif lines and lines[-1] != "":
            lines.append("")
    notes = "\n".join(lines).strip()
    return notes[:4000]


def find_build(asc, number, platform):
    q = f"/builds?filter[app]={APP_ID}&filter[version]={number}&filter[preReleaseVersion.platform]={platform}&include=preReleaseVersion"
    status, body = asc.call("GET", q.replace("[", "%5B").replace("]", "%5D"))
    if status != 200 or not body.get("data"):
        return None
    return body["data"][0]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", required=True)
    ap.add_argument("--platforms", nargs="+", default=list(PLATFORMS))
    ap.add_argument("--version", help="defaults to MARKETING_VERSION in project.yml")
    args = ap.parse_args()
    key_id, issuer = os.environ.get("ASC_KEY_ID"), os.environ.get("ASC_ISSUER_ID")
    if not key_id or not issuer:
        sys.exit("needs ASC_KEY_ID and ASC_ISSUER_ID")
    version = args.version or re.search(r"MARKETING_VERSION:\s*(\S+)", (ROOT / "project.yml").read_text()).group(1)
    notes = notes_for(version)
    asc = ASC(key_id, issuer)
    print(f"{version} ({args.build}): What to Test from CHANGELOG.md, {len(notes)} characters")

    for p in args.platforms:
        platform = PLATFORMS[p]
        deadline = time.time() + 45 * 60
        build = None
        while time.time() < deadline:                      # appears a few minutes after upload, then processes
            build = find_build(asc, args.build, platform)
            state = build and build["attributes"].get("processingState")
            if state == "VALID":
                break
            if state in ("FAILED", "INVALID"):
                sys.exit(f"{p}: build {args.build} processing {state}")
            print(f"{p}: {state or 'not there yet'}; waiting", flush=True)
            time.sleep(30)
        else:
            sys.exit(f"{p}: build {args.build} not processed after 45 min")
        bid = build["id"]

        # What to Test (update the existing en-US one, or make it).
        status, locs = asc.call("GET", f"/builds/{bid}/betaBuildLocalizations")
        existing = next((l for l in locs.get("data", []) if l["attributes"].get("locale") == "en-US"), None)
        if existing:
            status, _ = asc.call("PATCH", f"/betaBuildLocalizations/{existing['id']}",
                                 {"data": {"type": "betaBuildLocalizations", "id": existing["id"], "attributes": {"whatsNew": notes}}})
        else:
            status, _ = asc.call("POST", "/betaBuildLocalizations",
                                 {"data": {"type": "betaBuildLocalizations", "attributes": {"locale": "en-US", "whatsNew": notes},
                                           "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        print(f"{p}: What to Test {'set' if status in (200, 201) else f'failed ({status})'}")

        status, _ = asc.call("POST", f"/betaGroups/{GROUP_ID}/relationships/builds", {"data": [{"type": "builds", "id": bid}]})
        print(f"{p}: in Friends & Family {'yes' if status in (200, 204) else f'failed ({status})'}")

        status, body = asc.call("POST", "/betaAppReviewSubmissions",
                                {"data": {"type": "betaAppReviewSubmissions", "relationships": {"build": {"data": {"type": "builds", "id": bid}}}}})
        if status in (200, 201):
            print(f"{p}: submitted for Beta App Review")
        else:
            detail = "; ".join(e.get("detail", "") for e in body.get("errors", []))
            print(f"{p}: review submission {status}: {detail}")     # e.g. already approved for this version: none needed


if __name__ == "__main__":
    main()
