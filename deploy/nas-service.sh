#!/bin/sh
# Follows hearth-tv-launcher's user-level NAS service layout, with an independent runtime.
set -eu
APP_DIR=${TIANZIGE_APP_DIR:-$HOME/.local/share/tianzige-at-home}
case "$APP_DIR" in /*) ;; *) echo "TIANZIGE_APP_DIR must be absolute" >&2; exit 1;; esac
BINARY="$APP_DIR/bin/homework-server"
PIDFILE="$APP_DIR/service.pid"
running() {
  [ -f "$PIDFILE" ] || return 1
  pid=$(cat "$PIDFILE")
  case "$pid" in ""|*[!0-9]*) return 1;; esac
  [ -r "/proc/$pid/cmdline" ] || return 1
  [ "$(readlink "/proc/$pid/exe")" = "$(readlink -f "$BINARY")" ]
}
case "${1:-status}" in
  start)
    running && exit 0
    [ -x "$BINARY" ] || { echo "Missing $BINARY" >&2; exit 1; }
    [ -r "$APP_DIR/server.env" ] || { echo "Configure $APP_DIR/server.env first" >&2; exit 1; }
    mkdir "$APP_DIR/start.lock" 2>/dev/null || { echo "Another start is in progress" >&2; exit 1; }
    trap 'rmdir "$APP_DIR/start.lock"' EXIT
    set -a
    . "$APP_DIR/server.env"
    set +a
    : "${TIANZIGE_LISTEN:?Set TIANZIGE_LISTEN to the private LAN IP and an unused port}"
    export GOMAXPROCS=${GOMAXPROCS:-1} GOMEMLIMIT=${GOMEMLIMIT:-192MiB}
    mkdir -p "$APP_DIR/data"
    umask 077
    setsid "$BINARY" -addr "$TIANZIGE_LISTEN" -data "$APP_DIR/data" -web "$APP_DIR/web" >> "$APP_DIR/server.log" 2>&1 </dev/null &
    echo $! > "$PIDFILE"
    sleep 2
    running || { echo "Service did not start; inspect $APP_DIR/server.log" >&2; exit 1; }
    ;;
  stop)
    if running; then
      kill "$pid"
      n=0
      while running && [ "$n" -lt 20 ]; do sleep 1; n=$((n+1)); done
      running && { echo "Service did not stop; inspect server.log" >&2; exit 1; }
    fi
    rm -f "$PIDFILE"
    ;;
  status)
    if running; then echo running; else echo stopped; exit 1; fi
    ;;
  restart) "$0" stop; "$0" start;;
  *) echo "usage: nas-service.sh start|stop|restart|status" >&2; exit 2;;
esac
