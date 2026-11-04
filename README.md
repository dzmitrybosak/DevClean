# Dev Cache Cleaner (DevClean)

Нативная macOS-утилита на SwiftUI для очистки кэшей разработчика. Сначала приложение
запускает анализ и показывает **разбивку по 9 модулям с реальными размерами**, затем вы
отмечаете нужные модули и запускаете очистку только их.

## Требования

- macOS 14 или новее
- Xcode 27.2 или новее (проект использует новый формат `project.xcproj`)

## Сборка и запуск

### В Xcode

1. Откройте `DevClean.xcodeproj`.
2. Выберите схему **DevClean** и destination **My Mac**.
3. Нажмите **⌘R**.

### Из терминала

```bash
xcodebuild -scheme DevClean -configuration Release \
  -derivedDataPath .build CODE_SIGN_IDENTITY="-" build

open .build/Build/Products/Release/DevClean.app
```

Приложение подписано ad-hoc. При переносе на другой Mac Gatekeeper может попросить
открыть его через контекстное меню → **Open**.

## Архитектура

Проект построен по MVVM; зависимости собираются в одном composition root
(`App/AppDependencies.swift`).

- `Domain/` — модели и каталог модулей (`CleanupModuleCatalog` — единственный
  источник правды о списке модулей), конечный автомат `CleanupRunState`.
- `Services/` — инфраструктура за протоколами: поиск скрипта в бандле,
  запуск процесса и стриминг вывода, парсер протокола `@@...`, буфер обмена.
- `ViewModels/` — `CleanupViewModel`: состояние экрана и интенты
  (`startIfNeeded`, `analyze`, `cleanSelected`, `cancel`).
- `Views/` — только представление; каждая секция экрана вынесена в отдельный View.
- `Support/` — общие хелперы (форматирование размеров).

Поток данных: View → ViewModel → сервисы → `clean-dev-cache.sh` → события
парсера → ViewModel → View.


## Как это работает

1. При запуске автоматически выполняется
   `clean-dev-cache.sh --analyze --modules <все 9>`. Журнал обновляется в реальном
   времени по мере поступления вывода.
2. Скрипт завершает каждую секцию строкой `@@MODULE|id|name|bytes`. Приложение
   перехватывает эти строки, добавляет модуль в список и показывает размер через
   `ByteCountFormatter` (стиль `.file`). В журнал служебные строки `@@...` не попадают.
3. По умолчанию отмечены 7 модулей из 9. **Xcode Archives** и
   **Simulator data (erase all)** не отмечены — см. ниже.
4. **Пересканировать** повторяет анализ. **Очистить выбранное** показывает
   подтверждение со списком модулей и запускает
   `--execute --modules id1,id2,...` только для отмеченных.
5. Во время работы видны `ProgressView` и кнопка **Отмена** (SIGTERM). После успешной
   очистки автоматически запускается новый анализ, поэтому размеры на экране
   обновляются (у очищенных модулей — около нуля).
6. Если отменить очистку, список модулей и их размеры остаются на месте — можно
   повторить попытку или пересканировать.

### Модули

| ID | Имя в UI | Что очищается |
| --- | --- | --- |
| `xcode` | Xcode & iOS | DerivedData, iOS/watchOS/tvOS DeviceSupport, кэш Xcode, кэш CoreSimulator, недоступные симуляторы (`simctl delete unavailable`) |
| `xcode-archives` | Xcode Archives | `~/Library/Developer/Xcode/Archives` |
| `xcode-simulators` | Simulator data (erase all) | `xcrun simctl erase all` — данные **всех** симуляторов |
| `swiftpm` | SwiftPM | `~/Library/Caches/org.swift.swiftpm` |
| `cocoapods` | CocoaPods | `~/Library/Caches/CocoaPods` + `pod cache clean --all` |
| `carthage` | Carthage | `~/Library/Caches/org.carthage.CarthageKit`, `~/Library/Caches/carthage` |
| `packages` | Package managers | Homebrew, npm, yarn, pnpm, Gradle, pip, uv, Go build cache |
| `ai` | AI agents | Кэши Claude Desktop/Code, ChatGPT, OpenCode, MiMo Code и Xiaomi MiMo AI |
| `docker` | Docker | `docker system prune -af --volumes`; размер оценивается по `Docker.raw` |

### Что чистит модуль `ai`

Удаляются только кэши; `~/Library/Application Support/...` не затрагивается, чтобы не
потерять настройки и историю.

