# syntax=docker/dockerfile:1
# npm/vite run on BUILDPLATFORM (native Podman VM CPU). Only nginx + static dist use TARGETPLATFORM (e.g. linux/amd64).
# Avoids multi-hour QEMU hangs from npm ci under emulated amd64 on Apple Silicon.

FROM --platform=$BUILDPLATFORM node:22-alpine AS builder
WORKDIR /app
ENV CI=true \
    NPM_CONFIG_FETCH_TIMEOUT=120000 \
    NPM_CONFIG_FETCH_RETRIES=3 \
    NPM_CONFIG_PROGRESS=false \
    NODE_OPTIONS=--dns-result-order=ipv4first

COPY front-end/package.json front-end/package-lock.json ./
RUN npm ci --no-audit --no-fund

COPY front-end/ .
RUN npm run build

FROM --platform=$TARGETPLATFORM nginx:1.27-alpine
COPY front-end/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist /usr/share/nginx/html
EXPOSE 8505
