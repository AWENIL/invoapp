#!/usr/bin/env bash
set -euo pipefail

export PATH="$PWD/.flutter-sdk/bin:$PATH"
export API_BASE_URL="${API_BASE_URL:-https://api.invotaxi.ukudarov.pro}"

flutter config --enable-web
flutter pub get
flutter build web --release --base-href=/ \
  --dart-define=API_BASE_URL="$API_BASE_URL" \
  --dart-define=YANDEX_MAPS_API_KEY="${YANDEX_MAPS_API_KEY:-}" \
  --dart-define=YANDEX_MAPS_SUGGEST_API_KEY="${YANDEX_MAPS_SUGGEST_API_KEY:-}" \
  --dart-define=TERMS_URL="${TERMS_URL:-}" \
  --dart-define=PRIVACY_URL="${PRIVACY_URL:-}" \
  --dart-define=DISPATCH_PHONE_TEL="${DISPATCH_PHONE_TEL:-}"
