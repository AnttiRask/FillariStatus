# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with this repository. `fillaristatus-plan.md` has the full history, decisions and verified API facts; read its §0 and §12 first.

## Project Overview

FillariStatus is an R Shiny app that lists the nearest Helsinki/Espoo city bike stations with live bike counts (list + map). Data comes live from the Digitransit GraphQL API (HSL), cached for 60 s and shared across visitors. No database, no accounts. It is a sibling of `~/VSCode/BiblioStatus` and reuses its patterns (Cloud Run, renv, folder layout).

## Common Commands

```bash
# Run the app locally (keys come from .Renviron, which R reads on startup)
PORT=8083 Rscript app/run.R            # open http://localhost:8083

# Tests (no live API calls)
Rscript -e 'testthat::test_dir("tests/testthat", reporter = "summary")'
rm -rf tests/testthat/_problems tests/testthat/testthat-problems.rds   # failure artifacts

# Production image locally (reads .Renviron at runtime)
docker compose up --build

# Deploy (asks for confirmation; DRY_RUN=1 only prints the plan)
./deploy.sh
```

Stop a local server **by port** (`ss -ltnp | grep :8083`), never with `pkill -f app/run.R`: that also matches the user's BiblioStatus container.

## Architecture

- `app/www/api.R` - query, `fetch_stations_raw()`, `parse_stations()`, `fetch_stations_safe()` (never throws; keeps last good data; returns `data, stale, error, fetched_at, attempted_at`), memoised `get_stations()` (60 s, shared by all sessions).
- `app/www/functions.R` - `haversine_m`, `classify_status`, `nearest_stations` (n nearest + favourites outside them, favourites first), `filter_by_name`, `format_distance`, `stations_state` (`ok`/`off_season`/`stale`/`error`), popup/icon/colour helpers.
- `app/www/variables.R` - thresholds, status palettes (light/dark), map settings, defaults. `app/www/strings.R` - **all** user-facing text. Add UI text there, not inline.
- `app/server.R` - reactive logic; the list is a `renderUI`; the map base is `renderLeaflet` and markers are drawn through `leafletProxy`.
- `app/ui.R` - layout; injects the status colours as CSS custom properties; `asset()` appends the file mtime to CSS/JS URLs (evaluated once at startup: restart after editing assets).
- `app/www/security.R` - security headers (enforced frame-ancestors CSP, X-Frame-Options, Referrer-Policy, Permissions-Policy, HSTS, report-only CSP); `app/run.R` wraps the app's `httpHandler` with `with_security_headers()` (Shiny's `shiny.http.response.filter` option does nothing).
- Theme: youcanbeapirate brand colours in `variables.R` (`brand_colours`), a bslib theme with Gotham (loaded from `fonts.cdnfonts.com`), **light by default** (`input_dark_mode(mode = "light")`), one `--fs-accent` CSS custom property per theme (brand red; lighter red `#F26B70` on dark). Brand red is for chrome only, never for status meaning.
- `app/www/geolocation.js` / `favourites.js` - browser location and `localStorage` favourites, wired to Shiny inputs.
- Tests: `tests/testthat/` with a saved real response in `fixtures/stations.json`; `test-server.R` uses `testServer()` with a configurable `get_stations()` mock.

## Environment Variables

- `DIGITRANSIT_SUBSCRIPTION_KEY` - Digitransit API key (server-side only).
- That is the only secret. The map tiles (Esri World Light/Dark Gray) are keyless. Locally it lives in the git-ignored `.Renviron`; in Cloud Run it comes from Secret Manager (`digitransit-subscription-key`). Never commit or print its value. (`CARTO_API_KEY` / `carto-api-key` was used until 2026-10-17; the `carto-api-key` secret was deleted from Secret Manager on 2026-10-18.)

## Deployment

Google Cloud Run, project `bibliostatus-app` (shared with BiblioStatus), region `europe-north1`, service `fillaristatus-app`. See `DEPLOY.md`.

