# Contributing to Kalyta

Thanks for helping. Bug reports, ideas and pull requests are all welcome. The project is small on purpose:
if iOS can do something, Kalyta uses that instead of building its own.

## Requirements

- **Xcode with the iOS 26 SDK.** The project is built and tested with Xcode 27. It uses `ButtonRole.confirm` and an
  Icon Composer `.icon` file, so an older SDK does not build it.
- **iOS 17** is the deployment target (SwiftData).
- No package dependencies: everything is Apple frameworks.

## Build

```sh
git clone https://github.com/Miozzik/Kalyta.git
cd Kalyta
xcodebuild -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' build
```

Or open `Kalyta.xcodeproj` and press Run. The `Kalyta` scheme builds the app and its embedded widget extension
`KalytaWidgets` (`<bundle id>.widgets`). The simulator needs no Apple account.

### Running on your iPhone

Create `Config/Local.xcconfig` (git ignores it):

```
DEVELOPMENT_TEAM = <your Team ID>
// A free Apple ID may need a unique bundle id:
// PRODUCT_BUNDLE_IDENTIFIER = com.example.kalyta
```

- Shared build settings live in `Config/Kalyta.xcconfig`, not in `project.pbxproj`; `Local.xcconfig` is included
  last, so it overrides them.
- The app and the widget share the App Group `group.<app bundle id>` (`APP_GROUP_ID`), so your own bundle id gives
  your own group. Signing is automatic.
- With a free Apple ID (Personal Team) each target's profile lasts 7 days; then press Run again.

## Project structure

```
Kalyta/                       # App target (Xcode synchronized folder: new files join the target automatically)
├── App/                      # Entry point, launch arguments, Settings, About, shared sheet toolbar
├── Model/                    # SwiftData models, schema versions and migrations, periods, hryvnia formatting
├── Features/
│   ├── Expenses/             # List, editor, CSV export/import, summary card
│   ├── Categories/           # Category editor, merchant → category memory
│   ├── Statistics/
│   ├── Subscriptions/
│   └── Today/                # Today's total shared with the widget
├── Integrations/
│   ├── Monobank/             # Token, API client, sync
│   ├── Currency/             # NBU / monobank rates
│   ├── Receipt/              # Fiscal QR scanner, Scan Receipt intent
│   └── Shortcuts/            # Add Expense intent, Apple Pay automation guide
├── Checks/                   # --selfcheck assertions and their fixtures (debug builds)
└── Resources/                # Assets, app icon, String Catalogs, Autopay.shortcut, privacy manifest
KalytaWidgets/                # Widget extension
KalytaUITests/                # UI tests, one file per feature
Config/                       # xcconfig, Info.plist, entitlements; Local.xcconfig is git-ignored
scripts/                      # Translation check, screenshot and shortcut-upgrade scripts
docs/
├── privacy.md, support.md    # Public pages the app links to
├── appstore/, review/        # App Store screenshots, App Review attachment
├── images/                   # README images
└── internal/                 # Decision log, design specs, App Review notes
```

Folders are for people only: the bundle is flat, so moving a file changes nothing at run time. A file the widget
also compiles is listed by its path in the `Exceptions for "Kalyta" folder in "KalytaWidgets" target` set of
`project.pbxproj` — move it in Xcode, or update that path by hand.

## Code style

