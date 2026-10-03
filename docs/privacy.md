# Політика конфіденційності Kalyta / Kalyta Privacy Policy

Дата / Effective date: 01.10.2026

## Українською

**Розробник не збирає жодних даних.** У Kalyta немає акаунта, сервера, реклами, аналітики й відстеження.
Усі витрати, доходи, категорії й підписки зберігаються лише на твоєму iPhone (SwiftData у пісочниці застосунку).

**Що покидає телефон:**
- **Іконки підписок.** Коли ти додаєш або перейменовуєш підписку, застосунок завантажує її іконку
  з jsDelivr (CDN, що віддає файли з GitHub-репозиторію homarr-labs/dashboard-icons). Цей сервер бачить назву
  підписки й твою IP-адресу. Запит підписано просто «Kalyta», без моделі пристрою й версії iOS.
- **monobank — лише якщо ти сам його ввімкнеш.** Застосунок напряму, без нашого сервера, запитує твою виписку
  в api.monobank.ua твоїм особистим токеном. Токен лежить у Keychain лише на цьому iPhone і не переноситься на інший
  iPhone з бекапу. Ім’я, IBAN і ЄДРПОУ іншої сторони, коментар до переказу й баланс застосунок не читає взагалі.
  Переказ записується з підписом «Переказ», а не з описом банку, бо там може бути ім’я людини; у покупок
  і повернень зберігається назва продавця. Назви банок читаються лише під час синхронізації.
  На телефоні зберігається лише внутрішній ідентифікатор гривневого рахунку з відповіді monobank (не IBAN і не номер
  картки), щоб знати, з якого рахунку читати виписку; «Відключити» його видаляє.
  Щоб видалений запис із банку не повернувся з наступною синхронізацією, 35 днів зберігається лише його
  ідентифікатор у банку й час видалення — без суми, продавця, дати й нотатки; у CSV і App Group він не потрапляє.
  Дані monobank обробляє згідно зі своїми правилами — ми до них доступу не маємо.
- **Курси валют — лише якщо є записи в іноземній валюті** (або в аркуші запису вибрано не гривню). Застосунок
  запитує в НБУ (bank.gov.ua, через Cloudflare) список курсів на дату запису — надсилається лише дата — і загальні
  курси monobank (`api.monobank.ua/bank/currency`, без токена). Ці сервери бачать твою IP-адресу, але не суму
  й не нотатку. Курс зберігається в самому записі; окремого кешу на диску немає. Поки всі записи в гривнях,
  курси не запитуються.

Більше нічого не надсилається. Сканування чека розбирає QR-код на телефоні, без мережі.
Сума за сьогодні зберігається у спільному контейнері App Group, щоб її показав віджет, — теж лише на телефоні.

**Як видалити дані:**
- Видали застосунок — зникнуть усі записи. (Токен monobank iOS може лишити в Keychain; наступне встановлення
  його видалить при першому запуску.)
- Налаштування → Банк → monobank → «Відключити» видаляє токен, а також список видалених записів банку; відкликати його можна на api.monobank.ua.
- Перед видаленням можна зберегти резервну копію: Налаштування → «Резервна копія» → «Експортувати резервну копію» → CSV-файл.

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
  move to another iPhone through a backup. The other party's name, IBAN and EDRPOU code, transfer comments and the
  balance are never read. A transfer is recorded as "Transfer", not with the bank's description, which can contain a
  person's name; purchases and refunds keep the merchant name. Jar titles are read during a sync only. The only thing kept on the phone is monobank's internal id of your hryvnia account (not an IBAN or card
  number), so the app knows which account's statement to read; "Disconnect" deletes it. So that a bank entry you
  delete does not come back with the next sync, only its bank id and the time of deletion are kept for 35 days — no
  amount, merchant, date or note; this list is never exported to CSV or shared with the App Group. monobank handles your data
  under its own terms; we have no access to it.
- **Exchange rates — only if you have foreign-currency entries** (or pick a currency other than the hryvnia in the
  entry sheet). The app asks the NBU (bank.gov.ua, served through Cloudflare) for its list of rates on the entry's
  date — only the date is sent — and monobank for its public rates (`api.monobank.ua/bank/currency`, no token).
  These servers see your IP address, never the amount or the note. The rate is stored on the entry itself; there is
  no separate cache on disk. While every entry is in hryvnias, no rates are requested.

Nothing else is sent. Receipt scanning parses the QR code on the phone, without any network request.
Today's total is kept in a shared App Group container so the widget can show it — also on the phone only.

**How to delete your data:**
- Delete the app to remove every entry. (iOS may keep the monobank token in the Keychain; the next install deletes it
  on first launch.)
- Settings → Bank → monobank → "Disconnect" deletes the token, and also deletes the list of deleted bank entries; you can revoke it at api.monobank.ua.
- To keep a backup first: Settings → Backup → Export Backup → CSV file.

**Contact:** see the support page — [support.md](support.md).
