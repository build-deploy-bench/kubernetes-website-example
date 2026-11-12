# Build-deploy benchmark fixture: static-large (kubernetes/website, Hugo)

## Source

- Upstream: https://github.com/kubernetes/website at `2674d5095a50d781d2f884c83973921f48c5cf28` (2026-11-12). Content CC BY 4.0, kept in `LICENSE`. The site carries the Kubernetes trademarks.
- This repo: https://github.com/build-deploy-bench/kubernetes-website-example (private). The first commit has the unmodified upstream tree (tree `adb3242a`, without upstream history).
- Output: 12,463 files, 3.9 GB, from 13,436 source files (528 MB). Hugo extended 0.144.2 builds 17 languages. About 2,990 HTML files differ between two builds of the same commit (hashed asset names); this is accepted and not patched.
- Static fixture convention: see "Static fixtures" in the harness's `guides/fixtures.md`. The reference is `vuejs-docs-static`.

## Patches

1. Removed the `api-ref-generator` submodule and `.gitmodules`. Only `make api-reference` uses the submodule, and a provider that clones submodules would fetch it on every build.
2. Removed the upstream GitHub Actions workflows (two scheduled jobs).
3. `layouts/robots.txt` disallows all crawlers. The development build already adds `<meta name=robots content="noindex, nofollow">` to every page, and every provider sends `X-Robots-Tag: noindex, nofollow` (Render header rule, `vercel.json`, `Caddyfile`). A deployed copy is a public clone of kubernetes.io, so it must be up only during runs.
4. Replaced upstream's root `Dockerfile` (its Hugo dev container) and `.dockerignore` (which admits only the package files) with the benchmark image, as the static convention requires a root `Dockerfile`. The site build does not use them.
5. Added `bench/build.sh`, `bench/serve.sh`, `Caddyfile`, `fly.toml`, `vercel.json` and the touch file `data/bench_touch.yaml`. The harness replaces the whole touch file, so it is a Hugo data file and not a content page.

Not patched: Docsy is a GitHub dependency, and the lockfile entry is `git+ssh://git@github.com/google/docsy.git#cf0c68f…`. npm 10 falls back to HTTPS for GitHub, so `npm ci` works without an SSH key on every builder that has `git`. This was checked in a clean container and on all four providers.

## Commands

| Step | Command | Markers |
|---|---|---|
| Toolchain (before the marker) | download Hugo extended 0.144.2 and Node 20.17.0 to `.bench/` (checksum-pinned), print versions | |
| Install | `./bench/build.sh install` = `npm ci` | `::bench::install_start` / `::bench::install_done` |
| Build | `./bench/build.sh build` = `hugo --cleanDestinationDir --minify --environment development`, then write `public/version` | `::bench::build_start` / `::bench::build_done` |
| Start (Caddy image only) | `sh /bench/serve.sh` | `::bench::start` / `::bench::listening` |
| Health | `GET /` | |

The build command is upstream's `make build` without its submodule check. `--environment development` is necessary: in production, the blocked remote fetches below are errors.

