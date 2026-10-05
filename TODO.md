# Kalyta — відкриті задачі

Єдиний список задач проєкту. Зроблене переїжджає в розділ «Стан» README,
рішення й суперечки — у `docs/internal/decisions.md`.

## Точка передачі (05.10.2026) — звідси продовжувати новий діалог

**05.10.2026:** у `main` (`f6bec66`, Forgejo + GitHub): валюти етап 1, нова структура, README/CONTRIBUTING/SECURITY, повний бекап, «Автоматизація» етап 1. Далі: «Автоматизація» S2 (Back Tap; спершу на iPhone перевірити, чи список Back Tap показує App Shortcut «Додати витрату» без імпорту), S3 (інструкції + знімки з симулятора), S4 (знімки з iPhone по USB); валюти етап 2 (картки monobank USD/EUR). Платний Developer Program — користувач оформлює.

**01.10.2026 зроблено:** Тильний дотик питає категорію; monobank читає гривневий рахунок із `client-info`;
надходження з monobank (банки пропускаються, повернення й перекази — без імен); вкладка «Надходження»;
знімки в інструкції автозапису (кроки 1 і 3). Збірка стоїть на iPhone; ставиться й по Wi-Fi (`devicectl`).

**Чекає рішення користувача:**
- [ ] Прибрати надходження з вкладки «Витрати» (сума дня зараз складає їх із витратами) — ~15 хв.
- [ ] Валюти, етап 1: сума у валюті + гривні за курсом НБУ на день запису; поруч курс monobank/НБУ сьогодні.
      Етап 2 — валютні картки monobank. Дослідження — `docs/internal/decisions.md` не записано, підсумок у vault [[55 Kalyta]].
- [ ] 4 питання по надходженнях (кінець `docs/internal/decisions.md`, «revisit with the user»): пам'ять категорій для переказів,
      умова «банк» для зняття з банки, злиття з ручними надходженнями, «надгробки» для видалених банківських записів.
- [ ] Знімок кроку 2 інструкції (Shortcuts → Automation → Transaction) — лише з iPhone; можливо, крок 3 зайвий на iOS 27.
- [ ] Звірити правила «Скасування.» / «Часткове зняття банки» зі справжньою випискою.

**Борг після 01.10:**
- [ ] `StatisticsUITests.testPendingDeletionIsNotInStatistics` падає й на старому `main` («Комуналка» не з'являється; підозра — демо-дата «вчора» в четвер, SelfCheck.swift:153).
- [ ] Перевірка «видалення під час синхронізації» для «надгробків» (хук у FakeTransport між двома запитами).
- [ ] У `docs/internal/decisions.md` для B + надгробків — таблиця мутацій з рядками асертів, як на етапі 14.

**Стан на 25.09:** усі 15 етапів у `main`, гілок і worktree етапів немає. Відкриті лише перевірки на справжньому iPhone
(«Зараз») і рішення про розповсюдження (нижче). Що вміє застосунок — README, «Стан»; чому саме так — `docs/internal/decisions.md`.

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
1. Гейт A: план → PM і клієнт паралельно → суперечка → переможця записати в `docs/internal/decisions.md`.
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
xcrun xcstringstool sync Kalyta/Resources/Localizable.xcstrings --stringsdata <кожен .stringsdata з DerivedData/Kalyta.build>
```

## Етап 16 — готовність до App Store

Документи вже є: `LICENSE` (MIT), `docs/privacy.md`, `docs/support.md`, `docs/internal/app-review-notes.md`,
`docs/review/sample-receipt-qr.png`. Лишилось (переважно рішення й дії користувача):

- [ ] **Платний Apple Developer Program** (99 USD/рік) — без нього ні TestFlight, ні App Store.
- [ ] **Віковий рейтинг** — анкета в App Store Connect; **категорія** — Finance.
- [ ] **Опис і ключові слова** українською й англійською; що нового; URL підтримки й політики.
- [ ] **App Review:** вставити `docs/internal/app-review-notes.md` у Review Notes, додати QR-зразок як вкладення.
- [ ] **TestFlight:** опис бети, email для відгуків; для зовнішніх тестувальників перша збірка проходить App Review.

## Зараз — перевірки на справжньому iPhone (користувач)

- [ ] **Чек (етап 9):** камера дозволена / заборонена, справжній чек АТБ, збіг чека із записом Apple Pay.
- [ ] **Автоматизація «Транзакція»:** спрацьовує мовчки й передає продавця та суму; якщо можна — оплата в іноземній
      валюті (чи не запишеться як гривні).
- [ ] **monobank (етап 11):** справжній токен; чи повертає monobank сам у Safari після підтвердження;
      після першої синхронізації в «Перекази» не потрапили поповнення банок; фонове оновлення; перевстановлення
      видаляє токен; відкликання токена на api.monobank.ua — тоді прибрати «перевірити» в README.
- [ ] **Сканер одним тапом (етап 12):** кнопка в Пункті керування відкриває сканер (дія мусить виконатися в процесі
      застосунку); віджети на екрані блокування; кнопка дії й Тильний дотик; фраза Siri українською;
      безкоштовна команда реєструє App ID `.widgets`.
- [ ] **Сума за сьогодні (етап 14):** після оновлення записи на місці; сума прихована на заблокованому екрані
      й у StandBy; о півночі — 0 без відкриття застосунку; безкоштовна команда створює App Group для обох
      ідентифікаторів; запис через Тильний дотик чи автоматизацію при закритому застосунку з’являється у віджеті.

- [ ] `ShortcutUpgradeUITests.swift:45`: перед `typeText` тапнути поле суми й дочекатись клавіатури; прогнати `scripts/check-shortcut-upgrade.sh` на HEAD перед наступним релізом, що чіпає `QuickAddExpense`. Якщо й далі червоне на :45 — регресія.
- [ ] `StoreCheck.swift:83` (перевідкриття архіву злитого сховища) раз почервоніло й позеленіло при повторі: прогнати `--selfcheck` 20 разів; якщо червоне — закривати/checkpoint WAL джерела перед `StoreMerge.archive`.
