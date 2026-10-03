# Stage 11 — monobank UI spec

Author: designer, 2026-09-24. Rules for the token itself: `docs/internal/decisions.md`, «Security review».
Cost: UI ~3–4 h on top of the sync engine.

## Verified facts
- The QR code on api.monobank.ua is tappable on iPhone and hands off to the monobank app via `mono://api.monobank.ua`.
- No deep link returns the token to our app: the person copies it. The token is shown once.

## Where
- `SettingsView`: new Section "Bank" above Import.
- `NavigationLink { … } label: { Label("monobank", systemImage: "building.columns") }`, trailing "Off" or "Connected".
- On a sync error: a small `exclamationmark.circle` in `.orange`.

## Connect (4 taps + 1 copy)
1. Not connected: one-line promise + bordered button "Open api.monobank.ua" → `openURL`, external Safari.
2. `PasteButton` fills a `SecureField` (typing also allowed).
3. Auto-verify once the value matches `^[A-Za-z0-9_-]{20,128}$`: call `client-info` once, `ProgressView` + "Checking…". No Connect button.
4. Success: the field is gone for good; "Connected" + status line + "Disconnect". Clear `UIPasteboard` if it still holds the token.

## Connected
- `Button("Disconnect", role: .destructive)` → `confirmationDialog`.
- `Link` "Manage tokens at api.monobank.ua".
- No "Sync now": sync runs on app open.

## Status line (footnote)
| case | text |
|---|---|
| ok | "Updated <relative, named>" |
| 429 | "monobank asked to wait. Retrying in a minute." |
| offline | "No connection. Will update when online." |
| 401 / 403 | "monobank no longer accepts the token. Disconnect and connect again." (`.orange`) |
| other | "Couldn't update. Will try again later." |

## List mark
`ExpenseListRows.swift:55`, after the time caption: `Image(systemName: "building.columns")`, `.caption2`, `.secondary`, `.imageScale(.small)`, only when `bankID != nil`; `accessibilityLabel` "from monobank".

## Strings (en | uk, verbatim; "monobank" always lowercase)
| en | uk |
|---|---|
| Bank | Банк |
| Off | Вимкнено |
| Connected | Підключено |
| Records your monobank card payments by itself. The token only reads; it can't move money. | Сама записує платежі з картки monobank. Токен дає лише читання — переказати гроші з ним неможливо. |
| Open api.monobank.ua | Відкрити api.monobank.ua |
| Tap the QR code, confirm in monobank, copy the token and come back. | Натисни на QR-код, підтверди в monobank, скопіюй токен і повернись. |
| Token | Токен |
| Checking… | Перевіряю… |
| This doesn't look like a monobank token. | Це не схоже на токен monobank. |
| monobank didn't accept this token. Copy it again. | monobank не прийняв цей токен. Скопіюй його ще раз. |
| Updated %@ | Оновлено %@ |
| monobank asked to wait. Retrying in a minute. | monobank просить зачекати. Спробую ще раз за хвилину. |
| No connection. Will update when online. | Немає зв’язку. Оновлю, щойно з’явиться. |
| monobank no longer accepts the token. Disconnect and connect again. | monobank більше не приймає токен. Відключи й підключи знову. |
| Couldn't update. Will try again later. | Не вдалося оновити. Спробую пізніше. |
| Disconnect | Відключити |
| Disconnect monobank? | Відключити monobank? |
| Recorded expenses stay. To revoke the token itself, open api.monobank.ua. | Записані витрати лишаться. Щоб скасувати сам токен, відкрий api.monobank.ua. |
| Manage tokens at api.monobank.ua | Керувати токенами на api.monobank.ua |
| from monobank | з monobank |

## HIG and docs
- Settings: https://developer.apple.com/design/human-interface-guidelines/settings
- Entering data: https://developer.apple.com/design/human-interface-guidelines/entering-data
- SF Symbols: https://developer.apple.com/design/human-interface-guidelines/sf-symbols
- `PasteButton`: https://developer.apple.com/documentation/swiftui/pastebutton
- Action sheets (the Disconnect confirmation dialog): https://developer.apple.com/design/human-interface-guidelines/action-sheets
