#!/usr/bin/env bash
set -u

pane_id=${1:-}
state=${2:-}
message=${3:-}

case "$state" in
  working|blocked|idle) ;;
  *) exit 0 ;;
esac

if [ -z "$pane_id" ]; then
  exit 0
fi

backend_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
backend="$backend_dir/zellij-agent-report.sh"

if [ ! -x "$backend" ]; then
  exit 0
fi

"$backend" "$pane_id" "$state" "$message"
