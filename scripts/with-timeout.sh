#!/usr/bin/env bash
# with-timeout.sh [SECONDS] command...      (default 30 s hard kill)
#
# Kills the command's ENTIRE descendant tree on timeout — collected before
# anything dies, because some tools (swiftpm-testing-helper) detach into their
# own process group and get re-parented to launchd, escaping a group kill.
#
# The watchdog's own sleep must be interruptible and must not hold the
# caller's stdout/stderr, or a pipeline like `with-timeout … | grep` would sit
# open until the sleep expires even though the command finished instantly.
set -u
secs=30
[[ "${1:-}" =~ ^[0-9]+$ ]] && { secs=$1; shift; }

descendants() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do echo "$c"; descendants "$c"; done; }

"$@" &
pid=$!
exec 3>&2                                            # keep a handle for the timeout message
(
  trap 'kill "$sp" 2>/dev/null; exit 0' TERM
  sleep "$secs" & sp=$!
  wait "$sp"
  kill -0 "$pid" 2>/dev/null || exit 0
  echo "⏱ TIMEOUT after ${secs}s: $*" >&3
  tree="$pid $(descendants "$pid")"
  kill -TERM $tree 2>/dev/null; sleep 1; kill -KILL $tree 2>/dev/null
) >/dev/null 2>&1 &
watchdog=$!
wait "$pid"; status=$?
kill -TERM "$watchdog" 2>/dev/null; wait "$watchdog" 2>/dev/null
exec 3>&-
[[ $status -ge 128 ]] && exit 124 || exit "$status"
