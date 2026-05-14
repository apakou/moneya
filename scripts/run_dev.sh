#!/usr/bin/env bash
# Run MoneyA in the **dev** flavor.
#
# Wraps `flutter run` with the dart-defines that Env (lib/core/config/env.dart)
# expects. Edit the API_BASE_URL fallback or pass extra flags after `--`:
#
#   ./scripts/run_dev.sh                                  # default
#   ./scripts/run_dev.sh --device-id=emulator-5554        # forwarded to flutter
#   ./scripts/run_dev.sh -- --release                     # release-mode dev
#
# BYPASS_ONBOARDING is allowed in dev so engineers can iterate on
# post-onboarding screens without re-walking auth on every hot restart.
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://api.dev.moneya.app}"
BYPASS_ONBOARDING="${BYPASS_ONBOARDING:-true}"

exec flutter run \
  --flavor dev \
  --dart-define=FLAVOR=dev \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=BYPASS_ONBOARDING="${BYPASS_ONBOARDING}" \
  "$@"
