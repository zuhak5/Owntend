#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${SHOREBIRD_KMS_LOCATION:?SHOREBIRD_KMS_LOCATION is required}"
: "${SHOREBIRD_KMS_KEYRING:?SHOREBIRD_KMS_KEYRING is required}"
: "${SHOREBIRD_KMS_KEY:?SHOREBIRD_KMS_KEY is required}"
: "${SHOREBIRD_KMS_KEY_VERSION:?SHOREBIRD_KMS_KEY_VERSION is required}"

gcloud kms keys versions get-public-key "$SHOREBIRD_KMS_KEY_VERSION" \
  --project="$GCP_PROJECT_ID" \
  --location="$SHOREBIRD_KMS_LOCATION" \
  --keyring="$SHOREBIRD_KMS_KEYRING" \
  --key="$SHOREBIRD_KMS_KEY"