- **Claude Desktop**: `~/Library/Caches/com.anthropic.claudefordesktop`,
  `~/Library/Caches/com.anthropic.claudefordesktop.ShipIt`
- **Claude Code (CLI)**: `~/.cache/claude`
- **ChatGPT**: `~/Library/Caches/com.openai.chat`, `~/Library/Caches/ChatGPTHelper`,
  `~/Library/Caches/com.openai.ChatGPT`
- **OpenCode**: `~/Library/Caches/opencode`, `~/.cache/opencode`
- **MiMo Code**: `~/.cache/mimocode`
- **Xiaomi MiMo AI**: каталоги внутри `~/Library/Caches`, имя которых совпадает с
  `*Xiaomi*` или `*mimo*` (регистр первой буквы не важен). Поиск по шаблону нужен,
  потому что bundle id приложения может меняться.

Отсутствующие пути пропускаются и показываются в журнале как `(not found)`.

### Почему `xcode-archives` и `xcode-simulators` по умолчанию выключены

Архивы Xcode (`.xcarchive`) содержат dSYM и бинарники прошлых сборок. Они нужны для
символизации крашей и иногда для повторной подписи/экспорта сборки. Это не «мусор»,
который безопасно удалять при каждой очистке, поэтому модуль включается только вручную.

`xcode-simulators` тоже требует осознанного выбора: `simctl erase all` стирает данные
всех симуляторов, а не только кэши.

## App Sandbox

Sandbox **отключён** в проекте (`ENABLE_APP_SANDBOX = NO`), иначе процесс не получит
доступ к `~/Library/Developer/...`, `~/Library/Caches/...` и домашним каталогам
менеджеров пакетов.

Если включаете настройку заново или создаёте target с нуля:

1. Выберите target **DevClean** → вкладка **Signing & Capabilities**.
2. Удалите/снимите галочку **App Sandbox**.
3. Либо в **Build Settings** установите `ENABLE_APP_SANDBOX = NO`.

Это личная утилита, не для App Store.

## Скрипт вручную

Скрипт можно запускать из терминала для отладки — он печатает `@@MODULE|...` в конце
каждой секции и `@@DONE` в конце:

```bash
DevClean/clean-dev-cache.sh --analyze
DevClean/clean-dev-cache.sh --analyze --modules xcode,packages
DevClean/clean-dev-cache.sh --execute --modules xcode
```

Скрипт рассчитан на bash 3.2+, который поставляется с macOS: ассоциативные массивы
(`declare -A`, требующие bash 4) не используются, поэтому `#!/usr/bin/env bash`
работает без установки Homebrew bash.

## Архитектура

| Файл | Назначение |
| --- | --- |
| `DevClean/DevCleanApp.swift` | `@main`, `WindowGroup`, минимальный размер окна |
| `DevClean/ContentView.swift` | Заголовок, список модулей, кнопки, подтверждение, журнал |
| `DevClean/CleanupModel.swift` | `@MainActor ObservableObject`: Process, Pipe, парсер `@@MODULE`, автоанализ |
| `DevClean/CleanupModule.swift` | `Identifiable`-модель модуля |
| `DevClean/clean-dev-cache.sh` | Bash-скрипт, копируется в `Contents/Resources` |

Технические решения:

- **PATH.** GUI-приложения не наследуют PATH из `.zshrc`, поэтому в
  `Process.environment` явно задан
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin`.
- **Запуск.** `Process` запускает `/bin/zsh -c "\"<scriptPath>\" \"$@\"" devclean ...flags`.
  Это не требует executable-бита у ресурса в бандле, а `"$@"` передаёт каждый флаг
  отдельным аргументом. Скрипт лежит в бандле с правами `755`.
- **Стриминг.** stdout и stderr читаются независимо через `Pipe` +
  `FileHandle.readabilityHandler`; данные буферизуются до целых строк на уровне байтов,
  поэтому многобайтовые UTF-8 символы и строка `@@MODULE|...` не рвутся между чанками.
  Все обновления `@Published` выполняются на `@MainActor`.
- **Завершение.** `terminationHandler` дожидается остатков вывода (неблокирующее
  чтение, чтобы зависший дочерний процесс не блокировал UI), печатает код выхода
  и сбрасывает состояние. После успешного `--execute` вызывается `analyze()`.
- **Отмена.** `process.terminate()` (SIGTERM). Автоматический повторный анализ после
  отмены не запускается.
