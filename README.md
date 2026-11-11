# Dev Cache Cleaner (DevClean)

A native macOS utility built with SwiftUI for cleaning developer caches. On launch, the app
first runs an analysis and shows a **breakdown of 11 modules with real sizes**, then you
select the modules you want and clean only those.

## Requirements

- macOS 14 or later
- Xcode 27.2 or later (the project uses the new `project.xcproj` format)

## Build and run

### In Xcode

1. Open `DevClean.xcodeproj`.
2. Select the **DevClean** scheme and the **My Mac** destination.
3. Press **⌘R**.

### From the terminal

```bash
xcodebuild -scheme DevClean -configuration Release \
  -derivedDataPath .build CODE_SIGN_IDENTITY="-" build

open .build/Build/Products/Release/DevClean.app
```

The app is ad-hoc signed. When moved to another Mac, Gatekeeper may ask you to
open it via the context menu → **Open**.

## Architecture

The project follows MVVM; dependencies are assembled in a single composition root
(`App/AppDependencies.swift`).

- `Domain/` — models and the module catalog (`CleanupModuleCatalog` — the single
  source of truth for the module list), plus the `CleanupRunState` state machine.
- `Services/` — infrastructure behind protocols: locating the script in the bundle,
  running the process and streaming output, parsing the `@@...` protocol, the clipboard.
- `ViewModels/` — `CleanupViewModel`: screen state and intents
  (`startIfNeeded`, `analyze`, `cleanSelected`, `cancel`).
- `Views/` — presentation only; each section of the screen is a separate View.
- `Support/` — shared helpers (size formatting).

Data flow: View → ViewModel → services → `clean-dev-cache.sh` → parser events →
ViewModel → View.


## How it works

1. On launch, the app automatically runs
   `clean-dev-cache.sh --analyze --modules <all 11>`. The log updates in
   real time as output arrives.
2. The script ends each section with a line `@@MODULE|id|name|bytes`. The app
   intercepts these lines, adds the module to the list, and displays the size via
   `ByteCountFormatter` (`.file` style). Service `@@...` lines never appear in the log.
3. By default, 7 of the 11 modules are selected. **Xcode Archives**, **Simulator data (erase all)**,
   **Android Emulators (AVD)**, and **Docker** are not selected — see below.
4. **Rescan** repeats the analysis. **Clean selected** shows a
   confirmation with the list of modules and runs
   `--execute --modules id1,id2,...` for the selected ones only.
5. While running, a `ProgressView` and a **Cancel** button are visible (SIGTERM). After a successful
   cleanup, a new analysis starts automatically, so the sizes on screen
   update (cleaned modules show near zero; `docker`'s size does not decrease,
   see the table below).
6. If you cancel a cleanup, the module list and sizes remain in place — you can
   retry or rescan.
7. If you cancel an analysis, the list stays incomplete: cleanup is blocked until
   you rescan (a warning appears in the list header).

### Modules

| ID | Name in UI | What is cleaned |
| --- | --- | --- |
| `xcode` | Xcode & iOS | DerivedData, iOS/watchOS/tvOS DeviceSupport, Xcode cache, CoreSimulator cache, unavailable simulators (`simctl delete unavailable`) |
| `xcode-archives` | Xcode Archives | `~/Library/Developer/Xcode/Archives` |
| `xcode-simulators` | Simulator data (erase all) | `xcrun simctl erase all` — data of **all** simulators |
| `swiftpm` | SwiftPM | `~/Library/Caches/org.swift.swiftpm` |
| `cocoapods` | CocoaPods | `~/Library/Caches/CocoaPods` + `pod cache clean --all` |
| `carthage` | Carthage | `~/Library/Caches/org.carthage.CarthageKit`, `~/Library/Caches/carthage` |
| `packages` | Package managers | Homebrew, npm, yarn, pnpm, pip, uv, Go build cache |
| `ai` | AI agents | Caches of Claude Desktop/Code, ChatGPT, OpenCode, MiMo Code, and Xiaomi MiMo AI |
| `android` | Android Studio | IDE caches and logs for every installed Android Studio version, Gradle caches and wrapper distributions, `~/.android/cache`, `~/.android/build-cache` |
| `android-avd` | Android Emulators (AVD) | `~/.android/avd` — data of **all** emulators (apps, settings, snapshots) |
| `docker` | Docker | `docker builder prune -af`, `docker image prune -af`; size is unknown before cleanup (`Docker.raw` does not shrink on prune) |

### What the `ai` module cleans

Only caches are deleted; `~/Library/Application Support/...` is left untouched so that
settings and history are not lost.

- **Claude Desktop**: `~/Library/Caches/com.anthropic.claudefordesktop`,
  `~/Library/Caches/com.anthropic.claudefordesktop.ShipIt`
- **Claude Code (CLI)**: `~/.cache/claude`
- **ChatGPT**: `~/Library/Caches/com.openai.chat`, `~/Library/Caches/ChatGPTHelper`,
  `~/Library/Caches/com.openai.ChatGPT`
- **OpenCode**: `~/Library/Caches/opencode`, `~/.cache/opencode`
- **MiMo Code**: `~/.cache/mimocode`
- **Xiaomi MiMo AI**: directories inside `~/Library/Caches` whose names start
  with `com.xiaomi` or `com.mimo` (case-insensitive). Pattern matching is needed
  because the app's bundle ID may change; `find --print0` correctly
  handles spaces in paths.

Missing paths are skipped and shown in the log as `(not found)`.

### What the `android` module cleans

The module removes only regenerable caches and logs:

- **IDE caches**: every `~/Library/Caches/Google/AndroidStudio*`,
  `~/Library/Caches/AndroidStudio*`, and `~/Library/Caches/JetBrains/AndroidStudio*`
  directory. The glob is needed because versioned names such as `AndroidStudio2024.1`
  change between releases.
