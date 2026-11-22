#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

ENV_FILE=".env"
if [[ -f "$ENV_FILE" ]]; then
  set -a
  # shellcheck source=/dev/null
  source "$ENV_FILE"
  set +a
fi

LOCATION="${LOCATION:-us-central1}"

if [[ -z "${PROJECT_ID:-}" ]]; then
  echo "PROJECT_ID must be set (in .env or the environment)." >&2
  exit 1
fi

for tool in terraform gcloud; do
  if ! command -v "$tool" > /dev/null; then
    echo "$tool is not installed; see README \"Prerequisites\"." >&2
    exit 1
  fi
done

if ! gcloud auth application-default print-access-token > /dev/null 2>&1; then
  echo "No Application Default Credentials for Terraform. Run:" >&2
  echo "  gcloud auth application-default login" >&2
  exit 1
fi

export TF_VAR_project_id="$PROJECT_ID"
export TF_VAR_location="$LOCATION"

echo "Initialising Terraform..."
terraform init -input=false

# Adopt resources that already exist (for example a database created in the
# Firebase console) instead of failing to create them. Import fails harmlessly
# when the resource does not exist yet; Terraform then creates it.
adopt() {
  local address="$1" id="$2"
  if [[ -z "$(terraform state list "$address")" ]]; then
    terraform import -input=false "$address" "$id" > /dev/null 2>&1 &&
      echo "Adopted existing $address." || true
  fi
}
adopt google_firestore_database.default "projects/$PROJECT_ID/databases/(default)"
adopt google_firebaserules_release.firestore "projects/$PROJECT_ID/releases/cloud.firestore"

echo "Provisioning infrastructure..."
if [[ "${AUTO_APPROVE:-}" == "1" ]]; then
  terraform apply -input=false -auto-approve
else
  terraform apply -input=false
fi

echo "Installing the Firebase CLI..."
npm ci

echo "Writing build version..."
BUILD_VERSION=$(git describe --tags --always --dirty 2>/dev/null || echo "unversioned")
BUILD_TIME=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '{\n  "version": "%s",\n  "builtAt": "%s"\n}\n' "$BUILD_VERSION" "$BUILD_TIME" > public/version.json
echo "Build version: $BUILD_VERSION ($BUILD_TIME)"

echo "Deploying the frontend..."
npx --no-install firebase --project "$PROJECT_ID" --non-interactive deploy --only hosting

echo "Deployment finished: https://$PROJECT_ID.web.app"
echo "The first visit creates the demo collection and three sample documents."
