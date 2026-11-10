#!/usr/bin/env bash
set -uo pipefail

# Never operate on a relative/empty home: with HOME="" every "$HOME/..."
# path becomes an absolute system path such as /Library/...
if [ -z "${HOME:-}" ] || [ "${HOME}" = "/" ]; then
  echo "Refusing to run: HOME is empty or '/'" >&2
  exit 2
fi

# Single source of truth for the modules handled by this script. The order is
# meaningful: totals are emitted in this order. Keep in sync with
# CleanupModuleCatalog.swift.
MODULE_IDS="xcode xcode-archives xcode-simulators swiftpm cocoapods carthage packages ai docker"

MODE="analyze"
MODULES_CSV=$(printf '%s' "$MODULE_IDS" | tr ' ' ',')

while [ $# -gt 0 ]; do
  case "$1" in
    --execute)   MODE="execute" ;;
    --analyze)   MODE="analyze" ;;
    --modules)   shift; MODULES_CSV="${1:-}" ;;
    --modules=*) MODULES_CSV="${1#*=}" ;;
  esac
  shift
done

# Exact membership test: the module list is a CSV of identifiers, and no
# shell pattern matching (a module id containing glob characters would
# otherwise match a substring).
selected() {
  local rest="$MODULES_CSV" id
  while [ -n "$rest" ]; do
    id="${rest%%,*}"
    [ "$id" = "$1" ] && return 0
    [ "$id" = "$rest" ] && break
    rest="${rest#*,}"
  done
  return 1
}

is_module() {
  case " $MODULE_IDS " in
    *" $1 "*) return 0 ;;
    *)        return 1 ;;
  esac
}

