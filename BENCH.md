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
5. Moved the 11 assets of the generated kubectl reference from `static/docs/reference/generated/kubectl/node_modules/` to `…/kubectl/vendor/`, and changed the five relative references in `kubectl-commands.html`. Deploy tools leave `node_modules` paths out of an upload (the Vercel CLI dropped all 11, so that page had no CSS, fonts or scripts). The contributor docs that list the generator's output paths are unchanged.
6. `.npmrc` sets `omit=optional`, `package.json` has `engines.node: "26.x"` and an `allowScripts` entry for Docsy, `.node-version` is `26.13.1`, and the lockfile is regenerated with npm 11.20.0. See "Node and npm" below.
7. Added `bench/build.sh`, `bench/serve.sh`, `Caddyfile`, `fly.toml`, `vercel.json` and the touch file `data/bench_touch.yaml`. The harness replaces the whole touch file, so it is a Hugo data file and not a content page.

## Commands

| Step | Command | Markers |
|---|---|---|
| Toolchain (before the marker) | download Hugo extended 0.144.2 to `.bench/` (checksum-pinned), print the Hugo, Node and npm versions | |
| Install | `./bench/build.sh install` = `npm ci` | `::bench::install_start` / `::bench::install_done` |
| Build | `./bench/build.sh build` = `hugo --cleanDestinationDir --minify --environment development`, then write `public/version` | `::bench::build_start` / `::bench::build_done` |
| Start (Caddy image only) | `sh /bench/serve.sh` | `::bench::start` / `::bench::listening` |
| Health | `GET /` | |

The build command is upstream's `make build` without its submodule check. `--environment development` is necessary: in production, the blocked remote fetches below are errors.

### Node and npm

Every provider supplies Node 26.13.1 (the current LTS) with npm 11.20.0 itself: Render from `.node-version`, Vercel from `engines.node` (`26.x`; Vercel picks the patch, 26.13.1 on 2026-11-12), Railway and Fly from the `node:26.13.1-bookworm` image tag. Vercel no longer offers Node 20, which upstream's Netlify build pins.

On Node 26 the unchanged upstream install resolved 81 packages instead of 1,311. Cause: Docsy's `optionalDependencies` are `netlify-cli` and `npm-check-updates`, tools for Docsy's own repo. The lockfile has them as dev+optional. `netlify-cli` 17.38.1 fails its postinstall on Node 26 (exit code 1), so npm removes it with its 1,230 dependencies, after it has downloaded them and run their install scripts. On Node 20 it installs. The site build uses neither tool. Fix: `.npmrc` `omit=optional`, so npm 10 on Node 20 and npm 11 on Node 26 both install the same 80 packages. Docsy's own postinstall (`mkdirp` of two placeholder dirs) runs on both; npm 11 only warned that it is not in `allowScripts`, and `npm install-scripts approve docsy` added the entry. The `git+ssh` lockfile entry was not a problem: npm falls back to HTTPS for GitHub, so `npm ci` needs `git` but no SSH key.

### Hugo

`bench/build.sh` downloads Hugo extended 0.144.2 from the GitHub release on every provider, before `install_start`. Hugo's own guides for Render and Vercel do the same (a build script with a pinned `HUGO_VERSION`), and no provider has Hugo on its build image. Vercel's Hugo framework preset is not used, so that all four providers run the same binary. The `hugo-extended` npm package is the other common way for Docsy sites, but upstream does not use it.

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
- Hugo's `--cleanDestinationDir` keeps paths that match `ignoreFiles` (`^node_modules$`), and Render restores `public/` from its build cache. After patch 5, the first build with the cache still had the 11 old files (12,474); a build with a cleared cache had 12,463.
- **The site is suspended between runs.** The fixture is `private` in the harness `FIXTURES`, so the pause suspends this static site (503) and checks that it no longer answers. The harness resumes it before a suite, which starts a full build (about 5 min).
- Setup deploys: `dep-dbquc9ou01pc7384g890`, `dep-dbqufjei0phs738ka0i0`. The 3.9 GB upload and publish took 80 to 95 s.

### Railway

