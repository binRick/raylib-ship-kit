#!/usr/bin/env python3
"""
asc-submit.py - send an uploaded build to App Store review, without the web UI.

Picks up where scripts/ios-appstore.sh stops: waits until Apple finishes processing
the build, creates the App Store version, attaches the build, copies the listing text
from the previous version, declares export compliance and submits for review.

The very first version of an app still needs its listing (description, screenshots,
privacy answers, age rating) filled in on appstoreconnect.apple.com: there is no
previous version to copy from. Every release after that is this one command.

Requires:
  - pip install pyjwt cryptography
  - ASC_KEY_ID + ASC_ISSUER_ID env vars
  - ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8

Usage:
  scripts/asc-submit.py "What's new text"     # version from VERSION, bundle id from kit.env
"""
import datetime as dt
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

import jwt

ROOT = pathlib.Path(__file__).resolve().parent.parent
PLATFORM = "IOS"
RELEASE_TYPE = "AFTER_APPROVAL"  # vs "MANUAL" or "SCHEDULED"
API_BASE = "https://api.appstoreconnect.apple.com"


def make_token() -> str:
    key_id = os.environ["ASC_KEY_ID"]
    issuer_id = os.environ["ASC_ISSUER_ID"]
    key_path = pathlib.Path.home() / ".appstoreconnect" / "private_keys" / f"AuthKey_{key_id}.p8"
    private_key = key_path.read_text()
    payload = {
        "iss": issuer_id,
        "iat": int(dt.datetime.now(dt.timezone.utc).timestamp()),
        "exp": int(dt.datetime.now(dt.timezone.utc).timestamp()) + 20 * 60,
        "aud": "appstoreconnect-v1",
    }
    return jwt.encode(payload, private_key, algorithm="ES256", headers={"kid": key_id})


def req(method: str, path: str, *, token: str, body=None, query=None):
    url = API_BASE + path
    if query:
        url += "?" + urllib.parse.urlencode(query, doseq=True)
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", f"Bearer {token}")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request) as resp:
            text = resp.read().decode()
            return json.loads(text) if text else {}
    except urllib.error.HTTPError as e:
        err_body = e.read().decode()
        print(f"\n{method} {url} -> {e.code}\n{err_body}", file=sys.stderr)
        raise


def find_app(token, bundle_id):
    j = req("GET", "/v1/apps", token=token, query={"filter[bundleId]": bundle_id})
    if not j.get("data"):
        sys.exit(f"No app with bundleId={bundle_id}")
    return j["data"][0]


def wait_for_build(token, app_id, version, timeout_min=45, interval=30):
    """Poll until a build with the given short version reaches processingState=VALID."""
    deadline = time.time() + timeout_min * 60
    last_state = None
    while time.time() < deadline:
        j = req(
            "GET",
            "/v1/builds",
            token=token,
            query={
                "filter[app]": app_id,
                "filter[version]": version,
                "sort": "-uploadedDate",
                "limit": "5",
            },
        )
        builds = j.get("data", [])
        if builds:
            b = builds[0]
            state = b["attributes"]["processingState"]
            if state != last_state:
                print(f"  build {version} state: {state}")
                last_state = state
            if state == "VALID":
                return b
            if state == "FAILED":
                sys.exit(f"Build processing FAILED for {version}")
        else:
            if last_state != "missing":
                print(f"  no build {version} visible yet, waiting...")
                last_state = "missing"
        time.sleep(interval)
    sys.exit(f"Timed out waiting for build {version} to process")


def find_prior_version(token, app_id, exclude_version):
    """Last accepted (or any) App Store version we can copy localizations from."""
    j = req(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions",
        token=token,
        query={
            "filter[platform]": PLATFORM,
            "limit": "20",
        },
    )
    # API doesn't allow sort on this relationship endpoint, so newest-first
    # sort client-side via createdDate.
    candidates = sorted(
        [v for v in j.get("data", []) if v["attributes"]["versionString"] != exclude_version],
        key=lambda v: v["attributes"].get("createdDate", ""),
        reverse=True,
    )
    return candidates[0] if candidates else None


def get_or_create_version(token, app_id, version, build_id):
    j = req(
        "GET",
        f"/v1/apps/{app_id}/appStoreVersions",
        token=token,
        query={
            "filter[platform]": PLATFORM,
            "filter[versionString]": version,
        },
    )
    if j.get("data"):
        ver = j["data"][0]
        print(f"  reusing existing App Store version record {version} ({ver['id']})")
    else:
        body = {
            "data": {
                "type": "appStoreVersions",
                "attributes": {
                    "platform": PLATFORM,
                    "versionString": version,
                    "releaseType": RELEASE_TYPE,
                },
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app_id}},
                    "build": {"data": {"type": "builds", "id": build_id}},
                },
            }
        }
        created = req("POST", "/v1/appStoreVersions", token=token, body=body)
        ver = created["data"]
        print(f"  created App Store version {version} ({ver['id']})")
    return ver


def attach_build(token, version_id, build_id):
    """Make sure the build is the one attached to the version."""
    body = {"data": {"type": "builds", "id": build_id}}
    req("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build", token=token, body=body)
    print("  build attached")


