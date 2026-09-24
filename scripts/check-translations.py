#!/usr/bin/env python3
"""Fails if any string in the String Catalogs lacks a finished translation.

Xcode adds new strings from the code to Kalyta/Localizable.xcstrings on every
build, but nothing stops the app from shipping them untranslated: the
interface would silently fall back to English. Run this after building.

Usage: scripts/check-translations.py [language ...]   (default: uk)
"""

import json
import pathlib
import sys

APP = pathlib.Path(__file__).resolve().parent.parent / "Kalyta"
# The interface strings, and the Info.plist ones such as the camera permission text.
CATALOGS = [APP / "Localizable.xcstrings", APP / "InfoPlist.xcstrings"]


def string_units(localization: dict) -> list[dict]:
    """Returns every string unit of a localization, including plural and device variants."""
    if "stringUnit" in localization:
        return [localization["stringUnit"]]
    units = []
    for variants in localization.get("variations", {}).values():
        for variant in variants.values():
            units.extend(string_units(variant))
    return units


def missing_translations(catalog: dict, language: str) -> list[str]:
    """Returns the keys that should be translated but have no finished translation."""
    missing = []
    for key, entry in catalog["strings"].items():
        if entry.get("shouldTranslate") is False or entry.get("extractionState") == "stale":
            continue
        units = string_units(entry.get("localizations", {}).get(language, {}))
        if not units or any(u.get("state") != "translated" or not u.get("value") for u in units):
            missing.append(key)
    return sorted(missing)


def main() -> int:
    failed = False
    total = 0
    for path in CATALOGS:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        total += len(catalog["strings"])
        for language in sys.argv[1:] or ["uk"]:
            missing = missing_translations(catalog, language)
            for key in missing:
                print(f"{path.name}: {language}: missing translation for {key!r}")
            failed = failed or bool(missing)
    if not failed:
        print(f"All {total} strings are translated.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
