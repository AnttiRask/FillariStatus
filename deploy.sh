#!/bin/bash
# Deploy FillariStatus to Google Cloud Run.
# Uses the same GCP project as BiblioStatus. Nothing is created or changed
# until you confirm at the prompt. Run with DRY_RUN=1 to only print the plan.

set -euo pipefail

# ---- Configuration (override via env vars) ----------------------------------
PROJECT_ID="${GCP_PROJECT:-bibliostatus-app}"
REGION="${GCP_REGION:-europe-north1}"
SERVICE_NAME="${GCP_SERVICE_NAME:-fillaristatus-app}"
AR_REPO="${GCP_AR_REPO:-cloud-run-source-deploy}"
IMAGE="$REGION-docker.pkg.dev/$PROJECT_ID/$AR_REPO/$SERVICE_NAME"

# Secret Manager secret name
DIGITRANSIT_SECRET="${DIGITRANSIT_SECRET:-digitransit-subscription-key}"

# Cost/behaviour guards. R Shiny serves requests on one thread per instance,
# so keep concurrency modest and cap the instance count.
MAX_INSTANCES="${MAX_INSTANCES:-3}"
CONCURRENCY="${CONCURRENCY:-20}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

run() {
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "${YELLOW}[dry run]${NC} $*"
  else
    "$@"
  fi
}

echo -e "${GREEN}=== FillariStatus Deployment ===${NC}"
echo -e "${YELLOW}Project:${NC}  ${PROJECT_ID}"
echo -e "${YELLOW}Region:${NC}   ${REGION}"
echo -e "${YELLOW}Service:${NC}  ${SERVICE_NAME}  (max ${MAX_INSTANCES} instances, concurrency ${CONCURRENCY})"
echo -e "${YELLOW}Image:${NC}    ${IMAGE}"
echo -e "${YELLOW}Secret:${NC}   ${DIGITRANSIT_SECRET} (created from .Renviron if missing)"
echo ""

# ---- Preconditions ----------------------------------------------------------
command -v gcloud &>/dev/null || { echo -e "${RED}Error: gcloud CLI is not installed${NC}"; exit 1; }

ACTIVE_ACCT="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' || true)"
[[ -n "${ACTIVE_ACCT}" ]] || { echo -e "${RED}No active gcloud login. Run: gcloud auth login${NC}"; exit 1; }
echo -e "${YELLOW}Using account:${NC} ${ACTIVE_ACCT}"

gcloud projects describe "$PROJECT_ID" &>/dev/null \
  || { echo -e "${RED}Project ${PROJECT_ID} not found or not accessible${NC}"; exit 1; }

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  read -r -p "Build and deploy ${SERVICE_NAME} to ${PROJECT_ID}? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || { echo "Aborted."; exit 1; }
fi

# ---- APIs (idempotent) ------------------------------------------------------
echo -e "${YELLOW}Enabling required APIs...${NC}"
run gcloud services enable \
  cloudbuild.googleapis.com run.googleapis.com \
  artifactregistry.googleapis.com secretmanager.googleapis.com \
  --project "$PROJECT_ID"

# ---- Secrets ----------------------------------------------------------------
if ! gcloud secrets describe "$DIGITRANSIT_SECRET" --project "$PROJECT_ID" &>/dev/null; then
  echo -e "${YELLOW}Creating secret ${DIGITRANSIT_SECRET} from DIGITRANSIT_SUBSCRIPTION_KEY in .Renviron...${NC}"
  KEY="$(sed -n 's/^DIGITRANSIT_SUBSCRIPTION_KEY=//p' .Renviron | head -1)"
  [[ -n "$KEY" ]] || { echo -e "${RED}DIGITRANSIT_SUBSCRIPTION_KEY not found in .Renviron${NC}"; exit 1; }
  if [[ "${DRY_RUN:-0}" == "1" ]]; then
    echo -e "${YELLOW}[dry run]${NC} gcloud secrets create ${DIGITRANSIT_SECRET} (value from .Renviron)"
  else
    printf '%s' "$KEY" | gcloud secrets create "$DIGITRANSIT_SECRET" \
      --data-file=- --replication-policy=automatic --project "$PROJECT_ID"
  fi
fi

# The Cloud Run runtime service account must be able to read the secret
PROJECT_NUMBER="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')"
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"
run gcloud secrets add-iam-policy-binding "$DIGITRANSIT_SECRET" \
  --member "serviceAccount:${RUNTIME_SA}" \
  --role roles/secretmanager.secretAccessor \
  --project "$PROJECT_ID" --quiet

# ---- Build ------------------------------------------------------------------
echo -e "${GREEN}Building container image with Cloud Build...${NC}"
run gcloud builds submit \
  --tag "$IMAGE" \
  --region "$REGION" \
  --timeout 3600 \
  --project "$PROJECT_ID"

# ---- Deploy -----------------------------------------------------------------
echo -e "${GREEN}Deploying to Cloud Run...${NC}"
# --set-secrets replaces all existing secrets, which also drops the map-tile key
# that earlier revisions used
run gcloud run deploy "$SERVICE_NAME" \
  --image "$IMAGE" \
  --platform managed \
  --region "$REGION" \
  --allow-unauthenticated \
  --memory 1Gi \
  --timeout 3600 \
  --session-affinity \
  --max-instances "$MAX_INSTANCES" \
  --concurrency "$CONCURRENCY" \
  --set-secrets "DIGITRANSIT_SUBSCRIPTION_KEY=${DIGITRANSIT_SECRET}:latest" \
  --project "$PROJECT_ID"

if [[ "${DRY_RUN:-0}" != "1" ]]; then
  SERVICE_URL="$(gcloud run services describe "$SERVICE_NAME" \
    --region "$REGION" --format='value(status.url)' --project "$PROJECT_ID")"
  echo ""
  echo -e "${GREEN}=== Deployment Complete ===${NC}"
  echo -e "Your app is live at: ${GREEN}${SERVICE_URL}${NC}"
fi
