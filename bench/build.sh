#!/bin/sh
set -eu

# Each marker carries the wall-clock time in epoch milliseconds, so a parser does not depend on the time at which
# the provider received the log line.
mark() {
  now="$(date +%s%3N)"
  # BusyBox ignores %N and prints whole seconds; anything but 13 digits falls back to seconds times 1000.
  case "$now" in [0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9][0-9]) ;; *) now="$(date +%s)000" ;; esac
  printf '::bench::%s %s\n' "$1" "$now"
}

HUGO_VERSION=0.144.2
HUGO_DIR="$PWD/.bench/hugo-$HUGO_VERSION"

# Hugo settings, the same on every provider. They are set here and not in each provider's settings, so they cannot
# drift apart.
# - Git info off: Docker contexts have no .git, and Render's clone does. Upstream's Netlify build has it on.
# - Remote fetches off: the CVE feed and release_binaries.json are fetched at build time upstream; a blocked fetch is
#   a warning in the development environment. A fetch would make the build depend on two third-party endpoints.
# - Memory limit 6 GB: Hugo 0.144.2 deadlocked twice with its default limit on a large machine.
export HUGO_ENABLEGITINFO=false
export HUGO_SECURITY_HTTP_URLS='^https://none\.invalid/'
export HUGO_MEMORYLIMIT=6

# Hugo extended is not on any provider's build image in the same version, so every provider downloads the same
# release. The checksum pins the archive.
install_hugo() {
  case "$(uname -m)" in
    x86_64 | amd64) arch=amd64 sum=961b258ba2478bec4b2756be4f8982b221bf2d6c1b20f0727ad86e84677053d9 ;;
    aarch64 | arm64) arch=arm64 sum=5d0756c3e72a7386f3a3fcd432789c39c3d1239715e147c63bd7a73bbfcfc93f ;;
    *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac
  if [ -x "$HUGO_DIR/hugo" ]; then
    return
  fi
  tgz="hugo_extended_${HUGO_VERSION}_linux-$arch.tar.gz"
  mkdir -p "$HUGO_DIR"
  curl -fsSL -o "$HUGO_DIR/$tgz" "https://github.com/gohugoio/hugo/releases/download/v$HUGO_VERSION/$tgz"
  printf '%s  %s\n' "$sum" "$HUGO_DIR/$tgz" | sha256sum -c -
  tar -xzf "$HUGO_DIR/$tgz" -C "$HUGO_DIR" hugo
  rm "$HUGO_DIR/$tgz"
}

install() {
  mark install_start
  install_hugo
  "$HUGO_DIR/hugo" version
  printf 'node %s, npm %s\n' "$(node --version)" "$(npm --version)"
  # Docsy is a GitHub dependency (git+ssh in the lockfile). npm falls back to HTTPS for GitHub, so this needs git
  # but no SSH key.
  npm ci
  mark install_done
}

build() {
  mark build_start
  # Upstream's `make build` without its submodule check. Production would turn the blocked fetches into errors.
  "$HUGO_DIR/hugo" --cleanDestinationDir --minify --environment development
  write_version
  mark build_done
}

# /version on the CDN providers (Render static site, Vercel) is this file. BENCH_RUN_ID is a build env var there, so
# each deployment has its own ID. The Caddy image (Railway, Fly) overwrites `run` at start from its runtime env.
# BENCH_COMMIT is the harness override (Fly passes it as a build arg); the others are provider variables.
write_version() {
  commit="${BENCH_COMMIT:-${RENDER_GIT_COMMIT:-${RAILWAY_GIT_COMMIT_SHA:-${VERCEL_GIT_COMMIT_SHA:-}}}}"
  if [ -z "$commit" ]; then
    commit="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
  fi
  printf '{"commit":"%s","run":"%s"}\n' "$commit" "${BENCH_RUN_ID:-unknown}" > public/version.json
  printf 'output: %s files, %s\n' "$(find public -type f | wc -l | tr -d ' ')" "$(du -sh public | cut -f1)"
}

case "${1:-all}" in
  install) install ;;
  build) build ;;
  all) install; build ;;
  *) printf 'Usage: %s {install|build|all}\n' "$0" >&2; exit 2 ;;
esac
