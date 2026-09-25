# Політика конфіденційності Kalyta / Kalyta Privacy Policy

Дата / Effective date: 25.09.2026

## Українською

**Розробник не збирає жодних даних.** У Kalyta немає акаунта, сервера, реклами, аналітики й відстеження.
Усі витрати, доходи, категорії й підписки зберігаються лише на твоєму iPhone (SwiftData у пісочниці застосунку).

**Що покидає телефон:**
- **Іконки підписок.** Коли ти додаєш або перейменовуєш підписку, застосунок завантажує її іконку
  з jsDelivr (CDN, що віддає файли з GitHub-репозиторію homarr-labs/dashboard-icons). Цей сервер бачить назву
  підписки й твою IP-адресу. Запит підписано просто «Kalyta», без моделі пристрою й версії iOS.
- **monobank — лише якщо ти сам його ввімкнеш.** Застосунок напряму, без нашого сервера, запитує твою виписку
  в api.monobank.ua твоїм особистим токеном. Токен лежить у Keychain лише на цьому iPhone і не переноситься на інший
  iPhone з бекапу. Імена, IBAN і номери карток не зберігаються; назви банок читаються лише під час синхронізації.
  Дані monobank обробляє згідно зі своїми правилами — ми до них доступу не маємо.

Більше нічого не надсилається. Сканування чека розбирає QR-код на телефоні, без мережі.
Сума за сьогодні зберігається у спільному контейнері App Group, щоб її показав віджет, — теж лише на телефоні.

**Як видалити дані:**
- Видали застосунок — зникнуть усі записи. (Токен monobank iOS може лишити в Keychain; наступне встановлення
  його видалить при першому запуску.)
- Налаштування → Банк → monobank → «Відключити» видаляє токен; відкликати його можна на api.monobank.ua.
- Перед видаленням можна зберегти резервну копію: «Поширити» → CSV-файл.

**Контакт:** сторінка підтримки — [support.md](support.md).

## English

**The developer collects no data.** Kalyta has no account, no server, no ads, no analytics and no tracking.
All expenses, income, categories and subscriptions stay on your iPhone (SwiftData in the app's sandbox).

**What leaves the phone:**
- **Subscription icons.** When you add or rename a subscription, the app downloads its icon from jsDelivr
  (a CDN serving the GitHub repository homarr-labs/dashboard-icons). That server sees the subscription name and your
  IP address. The request's User-Agent is just "Kalyta", with no device model or iOS version.
- **monobank — only if you turn it on.** The app requests your statement directly from api.monobank.ua with your own
  personal token, with no server of ours in between. The token is kept in the Keychain on this iPhone only and does not
  move to another iPhone through a backup. Names, IBANs and card numbers are not stored; jar titles are read during a
  sync only. monobank handles your data under its own terms; we have no access to it.

Nothing else is sent. Receipt scanning parses the QR code on the phone, without any network request.
Today's total is kept in a shared App Group container so the widget can show it — also on the phone only.

**How to delete your data:**
- Delete the app to remove every entry. (iOS may keep the monobank token in the Keychain; the next install deletes it
  on first launch.)
- Settings → Bank → monobank → "Disconnect" deletes the token; you can revoke it at api.monobank.ua.
- To keep a backup first: Share → CSV file.

**Contact:** see the support page — [support.md](support.md).