- **IDE logs**: `~/Library/Logs/Google/AndroidStudio*`.
- **Gradle**: `~/.gradle/caches` and `~/.gradle/wrapper/dists`.
- **Android SDK caches**: `~/.android/cache` and `~/.android/build-cache`.

It deliberately does **not** touch:

- `~/Library/Application Support/Google/AndroidStudio*` — IDE settings, installed
  plugins, and local history live there. Deleting it would reset the IDE
  configuration instead of freeing disposable space.
- `~/.android/avd` — emulator data is user data, not a cache. It is available only
  through the separate `android-avd` module.
- `~/.gradle/daemon` and `~/.gradle/native` — these are working files used by the
  Gradle daemon and native integrations, not caches.

Gradle caches used to be part of `packages`. They now belong to `android`: if you
previously cleaned them via **Package managers**, select **Android Studio** instead —
the `packages` module no longer touches Gradle.

`android-avd` is off by default because emulator data is not a cache. Deleting
`~/.android/avd` permanently removes every emulator together with its state
(installed apps, settings, snapshots), so it runs only when explicitly checked.

### Why `xcode-archives`, `xcode-simulators`, `android-avd`, and `docker` are off by default

Xcode archives (`.xcarchive`) contain dSYMs and binaries from past builds. They are needed for
symbolicating crashes and sometimes for re-signing/exporting a build. They are not "junk"
that is safe to delete on every cleanup, so this module is enabled only manually.

`xcode-simulators` also requires a deliberate choice: `simctl erase all` wipes the data
of all simulators, not just caches.

`android-avd` follows the same rule: `~/.android/avd` holds emulator disks and snapshots,
so cleaning it destroys the devices themselves, not their caches.

`docker` is off because cleaning Docker affects the daemon's shared resources, not
just the current project's cache. The module deletes the build cache and unused images;
**volumes are not touched** — they often hold databases and the state of
stopped containers.

## App Sandbox

The sandbox is **disabled** in the project (`ENABLE_APP_SANDBOX = NO`); otherwise the process
would not get access to `~/Library/Developer/...`, `~/Library/Caches/...`, and the home
directories of package managers. At the same time, **Hardened Runtime is enabled**
(`ENABLE_HARDENED_RUNTIME = YES`); it applies to builds with a proper signature
(the ad-hoc signature from the example above disables it — that is an ad-hoc limitation,
not a project setting).

If you re-enable the setting or create the target from scratch:

1. Select the **DevClean** target → **Signing & Capabilities** tab.
2. Remove/uncheck **App Sandbox**.
3. Alternatively, set `ENABLE_APP_SANDBOX = NO` in **Build Settings**.

This is a personal utility, not intended for the App Store.

## Running the script manually

You can run the script from the terminal for debugging — it prints `@@MODULE|...` at the end
of each section and `@@DONE` at the end:

```bash
DevClean/clean-dev-cache.sh --analyze
DevClean/clean-dev-cache.sh --analyze --modules xcode,packages
DevClean/clean-dev-cache.sh --execute --modules xcode
```

The script targets bash 3.2+, which ships with macOS: associative arrays
(`declare -A`, which require bash 4) are not used, so `#!/usr/bin/env bash`
works without installing Homebrew bash.

## Errors in the UI

Script errors are shown in the UI, not just in the Xcode console:

- **Status label** next to the action buttons instead of a raw `Exit code: N`.
  The result type is classified in `CleanupRunIssue`
  (`DevClean/Domain/CleanupRunIssue.swift`): success, cancellation, partial errors
  (`N operation(s) failed.` from stderr), non-zero exit code, timeout,
  signal termination, script launch failure. Each type has a clear
  localized text, color (green/orange/red/gray), icon, and
  a tooltip with a recommendation (`.help`).
- **stderr highlighting in the log.** `CleanupViewModel` stores output as
  `LogLine(text:isFromStderr:)`, and `LogPanelView` renders stderr lines
  in red via `AttributedString`. The full raw stdout+stderr is still
  available in its entirety, including the copy button.

## Technical decisions

- **PATH.** GUI apps do not inherit PATH from `.zshrc`, so
  `/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin` is set explicitly in
  `Process.environment`.
- **Launch.** `Process` runs `/bin/bash <pathToScript> --analyze|--execute
  --modules id1,id2,…`: the script path is passed as argv, without an intermediate
  shell and without interpolation, so special characters in the path are safe. The executable bit
  and a valid shebang are not required — bash receives the path as an argument.
- **Streaming.** stdout and stderr are read independently via `Pipe` +
  `FileHandle.readabilityHandler`; data is buffered up to whole lines at the byte level,
  so multi-byte UTF-8 characters and the `@@MODULE|...` line are not split between chunks.
  Trailing output is appended in the same MainActor job as the termination result;
  all state updates run on `@MainActor`.
- **Termination.** `terminationHandler` waits for the remaining output (non-blocking
  reads, so a hung child process cannot block the UI), prints the exit code,
  and resets the state. After a successful `--execute`, `analyze()` is called.
- **Cancellation.** `SIGTERM` is sent to the process group directly
  (`killpg` if the process is the group leader), followed by `SIGKILL` after 3 seconds
  if the process has not terminated. After cancellation, no automatic re-analysis is
  started.

## Tests

Unit tests cover the output parser, the module catalog, the run state, the ViewModel,
line-by-line reading, process launching, and the bash script itself (in an isolated temporary `HOME`).

```bash
xcodebuild test -scheme DevClean -destination 'platform=macOS' -derivedDataPath .build
```

Tests do not touch the real home directory, and `docker` and `xcrun` are replaced by
shim scripts, so real images and simulators are not affected.