def copy_localizations(token, src_version_id, dst_version_id, whats_new):
    """Mirror localized text fields from a prior version into the new one."""
    src = req(
        "GET",
        f"/v1/appStoreVersions/{src_version_id}/appStoreVersionLocalizations",
        token=token,
        query={"limit": "20"},
    ).get("data", [])
    dst = req(
        "GET",
        f"/v1/appStoreVersions/{dst_version_id}/appStoreVersionLocalizations",
        token=token,
        query={"limit": "20"},
    ).get("data", [])
    dst_by_locale = {d["attributes"]["locale"]: d for d in dst}

    fields = [
        "description",
        "keywords",
        "marketingUrl",
        "promotionalText",
        "supportUrl",
    ]
    for s in src:
        locale = s["attributes"]["locale"]
        attrs = {f: s["attributes"].get(f) for f in fields if s["attributes"].get(f) is not None}
        attrs["whatsNew"] = whats_new
        if locale in dst_by_locale:
            d = dst_by_locale[locale]
            req(
                "PATCH",
                f"/v1/appStoreVersionLocalizations/{d['id']}",
                token=token,
                body={
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "id": d["id"],
                        "attributes": attrs,
                    }
                },
            )
            print(f"  updated localization {locale}")
        else:
            req(
                "POST",
                "/v1/appStoreVersionLocalizations",
                token=token,
                body={
                    "data": {
                        "type": "appStoreVersionLocalizations",
                        "attributes": {"locale": locale, **attrs},
                        "relationships": {
                            "appStoreVersion": {
                                "data": {"type": "appStoreVersions", "id": dst_version_id}
                            }
                        },
                    }
                },
            )
            print(f"  created localization {locale}")


def set_export_compliance(token, build_id):
    body = {
        "data": {
            "type": "builds",
            "id": build_id,
            "attributes": {"usesNonExemptEncryption": False},
        }
    }
    try:
        req("PATCH", f"/v1/builds/{build_id}", token=token, body=body)
    except urllib.error.HTTPError as e:
        # 409 = already declared (ITSAppUsesNonExemptEncryption in Info.plist)
        if e.code != 409:
            raise
        print("  export compliance: already declared on build")
        return
    print("  export compliance: no non-exempt encryption")


def submit_for_review(token, app_id, version_id):
    """Create a reviewSubmission, add the version as an item, submit."""
    rs = req(
        "POST",
        "/v1/reviewSubmissions",
        token=token,
        body={
            "data": {
                "type": "reviewSubmissions",
                "attributes": {"platform": PLATFORM},
                "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
            }
        },
    )
    rs_id = rs["data"]["id"]
    print(f"  created reviewSubmission {rs_id}")
    req(
        "POST",
        "/v1/reviewSubmissionItems",
        token=token,
        body={
            "data": {
                "type": "reviewSubmissionItems",
                "relationships": {
                    "reviewSubmission": {
                        "data": {"type": "reviewSubmissions", "id": rs_id}
                    },
                    "appStoreVersion": {
                        "data": {"type": "appStoreVersions", "id": version_id}
                    },
                },
            }
        },
    )
    print("  added version as a submission item")
    req(
        "PATCH",
        f"/v1/reviewSubmissions/{rs_id}",
        token=token,
        body={
            "data": {
                "type": "reviewSubmissions",
                "id": rs_id,
                "attributes": {"submitted": True},
            }
        },
    )
    print(f"  SUBMITTED for review: https://appstoreconnect.apple.com")


def kit_env():
    """KEY="value" lines of kit.env."""
    env = {}
    for line in (ROOT / "kit.env").read_text().splitlines():
        if "=" in line and not line.lstrip().startswith("#"):
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip().strip('"')
    return env


def main():
    if len(sys.argv) != 2:
        sys.exit('usage: scripts/asc-submit.py "What\'s new text"')
    whats_new = sys.argv[1]
    version = (ROOT / "VERSION").read_text().strip()
    bundle_id = kit_env()["BUNDLE_ID"]
    print(f"==> Submitting iOS {version} for App Store review")

    token = make_token()
    app = find_app(token, bundle_id)
    app_id = app["id"]
    print(f"  app: {app['attributes']['name']} ({bundle_id}) -> {app_id}")

    print(f"==> Waiting for build {version} to finish processing")
    build = wait_for_build(token, app_id, version)
    build_id = build["id"]
    print(f"  build {version} ready: {build_id}")

    prior = find_prior_version(token, app_id, version)
    if prior:
        print(f"  prior version for localization copy: {prior['attributes']['versionString']} ({prior['id']})")

    print("==> Creating App Store version + attaching build")
    ver = get_or_create_version(token, app_id, version, build_id)
    version_id = ver["id"]
    attach_build(token, version_id, build_id)

    set_export_compliance(token, build_id)

    if prior:
        print("==> Copying localizations + setting What's New")
        copy_localizations(token, prior["id"], version_id, whats_new)

    print("==> Submitting for review")
    submit_for_review(token, app_id, version_id)
    print("DONE.")


if __name__ == "__main__":
    main()
