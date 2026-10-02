# Security Policy

## Reporting a vulnerability

Please report security problems **privately**: open the repository's **Security** tab and choose
**Report a vulnerability** ([direct link](https://github.com/Miozzik/Kalyta/security/advisories/new)).
Do not open a public issue for a vulnerability.

Include what you found, how to reproduce it, and the iOS and app versions. You will get a reply in the advisory
thread; fixes are released as soon as they are ready.

## Scope

Kalyta has no server and no account; all data stays on the iPhone. The interesting surfaces are:

- **The monobank personal token** — stored in the Keychain on this device only, sent only to `api.monobank.ua`.
- **Network requests** — the app talks only to:
  - `cdn.jsdelivr.net` — subscription icons (sends the subscription name);
  - `api.monobank.ua` — the statement (with the token) and public exchange rates (without it);
  - `bank.gov.ua` — NBU exchange rates (sends a date).
- **CSV import** — files from outside the app are parsed with size, value and formula limits.
- **The App Group container** shared with the widget, which holds today's total only.

Out of scope: the security of monobank, the NBU, jsDelivr or iOS itself — report those to their owners.

See [docs/privacy.md](docs/privacy.md) for exactly what leaves the phone.
