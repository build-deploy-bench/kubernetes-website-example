# Image for the container providers (Railway, Fly). Render and Vercel build the site natively and serve it from
# their CDNs, so they do not use this file.
# Node is the version in .node-version. bench/build.sh downloads Hugo, as on Render and Vercel.
# Upstream's Dockerfile (its Hugo dev container) is replaced by this file.
FROM node:26.13.1-bookworm AS build
WORKDIR /app
# Only the install inputs, so a source change keeps the install layer.
COPY package.json package-lock.json .npmrc ./
COPY bench/build.sh bench/build.sh
RUN sh ./bench/build.sh install
COPY . .
# Declared after the install, so a new commit does not invalidate the install layer.
ARG BENCH_COMMIT
ARG RAILWAY_GIT_COMMIT_SHA
RUN sh ./bench/build.sh build

FROM caddy:2.11.9-alpine
# BusyBox `date` has no %N; the runtime markers need milliseconds.
RUN apk add --no-cache coreutils
COPY Caddyfile /etc/caddy/Caddyfile
COPY bench/serve.sh /bench/serve.sh
COPY --from=build /app/public /srv
ENV PORT=80
CMD ["sh", "/bench/serve.sh"]
