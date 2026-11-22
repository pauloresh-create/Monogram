#!/usr/bin/env python3
# MARK: Monogram
"""Refresh the repo's fake provisioning profiles for CI builds (macOS only).

The fake profiles in build-system/fake-codesigning/profiles expired, and rules_apple
refuses expired profiles. rules_apple reads a profile with `security cms -D` /
`openssl smime -noverify`, i.e. it never checks who signed it, so we:
  1. decode each profile to its plist,
  2. move ExpirationDate ten years ahead,
  3. re-sign the plist with the repo's fake SelfSigned.p12.
It also creates SGActionRequestHandler.mobileprovision (Swiftgram's extra extension,
which has no fake profile) from the Share one, with its own application-identifier.

The IPA is unsigned for real use anyway: Sideloadly/AltStore re-sign it.

Usage: refresh_fake_profiles.py <fake-codesigning dir> <base bundle id>
"""
import datetime
import os
import plistlib
import subprocess
import sys
import tempfile

TEN_YEARS = datetime.timedelta(days=3650)


def run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=True, capture_output=True, **kwargs)


def decode_profile(path: str) -> dict:
    data = run(["security", "cms", "-D", "-i", path]).stdout
    return plistlib.loads(data)


def sign_profile(plist: dict, signer_pem: str, out_path: str) -> None:
    with tempfile.NamedTemporaryFile(suffix=".plist", delete=False) as tmp:
        tmp.write(plistlib.dumps(plist, fmt=plistlib.FMT_XML))
        plist_path = tmp.name
    try:
        run([
            "openssl", "smime", "-sign", "-binary", "-nodetach", "-outform", "der",
            "-signer", signer_pem, "-in", plist_path, "-out", out_path,
        ])
    finally:
        os.unlink(plist_path)


def extract_signer(p12_path: str, out_pem: str) -> None:
    # The fake p12 has an empty password (see build-system/Make/ImportCertificates.py).
    attempts = (
        ["openssl", "pkcs12", "-in", p12_path, "-nodes", "-passin", "pass:", "-out", out_pem],
        ["openssl", "pkcs12", "-legacy", "-in", p12_path, "-nodes", "-passin", "pass:", "-out", out_pem],
    )
    last_error = None
    for args in attempts:
        try:
            run(args)
            return
        except subprocess.CalledProcessError as error:
            last_error = error
    raise SystemExit(f"cannot read SelfSigned.p12: {last_error.stderr.decode(errors='replace')}")


def with_app_id(plist: dict, bundle_id: str) -> dict:
    prefix = plist["ApplicationIdentifierPrefix"][0]
    entitlements = dict(plist["Entitlements"])
    entitlements["application-identifier"] = f"{prefix}.{bundle_id}"
    updated = dict(plist)
    updated["Entitlements"] = entitlements
    updated["Name"] = "Monogram SGActionRequestHandler"
    return updated


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit(__doc__)
    codesigning_dir, base_bundle_id = sys.argv[1], sys.argv[2]
    profiles_dir = os.path.join(codesigning_dir, "profiles")
    expiration = datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None) + TEN_YEARS

    with tempfile.TemporaryDirectory() as work:
        signer_pem = os.path.join(work, "signer.pem")
        extract_signer(os.path.join(codesigning_dir, "certs", "SelfSigned.p12"), signer_pem)

        share_plist = None
        for name in sorted(os.listdir(profiles_dir)):
            if not name.endswith(".mobileprovision"):
                continue
            path = os.path.join(profiles_dir, name)
            plist = decode_profile(path)
            plist = {**plist, "ExpirationDate": expiration}
            sign_profile(plist, signer_pem, path)
            print(f"refreshed {name}: expires {expiration:%Y-%m-%d}")
            if name == "Share.mobileprovision":
                share_plist = plist

        sg_path = os.path.join(profiles_dir, "SGActionRequestHandler.mobileprovision")
        if share_plist is not None and not os.path.exists(sg_path):
            sg_plist = with_app_id(share_plist, f"{base_bundle_id}.SGActionRequestHandler")
            sign_profile(sg_plist, signer_pem, sg_path)
            print("created SGActionRequestHandler.mobileprovision")


if __name__ == "__main__":
    main()
