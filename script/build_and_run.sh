#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
BUILD_ARGS=()
APP_PATH="$ROOT_DIR/dist/Wuwa Tappo.app"
PROCESS_NAME=WuwaTappo
if [[ "${1:-}" == --offline-full-atlas ]]; then
  BUILD_ARGS=(--offline-full-atlas)
  APP_PATH="$ROOT_DIR/dist/Wuwa Tappo Offline.app"
  PROCESS_NAME=WuwaTappoOffline
  shift
fi
MODE="${1:-run}"
case "$MODE" in run|--settings|--online-check|--native-check|--debug|--logs|--telemetry|--verify) ;; *) echo "usage: $0 [--offline-full-atlas] [--settings|--online-check|--native-check|--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
killall -TERM "$PROCESS_NAME" >/dev/null 2>&1 || true
for _ in {1..100}; do
  if ! pgrep -x "$PROCESS_NAME" >/dev/null; then break; fi
  sleep 0.1
done
if pgrep -x "$PROCESS_NAME" >/dev/null; then
  echo "旧实例仍在保存，未替换应用包；请处理退出提示后重试。" >&2
  exit 1
fi
python3 scripts/build-macos.py ${BUILD_ARGS[@]+"${BUILD_ARGS[@]}"}
if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$APP_PATH/Contents/MacOS/$PROCESS_NAME"
fi
if [[ "$MODE" == --settings ]]; then
  open -n "$APP_PATH" --args --show-settings
elif [[ "$MODE" == --online-check ]]; then
  open -n "$APP_PATH" --args --show-login --online-report "$ROOT_DIR/build/online-state.json"
elif [[ "$MODE" == --native-check ]]; then
  open -n "$APP_PATH" --args --native-socket --show-settings --online-report "$ROOT_DIR/build/online-state.json"
else
  open -n "$APP_PATH"
fi
case "$MODE" in
  --logs) exec /usr/bin/log stream --info --style compact --predicate "process == \"$PROCESS_NAME\"";;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "io.lliooly.wuwa-tappo.mac"';;
  --verify) sleep 1; pgrep -x "$PROCESS_NAME" >/dev/null;;
esac
