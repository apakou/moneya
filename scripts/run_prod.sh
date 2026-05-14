#!/usr/bin/env bash
# Run MoneyA in the **prod** flavor.
#
# Prod is intentionally a thin wrapper: no BYPASS_ONBOARDING (Env
# ignores it in release builds anyway), real prod backend, real
# observability.
#
# Useful for pre-release smoke tests against the production API from
# an internal device with the prod app ID (com.moneya.app).
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://api.moneya.app}"

exec flutter run \
  --flavor prod \
  --dart-define=FLAVOR=prod \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  "$@"