`bench/build.sh` downloads Node 20.17.0 (upstream's Netlify pin) on every provider and puts it first on `PATH`, so no provider uses its own Node. Vercel no longer offers Node 20, and with its Node 26.13.1 (npm 11.20) `npm ci` installed 81 packages instead of 1,311 and did not run Docsy's postinstall (npm 11 `allowScripts`).

`bench/build.sh` sets the Hugo env, so that it is the same on every provider and is not a provider setting:

- `HUGO_ENABLEGITINFO=false`: Docker contexts have no `.git`.
- `HUGO_SECURITY_HTTP_URLS=^https://none\.invalid/`: blocks the build-time fetches of the CVE feed and `release_binaries.json` (four warnings in each build log).
- `HUGO_MEMORYLIMIT=6`: Hugo 0.144.2 deadlocked twice at 7 GB.

## `/version`

The build writes `public/version` (`{"commit","run"}`, no extension), so every provider serves it at `/version` without a rewrite. `run` is `BENCH_RUN_ID` from the build env on Render (service env var) and Vercel (`--build-env`). In the Caddy image (Railway, Fly), `bench/serve.sh` writes the file again at start, with `run` and `deployment` from the runtime env.

Image: 4.97 GB uncompressed (local arm64 build). The site is one 3.9 GB layer.

## Providers

### Render

- Workspace `tea-dbmbhbg8v5cc73e4m0jg` (Pro). Static site `srv-dbquc9gu01pc7384g7m0` `bdb-kubernetes-website`, https://bdb-kubernetes-website.onrender.com. Build plan `starter` (2 CPU, 8 GB). Static sites have no instance cost. Auto-deploy off.
- Build command `./bench/build.sh all`, publish path `public`. Header rule `/*` `X-Robots-Tag: noindex, nofollow`. Env `SKIP_INSTALL_DEPS=true`, `BENCH_RUN_ID`. Without `SKIP_INSTALL_DEPS`, Render ran its own `npm install` (55 s) before the build command, so the site was installed twice.
- **Keep the site suspended between runs.** The harness does not suspend static sites, so suspend it by hand after each matrix (`POST /v1/services/<id>/suspend`). A suspended static site returns 503. The harness resumes it before a suite, which starts a full build (about 5 min).
- Setup deploys: `dep-dbquc9ou01pc7384g890`, `dep-dbqufjei0phs738ka0i0`. The 3.9 GB upload and publish took 80 to 95 s.

### Railway

- Workspace `d535606c-49a7-4a6c-9e29-ce73b5f01428`. Project `bdb-kubernetes-website` `0a656f75-e498-4cd6-8b40-2ed226f1e1fa`, environment `production` `138395cb-4b82-4d99-80c9-5664b57ebd31`, service `a8cc6b2e-dad3-4c26-a25d-2ef7e338e790`, https://bdb-kubernetes-website-production.up.railway.app
- Source `build-deploy-bench/kubernetes-website-example` `main`, root `Dockerfile`. Health check `/version`. Default region. Auto-deploy disabled after `railway add --repo` and confirmed with `serviceInstanceAutoDeployStatus`.
- Setup deploy `9306dc0d-c5f0-4d76-938d-ef116e5ba719`. The deployment is removed between runs.
- In the matrix runs, the deploy logs had only `Starting Container`, without the `::bench::start` and `::bench::listening` lines (also when fetched again later), so `app_boot` is empty. The setup deploy had them.

### Vercel

- Team `build-deploy-bench`. Project `bdb-kubernetes-website` `prj_mxXf7Nl4ikOWmv3kboLGtjHXhh7d`, https://bdb-kubernetes-website.vercel.app. No Git link; the harness uploads a `git archive` (13,441 files with `.vercel/`, under the 15,000-file CLI cap).
- Framework none. Build machine `standard` (4 CPU, 8 GB), selection `fixed` (the default was `elastic`). Project Node setting `26.x` (20.x is rejected as discontinued); `bench/build.sh` uses its own Node 20.17.0.
- **The Vercel output has 11 fewer files (12,452).** The Vercel CLI leaves every `node_modules` path out of the upload, and upstream commits 11 assets of the generated kubectl reference under `static/docs/reference/generated/kubectl/node_modules/` (CSS, fonts, jQuery). That page has no styles on Vercel. A Git-source deploy would include them, but the account has no GitHub connection. Not patched.
- `Deploying outputs` for 3.9 GB took 14 to 16 s.
- **Delete the deployments after a matrix** (`DELETE /v13/deployments/<id>`); there is no pause. This also drops the build cache, so the first run of the next matrix is cold.

### Fly.io

- Org `personal`. App `bdb-kubernetes-website`, https://bdb-kubernetes-website.fly.dev. One Machine, `iad`, shared-cpu-1x 256 MB.
- Deploy: `flyctl deploy --remote-only --depot=false` from a `git archive`, so every Fly run uploads the 538 MB build context from the runner (275 s from the setup Mac).
