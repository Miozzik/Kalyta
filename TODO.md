# Kalyta — відкриті задачі

Єдиний список задач проєкту. Зроблене переїжджає в розділ «Стан» README,
рішення й суперечки — у `docs/decisions.md`.

## Точка передачі (24.09.2026) — звідси продовжувати новий діалог

**Де зупинились:**
- Етапи 1–7 злиті в `main` (видалення, редагування, CSV, категорії, імпорт, статистика, підписки).
- **Етап 8 «Доходи»** — гілка `stage-8-income`, коміт `df0945f`, **чекає вердикту PM на гейті B**.
  PM сам проганяв повний набір UI-тестів. Власні перевірки зелені: SELFCHECK OK,
  103/103 перекладено, оновлення V3 → V4 — `UPGRADE OK`, мутації фільтра доходу червоні.
  Результат останнього прогону PM: `/tmp/kalyta-pm-dd/Logs/Test/*.xcresult` (найновіший);
  прочитати: `xcrun xcresulttool get test-results summary --path <xcresult>`.
  Після GO: squash-merge у `main` з нормальним повідомленням, видалити гілку.
- **Гейт A для QR та іконки** — позицію клієнта отримано (записано в `docs/decisions.md`,
  розділ «Гейт A: фіскальний QR та іконка — позиція клієнта»), **PM ще не питали**.

**Процес етапу (див. `.claude/agents/pm.md`, `client.md`, пам'ять `project-kalyta-ios`):**
1. Гейт A: план → PM і клієнт паралельно → суперечка → переможця записати в `docs/decisions.md`.
2. Гілка `stage-N-…`, код, самоперевірка й UI-тести, **кожна нова логіка — мутацією червона**.
3. Гейт B: PM сам проганяє все. Поки він тестує — **симулятор «iPhone 17» не чіпати**
   (два прогони вбивають застосунок одне одному); мутації — на клоні.
4. GO → squash-merge. Агенти `pm` і `client` у новому діалозі треба запустити заново
   (через `general-purpose` з інструкцією «прочитай `.claude/agents/<name>.md` і дій за ним»).
   PM інколи губить сповіщення після прогону — перевіряти xcresult і нагадувати.

**Команди:**
```sh
SP=<scratchpad>; xcodebuild -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $SP/dd build
xcrun simctl launch --console-pty "iPhone 17" org.merzlov.kalyta --selfcheck -AppleLocale uk_UA   # → SELFCHECK OK
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 90          # ~31 тест, 2 пропущено навмисно
scripts/check-translations.py; swift format lint -r Kalyta KalytaUITests
# рядки з коду в каталог (CLI не синхронізує сам):
xcrun xcstringstool sync Kalyta/Localizable.xcstrings --stringsdata <кожен .stringsdata з DerivedData/Kalyta.build>
```

## Зараз

- [ ] **Фіскальний QR → автозаповнення суми й дати.** Позиції чека недоступні (reCAPTCHA).
      Клієнт: кнопка «Сканувати чек» в аркуші вводу (VisionKit `DataScannerViewController`);
      **якщо витрата з тією ж сумою вже є в межах ~30 хв (Apple Pay уже записав) — відкрити її, а не створювати нову**;
      «Не фіскальний чек» для чужих QR; розбір локально, без мережі. Чекає позиції PM.
- [ ] **Іконка застосунку.** Клієнт: гліф калити (гаманця) у градієнті teal → indigo; світла, темна й тонована
      з одного джерела (Icon Composer / Asset Catalog). Чекає позиції PM.
