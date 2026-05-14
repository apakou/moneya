#!/usr/bin/env bash
# Run MoneyA in the **staging** flavor.
#
# Staging points at the QA backend and behaves like prod for every
# user-visible toggle: BYPASS_ONBOARDING is off (Env still gates it
# behind kDebugMode regardless), real auth + KYC flow, real analytics
# pipe once the keys are wired.
set -euo pipefail

API_BASE_URL="${API_BASE_URL:-https://api.staging.moneya.app}"

exec flutter run \
  --flavor staging \
  --dart-define=FLAVOR=staging \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --dart-define=BYPASS_ONBOARDING=false \
  "$@"
