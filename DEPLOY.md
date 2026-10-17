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

## Automatic deploys (GitHub Actions)

`.github/workflows/deploy_shiny_app.yml` builds with Cloud Build and deploys to Cloud Run:

- **When:** on pushes to `main` that change `app/**`, `Dockerfile`, `.dockerignore`, `renv.lock`, `.Rprofile`
  or `renv/activate.R` / `renv/settings.json` (docs, tests and the plan do **not** trigger a deploy), and
  on demand from the Actions tab ("Deploy to Cloud Run" > Run workflow). Deploys never overlap.
- **Same flags as `deploy.sh`.** If you change one, change the other.
- **Smoke test:** the last step requests the service URL and fails the run unless it returns HTTP 200.
  A failed deploy leaves the previous revision serving.
- **Secrets** (repo Settings > Secrets and variables > Actions): `GCP_SA_KEY` (a JSON key of the
  `github-deploy` service account) and `GCP_PROJECT_ID` (`bibliostatus-app`).
- **Pinned actions:** third-party actions are pinned to commit SHAs (the comment gives the version);
  Dependabot (`.github/dependabot.yml`) proposes weekly updates for them and for the Docker base image.

**About the key.** `github-deploy` is shared with BiblioStatus and has broad project roles (Cloud Run admin,
storage admin, Cloud Build, Artifact Registry writer, service account user). The key stored here is a second,
separate key for it (id starts `59985cf8`); the older key (BiblioStatus) must not be deleted. A more secure
setup is Workload Identity Federation (keyless, short-lived tokens) with a dedicated least-privilege account.

## Security headers

The page response carries `X-Frame-Options: DENY` plus an enforced CSP with `frame-ancestors 'none'`
(clickjacking), `Referrer-Policy`, `Permissions-Policy` (geolocation for the app only), HSTS, and a full
`Content-Security-Policy-Report-Only`. They live in `app/www/security.R` and are applied in `app/run.R`
by wrapping the app's page handler (Shiny's `shiny.http.response.filter` option does nothing).

The report-only policy allows exactly the hosts the app uses: itself, `*.basemaps.cartocdn.com` (tiles) and
`fonts.cdnfonts.com` (Gotham). Browsers don't enforce it, they only report violations. To see them reliably,
add a `securitypolicyviolation` event listener in the page (the Chrome console tool does not show report-only
violations). To tighten: once no violations show up during real use, rename the header to
`Content-Security-Policy` in `security.R` (and consider dropping `'unsafe-eval'` first, then replacing
`'unsafe-inline'` with nonces if Shiny allows it).

## GitHub repository settings

Set through the GitHub API (so not visible in the code): secret scanning and push protection, Dependabot
alerts and security updates, and protection of `main` against force-push and deletion (applies to admins
too; no pull-request or status-check requirement, so normal pushes and the deploy pipeline work).

## Project page (GitHub Pages)

`docs/index.html` is published from the `main` branch `/docs` folder, and appears at
https://youcanbeapirate.com/FillariStatus/ because the user site (`AnttiRask.github.io`) has the custom domain
`youcanbeapirate.com`. It reuses the BiblioStatus page's stylesheet. Preview it locally with
`python3 -m http.server --directory docs`.

## Custom domain

`fillaristatus.youcanbeapirate.com` is mapped to the service:

```bash
gcloud beta run domain-mappings create \
    --service fillaristatus-app \
    --domain fillaristatus.youcanbeapirate.com \
    --region europe-north1 --project bibliostatus-app
```

DNS for `youcanbeapirate.com` is hosted at NS1; the record is `CNAME fillaristatus -> ghs.googlehosted.com.`
(same as BiblioStatus). Check progress with
`gcloud beta run domain-mappings describe --domain fillaristatus.youcanbeapirate.com --region europe-north1 --project bibliostatus-app`
(look at `CertificateProvisioned`).

**State when this was written: certificate still pending.** DNS was correct (resolves to the same Google
address as BiblioStatus, no CAA records), but the first certificate attempt ran before the DNS record was
visible and Google backs off its retries (1 min, then 5 min, ...). Deleting and recreating the mapping with the
DNS record already in place restarts issuance with a fresh retry timer. Until the certificate exists, use the
`run.app` address.

Once the domain serves HTTPS, restrict the Carto tile key to the domain in Carto's dashboard (the key is
visible in tile URLs on any public site).

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