- **Pushes to `main` that touch `app/**`, `Dockerfile`, `.dockerignore`, `renv.lock`, `.Rprofile` or `renv/activate.R|settings.json` deploy automatically** (`.github/workflows/deploy_shiny_app.yml`, keyless Workload Identity login, secret `GCP_PROJECT_ID`, ends with a smoke test). Docs/tests/plan pushes don't deploy. Always read a run's status from GitHub (`gh run view <id> --json status,conclusion,jobs`), not from a background task's exit code. Keep the workflow's flags in sync with `deploy.sh`.
- Custom domain `fillaristatus.youcanbeapirate.com` is live over HTTPS (DNS at NS1: CNAME to `ghs.googlehosted.com.`; the Google-managed certificate renews itself). If a new mapping's certificate stays pending although DNS is right, delete and recreate the mapping (see DEPLOY.md), then require several consecutive successful HTTPS requests before calling it live.
- The project page is `docs/` published by GitHub Pages at youcanbeapirate.com/FillariStatus/. **Ask the user before** creating cloud resources, deploying, touching GitHub secrets, DNS or the repo's visibility. When running `gcloud` read-only commands, close stdin (`</dev/null`) so an "enable this API?" prompt can't be auto-answered.

## Gotchas (each cost real time)

- **Leaflet drops `leafletProxy` messages for a map that doesn't exist yet.** The map sits in a hidden tab; markers are drawn only after `input$map_bounds` arrives.
- Leaflet fires `layeradd` *before* popups are bound and stops click propagation inside popups: `favourites.js` uses a capture-phase listener and re-opens the popup after the markers settle.
- Leaflet's controls (z-index 1000) beat page UI unless `.leaflet-container` has `isolation: isolate`. Popups can't be drawn above the zoom buttons; they pan to stay clear.
- Don't name function arguments like data columns inside `mutate()` (`lat`/`lon` were masked and every distance was 0). `nearest_stations()` uses `user_lat`/`user_lon`.
- `availableSpaces.byType` is empty in the live API; free docks only exist as `total`. The app shows bikes only.
- `testServer()` doesn't step `debounce()` timers for a value already read; read search-dependent values for the first time *after* the input change.
- Docker: system libraries come from Posit Package Manager's sysreqs API; renv's cache must be disabled at build (`RENV_CONFIG_CACHE_ENABLED=FALSE`), otherwise packages are symlinks into root's private cache and the non-root runtime user can't load them. A build piped through `tee`/`tail` reports the pipe's exit code: capture `docker build`'s own and check the image exists. Same for `deploy.sh`.
- Don't darken the amber "low" colour for contrast: it becomes indistinguishable from "empty" for deuteranopia (see plan §6). The bike count is on every card and marker.
- **Map tiles (Esri):** attribution must be `addTiles()`'s own `attribution` argument (it overwrites `options$attribution`, so one inside `tileOptions()` is silently dropped; `add_basemap()` does it right and a test guards it). Real tiles stop at zoom 16 (17+ is a grey "Map data not yet available" tile), so requests are capped there. Esri URLs are `{z}/{y}/{x}`. Tile providers can answer HTTP 200 with a placeholder (Carto's missing-key watermark, Esri above zoom 16): check tile content/size, not the status code. No SLA: if the provider changes, see DEPLOY.md > Map tiles.
- Test in the browser, not only with unit tests: most bugs above were found by driving Chrome.
- The Chrome console tool does **not** show CSP report-only violations; add a `securitypolicyviolation` listener in the page (and prove it catches a deliberate probe) before concluding "no violations".
- Geolocation permission can silently differ per loopback origin (127.0.0.1 vs 127.0.0.2). For screenshots that go into the repo, force the fallback position with `Shiny.setInputValue('user_location', {lat: 60.1699, lon: 24.9384, accuracy: 20}, {priority: 'event'})`, check the first station is Mannerheimintie at 42 m, and delete the raw captures afterwards.
- zsh does not word-split unquoted variables (`set -- $pair` and `for x in $var` behave differently from bash); use arrays or explicit arguments in shell snippets.
- `docker image ls` shows the unpacked size (~3 GB); the registry shows the compressed size (~890 MB) that Cloud Run pulls.

## Conventions

- R with tidyverse style (`|>`, `dplyr`, `purrr`, `tidyr`, `stringr`); `renv` for dependencies. Config in `variables.R`, text in `strings.R`.
- Small commits tied to milestones. After every commit/push verify the remote: `git ls-remote origin refs/heads/main` must equal `git rev-parse HEAD`. Never suppress errors in scripts that call GitHub/GCP APIs.
- When a fix for CI, a deploy or a script fails: read the full error, find the root cause, explain it, propose 2-3 ranked fixes, then implement the top one. Don't retry the same thing.
- Show the user the running app after every visible change.
