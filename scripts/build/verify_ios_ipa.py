#!/usr/bin/env python3
"""Verify the real Info.plist shipped inside an iOS IPA / .app before publishing.

Reads Payload/<App>.app/Info.plist from the .ipa (or the Info.plist of an .app
bundle or .xcarchive) and exits with code 1 unless:

  * CFBundleShortVersionString equals the expected marketing version,
  * CFBundleVersion is a number greater than or equal to the expected build number,
  * CFBundleIdentifier equals the expected bundle id.

App Store Connect keeps version trains closed, so an IPA rebuilt with an already
approved version (1.0.3, 1.0.5, ...) is rejected on import. This guard inspects
the file that actually ships, not the project files, so a stale checkout or a
stale ios/Flutter/Generated.xcconfig cannot slip through.

The expected marketing version and build number default to the canonical source
(apps/fulltech_app/pubspec.yaml); there is no second version to maintain.

Usage:
    python3 scripts/build/verify_ios_ipa.py build/ios/ipa/Runner.ipa
    python3 scripts/build/verify_ios_ipa.py Runner.app --min-build-number 130
    python3 scripts/build/verify_ios_ipa.py Runner.ipa --bundle-id com.example.app
"""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
import zipfile
from pathlib import Path

DEFAULT_BUNDLE_ID = "com.fulltechrd.fullposcloud"
DEFAULT_PUBSPEC = Path(__file__).resolve().parents[2] / "apps" / "fulltech_app" / "pubspec.yaml"


def parse_pubspec_version(pubspec_path):
    """Return (marketing_version, build_number) from the canonical pubspec."""
    if not pubspec_path.is_file():
        sys.exit("FAIL: pubspec not found: {0}".format(pubspec_path))
    for line in pubspec_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("version:"):
            raw = line.split(":", 1)[1].strip()
            name, separator, build = raw.partition("+")
            if not separator or not name or not build.isdigit():
                sys.exit("FAIL: '{0}' in {1} is not <version>+<build>".format(raw, pubspec_path))
            return name, int(build)
    sys.exit("FAIL: no version: entry in {0}".format(pubspec_path))


def version_tuple(value):
    """Comparable numeric tuple for a dotted version string."""
    parts = re.findall(r"\d+", value)
    return tuple(int(part) for part in parts[:3]) if parts else (0,)


def read_shipped_info_plist(target):
    """Return (source_description, info_plist_dict) for the plist that ships."""
    if target.is_dir():
        direct = target / "Info.plist"
        if direct.is_file():
            candidates = [direct]
        else:
            candidates = (
                sorted(target.glob("Payload/*.app/Info.plist"))
                or sorted(target.glob("Products/Applications/*.app/Info.plist"))
                or sorted(target.glob("*.app/Info.plist"))
            )
        if len(candidates) != 1:
            sys.exit(
                "FAIL: expected exactly one Info.plist under {0}, found {1}".format(
                    target, [str(candidate) for candidate in candidates]
                )
            )
        with candidates[0].open("rb") as handle:
            return str(candidates[0]), plistlib.load(handle)

    if not target.is_file():
        sys.exit("FAIL: not found: {0}".format(target))

    with zipfile.ZipFile(target) as archive:
        entries = [
            name
            for name in archive.namelist()
            if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", name)
        ]
        if len(entries) != 1:
            sys.exit(
                "FAIL: expected exactly one Payload/<App>.app/Info.plist in {0}, found {1}".format(
                    target, entries
                )
            )
        with archive.open(entries[0]) as handle:
            return "{0}:{1}".format(target, entries[0]), plistlib.load(handle)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target", type=Path, help="Path to the .ipa, the .app bundle or the .xcarchive")
    parser.add_argument("--pubspec", type=Path, default=DEFAULT_PUBSPEC, help="Canonical version source")
    parser.add_argument("--expected-version", help="Override the marketing version expected in the bundle")
    parser.add_argument("--min-build-number", type=int, help="Override the minimum expected CFBundleVersion")
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID, help="Expected CFBundleIdentifier")
    args = parser.parse_args(argv)

    pubspec_version, pubspec_build = parse_pubspec_version(args.pubspec)
    expected_version = args.expected_version or pubspec_version
    min_build_number = args.min_build_number if args.min_build_number is not None else pubspec_build

    source, info = read_shipped_info_plist(args.target)
    found_version = str(info.get("CFBundleShortVersionString", ""))
    found_build_raw = str(info.get("CFBundleVersion", ""))
    found_bundle_id = str(info.get("CFBundleIdentifier", ""))

    failures = []

    if found_version != expected_version:
        failures.append(
            "CFBundleShortVersionString is {0!r}, expected {1!r} (from {2})".format(
                found_version, expected_version, args.pubspec
            )
        )

    if not found_build_raw.isdigit():
        failures.append("CFBundleVersion {0!r} is not numeric".format(found_build_raw))
    elif int(found_build_raw) < min_build_number:
        failures.append(
            "CFBundleVersion {0} is lower than the required {1}".format(found_build_raw, min_build_number)
        )

    if found_bundle_id != args.bundle_id:
        failures.append(
            "CFBundleIdentifier is {0!r}, expected {1!r}".format(found_bundle_id, args.bundle_id)
        )

    print("IPA            : {0}".format(args.target))
    print("Info.plist     : {0}".format(source))
    print("Expected from  : {0} (version {1}+{2})".format(args.pubspec, pubspec_version, pubspec_build))
    print("")
    print("{0:<30} {1:<24} {2:<24} {3}".format("CHECK", "EXPECTED", "FOUND", "RESULT"))
    print("{0:<30} {1:<24} {2:<24} {3}".format("CFBundleShortVersionString", expected_version, found_version, "PASS" if found_version == expected_version else "FAIL"))
    print("{0:<30} {1:<24} {2:<24} {3}".format("CFBundleVersion", ">= {0}".format(min_build_number), found_build_raw, "PASS" if found_build_raw.isdigit() and int(found_build_raw) >= min_build_number else "FAIL"))
    print("{0:<30} {1:<24} {2:<24} {3}".format("CFBundleIdentifier", args.bundle_id, found_bundle_id, "PASS" if found_bundle_id == args.bundle_id else "FAIL"))
    print("")

    if failures:
        print("RESULT: FAIL - DO NOT UPLOAD TO APP STORE CONNECT")
        for failure in failures:
            print("  * {0}".format(failure))
        if version_tuple(found_version) < version_tuple(expected_version):
            print(
                "  * the bundle carries {0}, lower than the canonical {1}: it was produced by an old "
                "checkout or by a stale ios/Flutter/Generated.xcconfig. Rebuild with "
                "'flutter build ipa' from the canonical checkout (it regenerates the version from pubspec).".format(
                    found_version, expected_version
                )
            )
        return 1

    print("RESULT: PASS - the shipped bundle is {0} ({1}) and matches the canonical version".format(found_version, found_build_raw))
    return 0


if __name__ == "__main__":
    sys.exit(main())