- Comments and documentation in English, following the
  [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/) and
  [DocC](https://developer.apple.com/documentation/xcode/writing-symbol-documentation-in-your-source-files):
  `///` on every non-`private` symbol, with `- Parameters:`, `- Returns:`, `- Throws:` where they apply.
- User settings go in `@AppStorage` / `UserDefaults`; build settings go in `.xcconfig`.
- Format with the `swift-format` bundled with Xcode and the repo's `.swift-format` (4 spaces, 120 columns):

```sh
swift format lint -r Kalyta KalytaUITests KalytaWidgets   # check
swift format -i -r Kalyta KalytaUITests KalytaWidgets     # fix
```

## Localization

- The development language is English; the translation is Ukrainian.
- No user-facing text is hard-coded: code holds the English key, the translation lives in a String Catalog.
  SwiftUI literals (`Text("Save")`) are localized automatically; a `String` returned from code must use
  `String(localized:)`, or Xcode never sees it.
- Catalogs: `Kalyta/Resources/Localizable.xcstrings` (UI), `Kalyta/Resources/InfoPlist.xcstrings` (camera permission),
  `Kalyta/Resources/AppShortcuts.xcstrings` (Siri phrases).
- Xcode adds new strings on build in the IDE; from the command line run `xcrun xcstringstool sync`.
- Check that nothing is left untranslated:

```sh
scripts/check-translations.py   # → All N strings are translated.
```

## Self-check

The app carries `assert`-based checks (`Kalyta/Checks/`) that prove the logic
without UI: totals and periods, CSV (RFC 4180 and formula protection), import limits, QR parsing, Apple Pay matching,
monobank against fixtures, merchant memory, currencies, today's total.

```sh
xcodebuild -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath <dd> build
xcrun simctl boot "iPhone 17"
xcrun simctl install booted <dd>/Build/Products/Debug-iphonesimulator/Kalyta.app
xcrun simctl launch --console-pty booted org.merzlov.kalyta --selfcheck -AppleLocale uk_UA   # → SELFCHECK OK
xcrun simctl launch booted org.merzlov.kalyta --demo                                         # sample data
```

The Ukrainian locale is deliberate: it catches a decimal comma sneaking into exported amounts. The check cleans up
after itself, so it can be rerun. Other launch arguments (`--empty`, `--check-upgrade`, `--measure-import`,
`-rateFixture`, `-scanPayload`) are documented in `Kalyta/App/KalytaApp.swift`; all but `--measure-import` work in
debug builds only.

## UI tests

```sh
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 90
```

- `xcodebuild test` sometimes does not exit after the tests finish — hence the `alarm` watchdog.
- Run one suite at a time on a quiet machine: under load the document picker and other UI tests flake.
- Widget tests: install the app, **reboot the simulator**, then run. On a freshly erased simulator the widget
  gallery does not see a new app until a reboot.
- Three tests skip on purpose: screenshots (`TEST_RUNNER_KALYTA_SCREENSHOTS=1`), the shortcut upgrade and the
  Shortcuts guide screenshots (run only by the scripts below).

## Testing new logic

Every new piece of logic needs a check that fails when the logic breaks — prove it by breaking it on a copy and
seeing the check go red.

Do mutations in a **copy** of the repo with its own identity, or a crash there kills a UI run elsewhere
("Critical process Kalyta crashed": XCTest links failures to the app by bundle id and process name):

- set `PRODUCT_BUNDLE_IDENTIFIER = org.merzlov.kalyta.mutation` in the copy's `Config/Kalyta.xcconfig`;
- replace both `PRODUCT_NAME = "$(TARGET_NAME)";` of the app target in the copy's `project.pbxproj`
  with `PRODUCT_NAME = KalytaMutation;`.

Never pass these on the `xcodebuild` command line: there they also rename the UI test runner and every run fails.

## Release checks

- **Add Expense parameters changed?** Run `scripts/check-shortcut-upgrade.sh [previous-ref]`: a shortcut saved with
  the previous build must keep its Category after the upgrade.
- **Shortcuts guide screenshots** (Settings → Automatic Recording, English and Ukrainian, in
  `Kalyta/Resources/Assets.xcassets/Autopay*`): `scripts/autopay-screenshots.sh`. It erases and relanguages the simulator
  "iPhone 17 Autopay", so never point it at a shared one. The **Transaction** trigger is not available on the
  simulator; that screenshot comes from a real iPhone.

## CSV column contract

The export is the user's only backup, so its format is a contract: column order is fixed and new columns are
**appended only** (`ExpenseCSV.columns` in `Kalyta/Features/Expenses/ExpenseCSV.swift`). Import requires the first six.

| column | example | format |
|---|---|---|
| `date` | `2026-09-23T12:18:00+03:00` | ISO 8601, local time with offset |
| `amount` | `878.4` | hryvnias; dot decimal, no spaces or currency sign |
| `currency` | `UAH` | ISO 4217, the currency of `amount` — always `UAH` |
| `category` | `food` | stable key, language-independent |
| `category_name` | `Food` | name in the app's language |
| `note` | `ATB` | as is; quoted when it contains a comma, quote or line break (RFC 4180) |
| `category_symbol` | `fork.knife` | SF Symbol name |
| `category_color` | `orange` | palette name, not RGB, so dark mode works |
| `kind` | `expense` | `expense` or `income`; files without it are all spending |
| `original_amount` | `100` | amount in the original currency; empty for hryvnias |
| `original_currency` | `USD` | ISO 4217; empty for hryvnias |
| `rate` | `44.9729` | hryvnias per unit, up to six decimals |
| `rate_estimated` | `false` | `true` while waiting for the NBU rate of the entry's date |

- **Formula protection:** text starting with `=`, `+`, `-`, `@`, a tab, a line break or their full-width forms
  (`＝＋－＠`) is written with a leading `'`; import strips it, so `=1+1` round-trips.
- **Import limits:** date from 2000-01-01 to tomorrow; amount > 0 and ≤ 10,000,000; category key ≤ 64 characters,
  name ≤ 100, note ≤ 1000; the kind must match the category (no income in a spending category); file ≤ 10 MB.
  Rows whose `currency` is not `UAH` are refused. Other rows are listed as unreadable.

## How this project is developed

Kalyta is built with AI coding agents. `.claude/agents/` holds their role definitions (product manager gates,
tester, designer, docs and others), and [docs/internal/decisions.md](docs/internal/decisions.md) is the decision log — each choice
with the argument that won, in mixed Ukrainian and English. Both are kept public for transparency.

## Reporting issues

[Open an issue](https://github.com/Miozzik/Kalyta/issues/new/choose) with your iOS version, device, steps to
reproduce, and what you expected versus what happened. Security problems go through [SECURITY.md](SECURITY.md),
not public issues.

## Pull requests

1. Fork and create a topic branch.
2. Keep the change focused; follow the code style and localization rules above.
3. Run `swift format lint`, `scripts/check-translations.py`, the self-check and the UI suites your change touches.
4. Describe what changed, why, and how you proved it.

By contributing you agree that your contributions are licensed under the project's [MIT License](LICENSE).
