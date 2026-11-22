#!/usr/bin/env bash
# One-time setup for .github/workflows/deploy.yml.
#
# Lets GitHub Actions deploy this project without stored keys: creates a
# Workload Identity Federation pool and provider that trust only this
# repository's "production" environment, a service account they may
# impersonate, and the roles it needs. Then stores the settings in the
# repository's "production" environment.
#
# Requires gcloud and gh, both signed in. Safe to re-run.
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

REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
ENVIRONMENT=production
# The subject GitHub puts in this repository's OIDC tokens. Ask GitHub for its
# prefix rather than assume repo:<owner>/<repo>: repositories can use the
# immutable form repo:<owner>@<owner-id>/<repo>@<repo-id>.
IFS=$'\t' read -r USE_DEFAULT_SUBJECT SUBJECT_PREFIX < <(
  gh api "repos/$REPO/actions/oidc/customization/sub" \
    --jq '[.use_default, (.sub_claim_prefix // "")] | @tsv')
if [[ "$USE_DEFAULT_SUBJECT" != "true" ]]; then
  echo "$REPO uses a customized OIDC subject claim, which this script does not support." >&2
  exit 1
fi
SUBJECT="${SUBJECT_PREFIX:-repo:$REPO}:environment:$ENVIRONMENT"

POOL=github
PROVIDER=github
SERVICE_ACCOUNT_NAME=github-deploy
SERVICE_ACCOUNT="$SERVICE_ACCOUNT_NAME@$PROJECT_ID.iam.gserviceaccount.com"
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
POOL_PATH="projects/$PROJECT_NUMBER/locations/global/workloadIdentityPools/$POOL"

echo "Enabling the IAM and token exchange APIs..."
gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  --project "$PROJECT_ID"

echo "Creating the workload identity pool and provider..."
if ! gcloud iam workload-identity-pools describe "$POOL" \
  --project "$PROJECT_ID" --location global > /dev/null 2>&1; then
  gcloud iam workload-identity-pools create "$POOL" \
    --project "$PROJECT_ID" --location global --display-name "GitHub Actions"
fi
if ! gcloud iam workload-identity-pools providers describe "$PROVIDER" \
  --project "$PROJECT_ID" --location global --workload-identity-pool "$POOL" > /dev/null 2>&1; then
  gcloud iam workload-identity-pools providers create-oidc "$PROVIDER" \
    --project "$PROJECT_ID" --location global --workload-identity-pool "$POOL" \
    --display-name "GitHub Actions" \
    --issuer-uri "https://token.actions.githubusercontent.com" \
    --attribute-mapping "google.subject=assertion.sub,attribute.repository=assertion.repository" \
    --attribute-condition "assertion.sub == '$SUBJECT'"
else
  gcloud iam workload-identity-pools providers update-oidc "$PROVIDER" \
    --project "$PROJECT_ID" --location global --workload-identity-pool "$POOL" \
    --attribute-condition "assertion.sub == '$SUBJECT'"
fi

echo "Creating the deployment service account..."
if ! gcloud iam service-accounts describe "$SERVICE_ACCOUNT" \
  --project "$PROJECT_ID" > /dev/null 2>&1; then
  gcloud iam service-accounts create "$SERVICE_ACCOUNT_NAME" \
    --project "$PROJECT_ID" --display-name "GitHub Actions deployment"
fi

echo "Granting the service account the roles deploy.sh needs..."
# Terraform enables the APIs and manages the Firestore database and rules;
# the Firebase CLI publishes Hosting.
for role in roles/serviceusage.serviceUsageAdmin roles/datastore.owner roles/firebase.admin; do
  gcloud projects add-iam-policy-binding "$PROJECT_ID" \
    --member "serviceAccount:$SERVICE_ACCOUNT" --role "$role" \
    --condition None --quiet > /dev/null
done

echo "Letting $SUBJECT impersonate the service account..."
gcloud iam service-accounts add-iam-policy-binding "$SERVICE_ACCOUNT" \
  --project "$PROJECT_ID" --role roles/iam.workloadIdentityUser \
  --member "principal://iam.googleapis.com/$POOL_PATH/subject/$SUBJECT" > /dev/null

echo "Storing the settings in the $REPO \"$ENVIRONMENT\" environment..."
gh api --method PUT "repos/$REPO/environments/$ENVIRONMENT" --silent
gh variable set GCP_WORKLOAD_IDENTITY_PROVIDER --repo "$REPO" --env "$ENVIRONMENT" \
  --body "$POOL_PATH/providers/$PROVIDER"
gh variable set GCP_SERVICE_ACCOUNT --repo "$REPO" --env "$ENVIRONMENT" --body "$SERVICE_ACCOUNT"
gh variable set PROJECT_ID --repo "$REPO" --env "$ENVIRONMENT" --body "$PROJECT_ID"
gh variable set LOCATION --repo "$REPO" --env "$ENVIRONMENT" --body "$LOCATION"

echo "Done. Pushing a version tag (git tag vX.Y.Z && git push origin vX.Y.Z) now deploys."
