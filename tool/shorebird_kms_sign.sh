#!/usr/bin/env bash
set -euo pipefail

: "${GCP_PROJECT_ID:?GCP_PROJECT_ID is required}"
: "${SHOREBIRD_KMS_LOCATION:?SHOREBIRD_KMS_LOCATION is required}"
: "${SHOREBIRD_KMS_KEYRING:?SHOREBIRD_KMS_KEYRING is required}"
: "${SHOREBIRD_KMS_KEY:?SHOREBIRD_KMS_KEY is required}"
: "${SHOREBIRD_KMS_KEY_VERSION:?SHOREBIRD_KMS_KEY_VERSION is required}"

work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT

input_file="$work_dir/input"
signature_file="$work_dir/signature"
cat >"$input_file"

# gcloud for Windows treats "-" as a literal filename instead of stdin/stdout.
# Git Bash supplies cygpath, so pass native paths while keeping the temporary
# files private to this process and deleting them on every exit path.
gcloud_input_file="$input_file"
gcloud_signature_file="$signature_file"
if command -v cygpath >/dev/null 2>&1; then
  gcloud_input_file="$(cygpath -w "$input_file")"
  gcloud_signature_file="$(cygpath -w "$signature_file")"
fi

gcloud kms asymmetric-sign \
  --project="$GCP_PROJECT_ID" \
  --location="$SHOREBIRD_KMS_LOCATION" \
  --keyring="$SHOREBIRD_KMS_KEYRING" \
  --key="$SHOREBIRD_KMS_KEY" \
  --version="$SHOREBIRD_KMS_KEY_VERSION" \
  --digest-algorithm=sha256 \
  --input-file="$gcloud_input_file" \
  --signature-file="$gcloud_signature_file" \
  >/dev/null

base64 <"$signature_file" | tr -d '\r\n'
