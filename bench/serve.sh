#!/bin/sh
# Start command of the container (Railway, Fly): serve the built site with Caddy and print the runtime markers.
set -eu

mark() {
  now="$(date +%s%3N)"
  case "$now" in *[!0-9]*) now="$(date +%s)000" ;; esac
  printf '::bench::%s %s\n' "$1" "$now"
}

mark start
: "${PORT:=80}"
export PORT
# The run and deployment IDs are runtime env here. Keep the commit that the build wrote.
commit="$(sed -n 's/.*"commit":"\([^"]*\)".*/\1/p' /srv/version)"
printf '{"commit":"%s","run":"%s","deployment":"%s"}\n' "$commit" "${BENCH_RUN_ID:-unknown}" "${RAILWAY_DEPLOYMENT_ID:-unknown}" > /srv/version

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
pid=$!
# Forward the stop signal, so Caddy shuts down cleanly when the platform replaces the instance.
trap 'kill -TERM "$pid" 2>/dev/null' TERM INT
until wget -q -O /dev/null "http://127.0.0.1:$PORT/version" 2>/dev/null; do
  kill -0 "$pid" 2>/dev/null || exit 1
  sleep 0.05
done
mark listening
# The first wait returns when the trap runs; the second one waits for Caddy to exit.
wait "$pid" || wait "$pid"
