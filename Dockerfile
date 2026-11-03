# Builds the web app and serves it with Caddy (Railway sets $PORT).
FROM debian:bookworm-slim AS build
RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch 3.47.9 https://github.com/flutter/flutter.git /flutter
ENV PATH="/flutter/bin:$PATH"
RUN flutter config --no-analytics --enable-web && flutter precache --web
WORKDIR /app
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY . .
RUN flutter build web --release --wasm --no-web-resources-cdn

FROM caddy:2.11.4-alpine
COPY Caddyfile /etc/caddy/Caddyfile
COPY --from=build /app/build/web /srv
