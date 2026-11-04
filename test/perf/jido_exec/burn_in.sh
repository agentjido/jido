#!/bin/sh
set -eu

runs=${1:-10}

case "$runs" in
  ''|*[!0-9]*) echo "run count must be a positive integer" >&2; exit 2 ;;
esac

if [ "$runs" -lt 1 ]; then
  echo "run count must be a positive integer" >&2
  exit 2
fi

index=0
while [ "$index" -lt "$runs" ]; do
  echo "load run $((index + 1))/$runs"
  mix test.load test/perf/jido_exec
  index=$((index + 1))
done
