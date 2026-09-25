# Kalyta — відкриті задачі

Єдиний список задач проєкту. Зроблене переїжджає в розділ «Стан» README,
рішення й суперечки — у `docs/decisions.md`.

## Точка передачі (25.09.2026) — звідси продовжувати новий діалог

**Стан:** усі 15 етапів у `main`, гілок і worktree етапів немає. Відкриті лише перевірки на справжньому iPhone
(«Зараз») і рішення про розповсюдження (нижче). Що вміє застосунок — README, «Стан»; чому саме так — `docs/decisions.md`.

**Відкрите рішення — розповсюдження (вирішує користувач):** зараз застосунок ставиться лише з Xcode на свій iPhone
(Personal Team, збірка живе 7 днів). TestFlight потребує платного Apple Developer Program — 99 USD на рік.
Внутрішні тестувальники — до 100 людей з команди розробника, без перевірки Apple; зовнішні — до 10 000,
перша збірка проходить перевірку App Review. Кожна збірка доступна тестувальникам 90 днів.
Джерела: https://developer.apple.com/testflight/, https://developer.apple.com/programs/whats-included/,
https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview.

**Команда — 7 агентів** (визначення в `.claude/agents/`; у новому діалозі запускати заново через `general-purpose`
з інструкцією «прочитай `.claude/agents/<name>.md` і дій за ним»):
`pm` (гейти A/B), `client` (голос користувача), `developer` (код), `tester` (UI-тести й мутації),
`designer` (HIG, ресурси), `security` (рев’ю безпеки), `docs` (README, TODO, рішення, vault). Комітить тимлід.

**Процес етапу:**
1. Гейт A: план → PM і клієнт паралельно → суперечка → переможця записати в `docs/decisions.md`.
2. Гілка `stage-N-…` в окремому worktree. `developer` пише код; паралельно `tester` пише тести й доводить мутаціями,
   що вони червоніють, `designer` робить ресурси й перевіряє екрани, `security` рев’юїть межі довіри.
   Кожен — на своєму симуляторі й зі своїм `-derivedDataPath`; спільний «iPhone 17» — лише для PM.
   Мутаційна копія: `PRODUCT_BUNDLE_IDENTIFIER = org.merzlov.kalyta.mutation` у її `Config/Kalyta.xcconfig`
   і `PRODUCT_NAME = KalytaMutation` у її `project.pbxproj` (ціль застосунку) — не в командному рядку `xcodebuild`.
   Деталі — README, «Перевірка».
3. Гейт B: PM сам проганяє все на тихій машині — повний набір UI-тестів лише один одночасно.
   PM інколи губить сповіщення після прогону — перевіряти xcresult і нагадувати.
4. `docs` записує рішення, TODO, «Стан» README і нотатку у vault.
5. GO → squash-merge у `main`, гілку й worktree видалити.

**Відомі флейки (не регресія):** під навантаженням `EditingUITests` (тап у `PopoverDismissRegion` влучає в чип «Здоров’я»)
і вибір документа в Export/Import; `ImportUITests.testReimportAddsNothing` інколи падає на вікні збереження навіть
на тихій машині — перезапустити. Тести віджетів: встановити → перезавантажити симулятор → запускати.

**Команди:**
```sh
SP=<scratchpad>; xcodebuild -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' -derivedDataPath $SP/dd build
xcrun simctl boot "iPhone 17"; xcrun simctl install "iPhone 17" $SP/dd/Build/Products/Debug-iphonesimulator/Kalyta.app
xcrun simctl launch --console-pty "iPhone 17" org.merzlov.kalyta --selfcheck -AppleLocale uk_UA   # → SELFCHECK OK
perl -e 'alarm 900; exec @ARGV' xcodebuild test -scheme Kalyta -destination 'platform=iOS Simulator,name=iPhone 17' \
  -test-timeouts-enabled YES -default-test-execution-time-allowance 90          # 42 тести, 2 пропущено навмисно
scripts/check-translations.py; swift format lint -r Kalyta KalytaUITests KalytaWidgets
# рядки з коду в каталог (CLI не синхронізує сам):
xcrun xcstringstool sync Kalyta/Localizable.xcstrings --stringsdata <кожен .stringsdata з DerivedData/Kalyta.build>
```

## Етап 16 — готовність до App Store

Документи вже є: `LICENSE` (MIT), `docs/privacy.md`, `docs/support.md`, `docs/app-review-notes.md`,
`docs/review/sample-receipt-qr.png`. Лишилось (переважно рішення й дії користувача):

- [ ] **Платний Apple Developer Program** (99 USD/рік) — без нього ні TestFlight, ні App Store.
- [ ] **Публічні сторінки політики й підтримки.** App Store Connect вимагає посилання на політику конфіденційності
      (і в застосунку, і в метаданих — Guideline 5.1.1(i)) та на підтримку. `git.merzlov.org` закритий
      Cloudflare Access, тож рецензент Apple його не відкриє — потрібна публічна адреса (публічне дзеркало репо
      або статична сторінка). Заповнити в `docs/support.md` адресу issues і пошту (зараз TODO).
- [ ] **Знімки екрана 6.9"** (1320 × 2868, симулятор iPhone 17 Pro Max): наявні `docs/screen-*.png` — 1206 × 2622 (6,3"),
      для App Store не підходять.
- [ ] **Віковий рейтинг** — анкета в App Store Connect; **категорія** — Finance.
- [ ] **Опис і ключові слова** українською й англійською; що нового; URL підтримки й політики.
- [ ] **App Review:** вставити `docs/app-review-notes.md` у Review Notes, додати QR-зразок як вкладення.
- [ ] **TestFlight:** опис бети, email для відгуків; для зовнішніх тестувальників перша збірка проходить App Review.

## Зараз — перевірки на справжньому iPhone (користувач)

- [ ] **Назва в Параметрах:** «Торкання ззаду» — тоді прибрати «перевірити на iPhone» в README.
- [ ] **Чек (етап 9):** камера дозволена / заборонена, справжній чек АТБ, збіг чека із записом Apple Pay.
- [ ] **Автоматизація «Транзакція»:** спрацьовує мовчки й передає продавця та суму; якщо можна — оплата в іноземній
      валюті (чи не запишеться як гривні).
- [ ] **monobank (етап 11):** справжній токен; чи повертає monobank сам у Safari після підтвердження;
      після першої синхронізації в «Перекази» не потрапили поповнення банок; фонове оновлення; перевстановлення
      видаляє токен; відкликання токена на api.monobank.ua — тоді прибрати «перевірити» в README.
- [ ] **Сканер одним тапом (етап 12):** кнопка в Пункті керування відкриває сканер (дія мусить виконатися в процесі
      застосунку); віджети на екрані блокування; кнопка дії й Торкання ззаду; фраза Siri українською;
      безкоштовна команда реєструє App ID `.widgets`.
- [ ] **Сума за сьогодні (етап 14):** після оновлення записи на місці; сума прихована на заблокованому екрані
      й у StandBy; о півночі — 0 без відкриття застосунку; безкоштовна команда створює App Group для обох
      ідентифікаторів; запис через Торкання ззаду чи автоматизацію при закритому застосунку з’являється у віджеті.
