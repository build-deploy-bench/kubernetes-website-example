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
NODE_VERSION=20.17.0
NODE_DIR="$PWD/.bench/node-v$NODE_VERSION"
# Upstream's Netlify build pins Node 20.17.0. Vercel no longer offers Node 20, and with Node 26 (npm 11) the install
# resolves other packages and skips Docsy's postinstall, so the output changes. Every provider therefore uses this
# download, whatever Node its build image has.
export PATH="$NODE_DIR/bin:$PATH"

# Hugo settings, the same on every provider. They are set here and not in each provider's settings, so they cannot
# drift apart.
# - Git info off: Docker contexts have no .git, and Render's clone does. Upstream's Netlify build has it on.
# - Remote fetches off: the CVE feed and release_binaries.json are fetched at build time upstream; a blocked fetch is
#   a warning in the development environment. A fetch would make the build depend on two third-party endpoints.
# - Memory limit 6 GB: Hugo 0.144.2 deadlocked twice with its default limit on a large machine.
export HUGO_ENABLEGITINFO=false
export HUGO_SECURITY_HTTP_URLS='^https://none\.invalid/'
export HUGO_MEMORYLIMIT=6

# Download a release archive to `dir`, check it against `sum`, and unpack it there. An existing `dir` is kept, so a
# provider that restores `.bench/` from its build cache skips the download.
fetch() { # url sum dir tar-args...
  url="$1" sum="$2" dir="$3"
  shift 3
  [ -d "$dir" ] && return
  mkdir -p "$dir.partial"
  curl -fsSL -o "$dir.partial/archive" "$url"
  printf '%s  %s\n' "$sum" "$dir.partial/archive" | sha256sum -c -
  tar -xzf "$dir.partial/archive" -C "$dir.partial" "$@"
  rm "$dir.partial/archive"
  mv "$dir.partial" "$dir"
}

# Hugo extended and Node are not on every provider's build image in these versions, so every provider downloads the
# same releases. The checksums pin the archives.
install_tools() {
  case "$(uname -m)" in
    x86_64 | amd64)
      fetch "https://github.com/gohugoio/hugo/releases/download/v$HUGO_VERSION/hugo_extended_${HUGO_VERSION}_linux-amd64.tar.gz" \
        961b258ba2478bec4b2756be4f8982b221bf2d6c1b20f0727ad86e84677053d9 "$HUGO_DIR" hugo
      fetch "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-x64.tar.gz" \
        21e656f6f4e34080ddc5d75fbfe58ce8482fe6e70a76aeae14afdcdc1e23079d "$NODE_DIR" --strip-components=1 ;;
    aarch64 | arm64)
      fetch "https://github.com/gohugoio/hugo/releases/download/v$HUGO_VERSION/hugo_extended_${HUGO_VERSION}_linux-arm64.tar.gz" \
        5d0756c3e72a7386f3a3fcd432789c39c3d1239715e147c63bd7a73bbfcfc93f "$HUGO_DIR" hugo
      fetch "https://nodejs.org/dist/v$NODE_VERSION/node-v$NODE_VERSION-linux-arm64.tar.gz" \
        18afbf2781edfcc9918343f4bf74a8c35d74d778b85d40a0c09b232adc0ea82c "$NODE_DIR" --strip-components=1 ;;
    *) printf 'Unsupported architecture: %s\n' "$(uname -m)" >&2; exit 1 ;;
  esac
}

install() {
  # Toolchain setup before the marker, as on the other fixtures: Render installs Node on the first `node` call, and the
  # other providers set up their toolchain before the install step.
  rm -rf .bench/*.partial
  install_tools
  "$HUGO_DIR/hugo" version
  printf 'node %s, npm %s\n' "$(node --version)" "$(npm --version)"
  mark install_start
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

# A CDN cannot answer from runtime env, so the build writes the deployment identity as `public/version` (no
# extension, so every provider serves it at /version without a rewrite). BENCH_RUN_ID reaches the build on Render
# (service env) and Vercel (--build-env). In the container (Railway, Fly), bench/serve.sh writes it again.
# BENCH_COMMIT is the harness override (Fly passes it as a build arg); the others are provider variables.
write_version() {
  commit="${BENCH_COMMIT:-${RENDER_GIT_COMMIT:-${RAILWAY_GIT_COMMIT_SHA:-${VERCEL_GIT_COMMIT_SHA:-}}}}"
  if [ -z "$commit" ]; then
    commit="$(git rev-parse HEAD 2>/dev/null || printf 'unknown')"
  fi
  printf '{"commit":"%s","run":"%s"}\n' "$commit" "${BENCH_RUN_ID:-unknown}" > public/version
  printf 'output: %s files, %s\n' "$(find public -type f | wc -l | tr -d ' ')" "$(du -sh public | cut -f1)"
}

case "${1:-all}" in
  install) install ;;
  build) build ;;
  all) install; build ;;
  *) printf 'Usage: %s {install|build|all}\n' "$0" >&2; exit 2 ;;
esac
