# Підтримка Kalyta / Kalyta Support

## Як отримати допомогу / Getting help

- **Задача або помилка / Issue or bug:** <!-- TODO(user): публічна адреса issues репозиторію; public issues URL --> 
- **Пошта / Email:** <!-- TODO(user): support email -->

Опиши, що робив, що очікував і що побачив; версію iOS і застосунку (Параметри → Загальні → Про пристрій).
Describe what you did, what you expected and what happened; include the iOS and app versions.

## Часті питання

**Як записувати витрату подвійним тапом по спинці?**
1. Команди → новий шорткат → дія **Додати витрату**; задай у ній **Категорію**.
2. Параметри → Доступність → Дотик → Тильний дотик → Подвійний → цей шорткат.

**Як записувати оплати карткою автоматично?**
Команди → Автоматизація → **Транзакція** → дія **Додати витрату**: **Сума** ← «Сума», **Нотатка** ← «Продавець»,
**Категорію лишити порожньою**; увімкнути «Запускати негайно». Kalyta сама бере категорію, яку ти востаннє
поставив цьому продавцю; новий продавець іде в «Інше» — виправ раз, далі запам’ятається.

**Як підключити monobank?**
Kalyta → Налаштування → Банк → monobank → «Відкрити api.monobank.ua». Натисни на QR-код, підтверди в застосунку
monobank, скопіюй токен (його показують лише раз) і встав у Kalyta — застосунок сам його перевірить.
Вимкнути — там само, «Відключити». Токен дає лише читання: переказати гроші з ним неможливо.

**Як додати віджет?**
Натисни й утримуй домашній екран або екран блокування → «Редагувати» → «Додати віджет» → Kalyta.
Віджет відкриває сканер чека й показує суму за сьогодні; на заблокованому iPhone сума прихована.
На iOS 18 є ще кнопка «Сканувати чек» у Пункті керування.

**Як не втратити дані?**
Усе лежить лише на телефоні. Роби резервну копію: «Поширити» на головному екрані → CSV. Відновлення — Налаштування →
«Імпорт із CSV».

## FAQ (English)

- **Back Tap:** Shortcuts → new shortcut → **Add Expense** action with a **Category**; then Settings → Accessibility →
  Touch → Back Tap → Double Tap → that shortcut.
- **Card payments:** Shortcuts → Automation → **Transaction** → **Add Expense**: Amount ← Amount, Note ← Merchant,
  Category empty, Run Immediately on. Kalyta reuses the category you last gave that merchant.
- **monobank:** Kalyta → Settings → Bank → monobank → "Open api.monobank.ua", tap the QR code, confirm in monobank, copy
  the token and paste it in Kalyta. "Disconnect" in the same place removes it. The token is read-only.
- **Widget:** long-press the Home or Lock Screen → Edit → Add Widget → Kalyta. On iOS 18 there is also a Control Center
  button.
- **Backup:** Share on the main screen → CSV; restore with Settings → "Import from CSV".