- Workspace `d535606c-49a7-4a6c-9e29-ce73b5f01428`. Project `bdb-kubernetes-website` `0a656f75-e498-4cd6-8b40-2ed226f1e1fa`, environment `production` `138395cb-4b82-4d99-80c9-5664b57ebd31`, service `a8cc6b2e-dad3-4c26-a25d-2ef7e338e790`, https://bdb-kubernetes-website-production.up.railway.app
- Source `build-deploy-bench/kubernetes-website-example` `main`, root `Dockerfile`. Health check `/version`. Default region. Auto-deploy disabled after `railway add --repo` and confirmed with `serviceInstanceAutoDeployStatus`.
- Setup deploy `9306dc0d-c5f0-4d76-938d-ef116e5ba719`. The deployment is removed between runs.
- In the matrix runs, the deploy logs had only `Starting Container`, without the `::bench::start` and `::bench::listening` lines (also when fetched again later), so `app_boot` is empty. The setup deploy had them.

### Vercel

- Team `build-deploy-bench`. Project `bdb-kubernetes-website` `prj_mxXf7Nl4ikOWmv3kboLGtjHXhh7d`, https://bdb-kubernetes-website.vercel.app. No Git link; the harness uploads a `git archive` (13,441 files with `.vercel/`, under the 15,000-file CLI cap).
- Framework none. Build machine `standard` (4 CPU, 8 GB), selection `fixed` (the default was `elastic`). Project Node setting `26.x`; `engines.node` takes precedence.
- The Vercel CLI leaves every `node_modules` path out of the upload. Before patch 5, the Vercel output had 11 fewer files (12,452).
- `Deploying outputs` for 3.9 GB took 14 to 16 s.
- **The deployments are deleted after a matrix.** Vercel has no pause, so the harness pause deletes every deployment of the project (the fixture is `private`). This also drops the build cache, so a suite must start with its cold run; the harness warns if it starts with a warm one.

### Fly.io

- Org `personal`. App `bdb-kubernetes-website`, https://bdb-kubernetes-website.fly.dev. One Machine, `iad`, shared-cpu-1x with 1 GB (the `fly launch` default). Image 4.1 GB.
- Deploy: `flyctl deploy --remote-only --depot=false` from a `git archive`. The runner uploads the 528 MB build context to the builder on every deploy, at about 1.4 to 2 MB/s from the setup Mac (275 s at setup, 382 s in the warm run), and this is inside Fly's `build_total`. The cold run sent only 1.26 MB, because it deployed the same commit as the setup deploy just before it.
- Setup deploys of `75bf859` and `f3be3a0`, under the Fly build lock. On the shared builder (shared-cpu-8x, 8 GB), Hugo took 632 to 655 s, against 62 s on Railway and 127 s on Vercel. Without the lock, `npm ci` took 18 min and the deploy did not finish.
- **The app is unreachable between runs.** The harness pause turns off autostart on the stopped Machine, so a request cannot start it again; the next deploy turns it on from `fly.toml`. The IPs stay allocated (they were released by hand once and allocated again on 2026-11-12).

## Matrix runs (one cold and one warm run per provider)

`2026-11-12-static-large-v2` is the current fixture (`f3be3a0`, Node 26.13.1 from each provider, 80 packages). `2026-11-12-static-large` was before patches 5 and 6 (Node 20.17.0 downloaded in `bench/build.sh` during `setup`, 1,311 packages). Times in seconds, old → new.

| Provider | Run | setup | install | build | build_total | e2e |
|---|---|---|---|---|---|---|
| Render | cold | 5.1 → 3.9 | 51 → 44 | 146 → 145 | 302 → 288 | 328 → 318 |
| Render | warm | 4.5 → 4.2 | 54 → 37 | 151 → 151 | 301 → 279 | 325 → 304 |
| Railway | cold | 3.7 → 8.9 (toolchain) | 30 → 26 | 57 → 59 | 132 → 139 | 188 → 204 |
| Railway | warm | 4.1 → 17.2 (toolchain) | 33 → 72 | 59 → 124 | 159 → 377 | 210 → 426 |
| Vercel | cold | 4.3 → 2.4 | 41 → 32 | 126 → 85 | 240 → 177 | 249 → 185 |
| Vercel | warm | 4.2 → 2.6 | 44 → 34 | 128 → 122 | 245 → 225 | 253 → 233 |

On Render, `setup` now includes Render's own Node install (about 2 s). The new Railway warm run was slow in every step (install, Hugo and image push), with the same inputs as the cold run; it was not repeated. Railway's install layer was rebuilt on both warm runs. The Fly matrix was not run again. The Fly setup deploy of `f3be3a0` built Hugo in 128 s (632 to 655 s before, on the same builder).

Raw runs: `build-deploy-bench-runs/2026-11-12-static-large{,-v2}/`.
