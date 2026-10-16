#!/usr/bin/env bash
# redact-output.sh: Sanitise logs, configs, and command outputs for privacy and secret prevention.
set -euo pipefail

sed -E \
  -e 's/token: .*/token: [REDACTED_TOKEN]/g' \
  -e 's/--token=[^ ]+/--token=[REDACTED_TOKEN]/g' \
  -e 's/K3S_TOKEN=[^ ]+/K3S_TOKEN=[REDACTED_TOKEN]/g' \
  -e 's/password: .*/password: [REDACTED_PASSWORD]/g' \
  -e 's/client-key-data: .*/client-key-data: [REDACTED_KEY_DATA]/g' \
  -e 's/client-certificate-data: .*/client-certificate-data: [REDACTED_CERT_DATA]/g' \
  -e 's/certificate-authority-data: .*/certificate-authority-data: [REDACTED_CA_DATA]/g' \
  -e 's/-----BEGIN [A-Z0-9 ]+ PRIVATE KEY-----.*-----END [A-Z0-9 ]+ PRIVATE KEY-----/[REDACTED_PRIVATE_KEY]/g' \
  -e 's/K3S_CLUSTER_SECRET=[^ ]+/K3S_CLUSTER_SECRET=[REDACTED_SECRET]/g' \
  -e 's/(echo\s+[\x27\x22]?)[^\s|]+([\x27\x22]?\s*\|\s*sudo)/\1[REDACTED]\2/g' \
  "$@"

