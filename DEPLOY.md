# Deploying FillariStatus

FillariStatus is an R Shiny app, so it needs a server process (GitHub Pages
can only host static files). It runs on Google Cloud Run in the same GCP
project as BiblioStatus (`bibliostatus-app`, region `europe-north1`).

**Live:** https://fillaristatus-app-884476669514.europe-north1.run.app
(Cloud Run service `fillaristatus-app`, project `bibliostatus-app`, region `europe-north1`).
A custom domain can be mapped later (see below).

## Secrets

| Variable | Where it lives | Used for |
|---|---|---|
| `DIGITRANSIT_SUBSCRIPTION_KEY` | Secret Manager `digitransit-subscription-key` | HSL / Digitransit station data. Server-side only, never sent to the browser. |
| `CARTO_API_KEY` | Secret Manager `carto-api-key` (shared with BiblioStatus) | Map tiles. Without it Carto returns a watermarked "API KEY REQUIRED" tile (with HTTP 200). |

Locally both go in a git-ignored `.Renviron` in the project root:

```
DIGITRANSIT_SUBSCRIPTION_KEY=...
CARTO_API_KEY=...
```

Never commit this file. The Docker build excludes it (`.dockerignore` is an
allowlist) and the keys are injected at runtime.

## Run locally

Without Docker:

```r
renv::restore()
shiny::runApp("app/", port = 8083)
```

With Docker (builds the same image Cloud Run uses; the first build downloads
prebuilt R packages and takes several minutes):

```bash
docker compose up --build
# open http://localhost:8083
```

Geolocation only works on `localhost` or HTTPS, so test it on the machine
running the container, or on the deployed HTTPS URL.

## Deploy to Cloud Run

```bash
DRY_RUN=1 ./deploy.sh   # print what would happen, change nothing
./deploy.sh             # asks for confirmation, then builds and deploys
```

The script:

1. checks you are logged in and the project exists
2. enables the Cloud Build, Cloud Run, Artifact Registry and Secret Manager APIs
3. creates the `digitransit-subscription-key` secret from your `.Renviron` if it
   does not exist, and lets the Cloud Run runtime service account read both secrets
4. builds the image with Cloud Build and deploys it with
   `--allow-unauthenticated`, `--session-affinity` (Shiny needs a session to
   stay on one instance), `--max-instances 3` and `--concurrency 20`

R handles one request at a time per instance, which is why concurrency is
modest and instances are capped. Raise `MAX_INSTANCES` / `CONCURRENCY`
through environment variables if traffic needs it.

## Custom domain

```bash
gcloud beta run domain-mappings create \
    --service fillaristatus-app \
    --domain fillaristatus.youcanbeapirate.com \
    --region europe-north1
```

Then add a CNAME record at the DNS provider (`fillaristatus` -> `ghs.googlehosted.com`).
Certificate provisioning takes roughly 15-30 minutes.

## Cost

Cloud Run's free tier (2 million requests, 360,000 GB-seconds and 180,000
vCPU-seconds per month) should cover personal use. The service scales to zero
when idle; the first request after that takes a few seconds (cold start) and
the in-memory station cache starts empty, which is fine because it just
fetches fresh data. The Artifact Registry image and Secret Manager secrets
cost cents per month at most.

## Checking a deploy

- Open the service URL, confirm the list loads and the map shows real tiles
  (not a watermark).
- `gcloud run services logs read fillaristatus-app --region europe-north1 --project bibliostatus-app --limit 50`
- If the page loads but shows "Couldn't load station data", the
  `DIGITRANSIT_SUBSCRIPTION_KEY` secret is missing or wrong.
