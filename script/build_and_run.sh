#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
MODE="${1:-run}"
case "$MODE" in run|--settings|--debug|--logs|--telemetry|--verify) ;; *) echo "usage: $0 [--settings|--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
killall -TERM WuwaTappo >/dev/null 2>&1 || true
for _ in {1..100}; do
  if ! pgrep -x WuwaTappo >/dev/null; then break; fi
  sleep 0.1
done
if pgrep -x WuwaTappo >/dev/null; then
  echo "旧实例仍在保存，未替换应用包；请处理退出提示后重试。" >&2
  exit 1
fi
python3 scripts/build-macos.py
if [[ "$MODE" == --debug ]]; then
  exec lldb -- "$ROOT_DIR/dist/Wuwa Tappo.app/Contents/MacOS/WuwaTappo"
fi
if [[ "$MODE" == --settings ]]; then
  open -n "$ROOT_DIR/dist/Wuwa Tappo.app" --args --show-settings
else
  open -n "$ROOT_DIR/dist/Wuwa Tappo.app"
fi
case "$MODE" in
  --logs) exec /usr/bin/log stream --info --style compact --predicate 'process == "WuwaTappo"';;
  --telemetry) exec /usr/bin/log stream --info --style compact --predicate 'subsystem == "io.lliooly.wuwa-tappo.mac"';;
  --verify) sleep 1; pgrep -x WuwaTappo >/dev/null;;
esac
