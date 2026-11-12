#!/bin/sh
set -eu

# Start command of the Caddy image. It prints the runtime markers, which the static file server cannot print.
mark() {
  now="$(date +%s%3N)"
  # BusyBox ignores %N and prints whole seconds; anything but 13 digits falls back to seconds times 1000.
  case "$now" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) now="$(date +%s)000" ;; esac
  printf '::bench::%s %s\n' "$1" "$now"
}

mark start

# The commit is fixed at build time. The run and deployment IDs come from the runtime env, so that a deployment of
# the same image with a new BENCH_RUN_ID (Fly) or a new Railway deployment is told apart from the old one.
commit="$(sed -n 's/.*"commit":"\([^"]*\)".*/\1/p' /srv/version.json)"
printf '{"commit":"%s","run":"%s","deployment":"%s"}\n' \
  "$commit" "${BENCH_RUN_ID:-unknown}" "${RAILWAY_DEPLOYMENT_ID:-unknown}" > /srv/version.json

caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
pid=$!
trap 'kill -TERM "$pid" 2>/dev/null' INT TERM
until wget -q -O /dev/null "http://127.0.0.1:${PORT:-80}/version" 2>/dev/null; do
  kill -0 "$pid" 2>/dev/null || wait "$pid"
  sleep 0.05
done
mark listening
wait "$pid"