# Absolute path of this script. When the app is launched from Xcode it lives
# inside ~/Library/Developer/Xcode/DerivedData, so a naive `rm -rf DerivedData`
# would delete the running app bundle along with this script.
SELF_PATH="${BASH_SOURCE[0]:-$0}"
case "$SELF_PATH" in
  /*) ;;
  *)  SELF_PATH="$PWD/$SELF_PATH" ;;
esac

# Keep the whole .app bundle containing this script (so the running app
# survives); if the script is not inside a bundle, keep just the directory
# chain leading to it.
KEEP_PATH="$SELF_PATH"
_probe="$SELF_PATH"
while [ -n "$_probe" ]; do
  case "$_probe" in
    *.app) KEEP_PATH="$_probe"; break ;;
  esac
  _probe="${_probe%/*}"
done

# Incremented whenever a deletion or cleanup command fails, so the caller can
# report a non-zero exit code instead of a misleading "success".
ERRORS=0

# Delete a directory, but never the bundle that contains this script.
# `-L` keeps broken symlinks visible: `[ -e ]` alone is false for them, so a
# dangling link would silently survive (or be skipped while walking).
remove_keeping_self() {
  local dir="$1" child
  [ -e "$dir" ] || [ -L "$dir" ] || return 0
  case "$KEEP_PATH" in
    "$dir")   return 0 ;;                 # this dir is the bundle: keep it
    "$dir"/*) ;;                          # bundle lives below: descend
    *)        rm -rf "$dir" 2>/dev/null || ERRORS=$((ERRORS + 1)); return 0 ;;
  esac
  for child in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [ -e "$child" ] || [ -L "$child" ] || continue
    remove_keeping_self "$child"
  done
  return 0
}

# macOS ships bash 3.2, which has no associative arrays, so per-module totals
# live in T_<MODULE> variables addressed through indirect expansion.
module_var() {
  printf 'T_%s' "$(printf '%s' "$1" | tr '[:lower:]-' '[:upper:]_')"
}

for _module in $MODULE_IDS; do
  eval "$(module_var "$_module")=0"
done
unset _module

total_of() {
  is_module "$1" || { echo 0; return; }
  local var
  var=$(module_var "$1")
  eval "printf '%s' \"\${$var}\""
}

add_total() {
  is_module "$1" || return 0
  local var
  var=$(module_var "$1")
  eval "$var=\$(( $var + $2 ))"
}

module_name() {
  case "$1" in
    xcode)            echo "Xcode & iOS" ;;
    xcode-archives)   echo "Xcode Archives" ;;
    xcode-simulators) echo "Simulator data (erase all)" ;;
    swiftpm)          echo "SwiftPM" ;;
    cocoapods)        echo "CocoaPods" ;;
    carthage)         echo "Carthage" ;;
    packages)         echo "Package managers" ;;
    ai)               echo "AI agents" ;;
    docker)           echo "Docker" ;;
    *)                echo "$1" ;;
  esac
}

human_bytes() {
  local b=$1
  if   [ "$b" -ge 1073741824 ]; then awk -v b="$b" 'BEGIN{printf "%.2fG", b/1073741824}'
  elif [ "$b" -ge 1048576 ];    then awk -v b="$b" 'BEGIN{printf "%.1fM", b/1048576}'
  elif [ "$b" -ge 1024 ];       then awk -v b="$b" 'BEGIN{printf "%.0fK", b/1024}'
  else echo "${b}B"; fi
}

dir_bytes() {
  [ -e "$1" ] || { echo 0; return; }
  du -sk "$1" 2>/dev/null | awk '{print $1*1024}' || echo 0
}

handle_dir() {
  local module="$1" desc="$2" target="$3"
  if [ ! -e "$target" ]; then
    printf "  %-50s %s\n" "$desc" "(not found)"
    return 0
  fi
  local b; b=$(dir_bytes "$target")
  add_total "$module" "$b"
  printf "  %-50s %s\n" "$desc" "$(human_bytes "$b")"
  [ "$MODE" = "execute" ] && remove_keeping_self "$target"
  return 0
}

handle_cmd() {
  local module="$1" desc="$2" measure_dir="$3"; shift 3
  local b=0
  if [ -n "$measure_dir" ] && [ -e "$measure_dir" ]; then
    b=$(dir_bytes "$measure_dir")
    add_total "$module" "$b"
    printf "  %-50s %s\n" "$desc" "$(human_bytes "$b")"
  else
    printf "  %-50s %s\n" "$desc" "(no size)"
  fi
  if [ "$MODE" = "execute" ]; then
    # The command's output is indented before it reaches the log, so a
    # misbehaving command cannot forge `@@MODULE`/`@@DONE` protocol lines.
    if "$@" 2>&1 | sed 's/^/    /'; then
      :
    else
      echo "    (command failed)"
      ERRORS=$((ERRORS + 1))
    fi
  fi
  return 0
}

emit() {
  local m="$1"
  echo "@@MODULE|$m|$(module_name "$m")|$(total_of "$m")"
}

begin_module() {
  echo "=== $1 ==="
}

end_module() {
  emit "$1"
  echo
}

# ---------- AI agents ----------
handle_ai() {
  begin_module "AI agents"

  # Claude Desktop
  handle_dir ai "Claude Desktop cache" "$HOME/Library/Caches/com.anthropic.claudefordesktop"
  handle_dir ai "Claude Desktop ShipIt" "$HOME/Library/Caches/com.anthropic.claudefordesktop.ShipIt"
  # Claude Code (CLI)
  handle_dir ai "Claude Code cache" "$HOME/.cache/claude"

  # ChatGPT
  handle_dir ai "ChatGPT cache (com.openai.chat)" "$HOME/Library/Caches/com.openai.chat"
  handle_dir ai "ChatGPT Helper cache" "$HOME/Library/Caches/ChatGPTHelper"
  handle_dir ai "ChatGPT cache (com.openai.ChatGPT)" "$HOME/Library/Caches/com.openai.ChatGPT"

  # OpenCode
  handle_dir ai "OpenCode cache (Library)" "$HOME/Library/Caches/opencode"
  handle_dir ai "OpenCode cache (XDG)" "$HOME/.cache/opencode"

  # MiMo Code
  handle_dir ai "MiMo Code cache" "$HOME/.cache/mimocode"

  # Xiaomi MiMo AI (desktop): bundle ids may change, so discover cache
  # directories by a bundle-id-like prefix inside Caches only. Application
  # Support is never touched, and unrelated names containing "mimo" are not
  # matched. `find -print0` keeps paths with spaces intact.
  local d name
  while IFS= read -r -d '' d; do
    name=$(basename "$d")
    handle_dir ai "Xiaomi MiMo cache ($name)" "$d"
  done < <(find "$HOME/Library/Caches" -maxdepth 1 -type d \
             \( -iname 'com.xiaomi*' -o -iname 'com.mimo*' \) -print0 2>/dev/null)

  end_module ai
}
# --------------------------------

echo ">>> MODE: $MODE"
echo ">>> Modules: $MODULES_CSV"
echo

if selected xcode; then
  begin_module "Xcode & iOS"
  handle_dir xcode "DerivedData"           "$HOME/Library/Developer/Xcode/DerivedData"
  handle_dir xcode "iOS DeviceSupport"     "$HOME/Library/Developer/Xcode/iOS DeviceSupport"
  handle_dir xcode "watchOS DeviceSupport" "$HOME/Library/Developer/Xcode/watchOS DeviceSupport"
  handle_dir xcode "tvOS DeviceSupport"    "$HOME/Library/Developer/Xcode/tvOS DeviceSupport"
  handle_dir xcode "Xcode cache"           "$HOME/Library/Caches/com.apple.dt.Xcode"
  handle_dir xcode "CoreSimulator cache"   "$HOME/Library/Developer/CoreSimulator/Caches"
  handle_cmd xcode "Remove unavailable simulators" "" xcrun simctl delete unavailable
  end_module xcode
fi

if selected xcode-archives; then
  begin_module "Xcode Archives"
  handle_dir xcode-archives "Xcode Archives" "$HOME/Library/Developer/Xcode/Archives"
  end_module xcode-archives
fi

if selected xcode-simulators; then
  begin_module "Simulator data (ERASE ALL)"
  handle_cmd xcode-simulators "Erase all simulators" "" xcrun simctl erase all
  end_module xcode-simulators
fi

if selected swiftpm; then
  begin_module "SwiftPM"
  handle_dir swiftpm "SwiftPM cache" "$HOME/Library/Caches/org.swift.swiftpm"
  end_module swiftpm
fi

if selected cocoapods; then
  begin_module "CocoaPods"
  handle_dir cocoapods "CocoaPods cache" "$HOME/Library/Caches/CocoaPods"
  handle_cmd cocoapods "pod cache clean" "" pod cache clean --all
  end_module cocoapods
fi

if selected carthage; then
  begin_module "Carthage"
  handle_dir carthage "CarthageKit cache" "$HOME/Library/Caches/org.carthage.CarthageKit"
  handle_dir carthage "carthage cache"    "$HOME/Library/Caches/carthage"
  end_module carthage
fi

if selected packages; then
  begin_module "Package managers"
  handle_dir packages "Homebrew cache" "$HOME/Library/Caches/Homebrew"
  handle_dir packages "npm cache"      "$HOME/.npm/_cacache"
  handle_dir packages "yarn cache"     "$HOME/Library/Caches/Yarn"
  handle_dir packages "pnpm store"     "$HOME/.pnpm-store"
  handle_dir packages "gradle caches"  "$HOME/.gradle/caches"
  handle_dir packages "pip cache"      "$HOME/Library/Caches/pip"
  handle_dir packages "uv cache"       "$HOME/.cache/uv"
  handle_dir packages "go build cache" "$HOME/Library/Caches/go-build"
  end_module packages
fi

if selected ai; then
  handle_ai
fi

if selected docker; then
  begin_module "Docker"
  # Only build cache and unused images. Volumes are deliberately left alone:
  # `--volumes` would delete user data (databases, state) of stopped containers.
  # Never delete Docker.raw itself — it is the VM disk, not a cache file.
  # Its size is not reported either: pruning does not shrink Docker.raw, so a
  # measured size would promise space that cleaning cannot free.
  echo "  Note: Docker.raw is not measured — pruning does not shrink the VM disk."
  handle_cmd docker "Docker build cache (Docker.raw not affected)" "" docker builder prune -af
  handle_cmd docker "Docker unused images" "" docker image prune -af
  end_module docker
fi

echo "@@DONE"

if [ "$ERRORS" -gt 0 ]; then
  echo ">>> $ERRORS operation(s) failed." >&2
  exit 1
fi
