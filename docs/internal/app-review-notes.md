# Notes for App Review

## What Kalyta does

Kalyta is a free, open-source personal expense log for iOS. The person records what they spent (by hand,
from a Back Tap or Wallet "Transaction" shortcut, or by scanning the QR code of a Ukrainian fiscal receipt),
and the app shows totals, categories and statistics. Everything is stored on the device; there is no account
and no server of ours. Optional: subscriptions with reminders, income next to spending, a widget with today's
total, and a read-only import of the person's own monobank statement.

## Guideline 5.1.1(ix) — not a financial service

Kalyta is a personal diary of the person's own spending. It does not provide banking or financial services:
no payments, no transfers, no accounts, no credit, no investment or financial advice, and no access to anyone
else's data. The optional monobank connection only **reads** the person's own statement, with a read-only personal
token the person creates for themselves at api.monobank.ua; the token cannot move money. Requests go from the phone
straight to monobank; no data passes through the developer.

monobank's API documentation (https://api.monobank.ua/docs/) allows exactly this use of the personal API:

> «Розробка бібліотек або програм, які будуть використовувати клієнти особисто (дані клієнта не будуть проходити
> черeз вузли розробника), також не потребують використання корпоративного API.»

Translation: "Developing libraries or programs that clients will use personally (client data will not pass through
the developer's nodes) also does not require using the corporate API."

## How to test without a Ukrainian bank

monobank is optional and off by default; every other feature works without it.

1. **Add an expense:** Expenses tab → **+** → type an amount → pick a category → ✓ (Save).
2. **Scan a receipt:** in the same entry sheet tap **Scan Receipt** and point the camera at
   `docs/review/sample-receipt-qr.png` (shown on another screen or printed). It is a sample link in the format of the
   Ukrainian tax service; the app reads the amount (432.90) and the date and time (24 Sep 2026, 12:18) from the link
   itself, with no network request. Any other QR code shows "Not a fiscal receipt".
3. **Statistics, subscriptions, income:** the Statistics and Subscriptions tabs, and the Expense / Income switch
   in the entry sheet. Adding a subscription (for example "Netflix") downloads its icon.
4. **Widget:** long-press the Home Screen → Edit → Add Widget → Kalyta. It opens the scanner and shows today's total.

Sample QR payload:
`https://cabinet.tax.gov.ua/cashregs/check?date=20260924&time=121800&id=123456789&sm=432.90&fn=4000123456`

## Back Tap and Wallet shortcuts

- **Back Tap:** Shortcuts → new shortcut → **Add Expense** action, choose a Category. Then Settings → Accessibility →
  Touch → Back Tap → Double Tap → that shortcut.
- **Wallet:** Shortcuts → Automation → **Transaction** → **Add Expense**: Amount ← Amount, Note ← Merchant, Category
  empty, Run Immediately on. The app reuses the category last given to that merchant.

## Privacy

No data is collected by the developer; no tracking, ads or analytics. The only network requests are the subscription
icon download from jsDelivr (the subscription name) and, if the person turns it on, monobank. Privacy policy:
`docs/privacy.md`.
