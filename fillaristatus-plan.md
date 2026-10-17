# FillariStatus — Project Plan

> A free, fast "nearest city bike stations" app for Helsinki & Espoo, built as a sibling of [BiblioStatus](https://github.com/AnttiRask/BiblioStatus).
>
> **Live:** https://fillaristatus-app-884476669514.europe-north1.run.app · **Repo:** https://github.com/AnttiRask/FillariStatus (private)
>
> **For Claude Code:** read this whole file first. §0 says where the project stands, §12 lists the gotchas that cost time. BiblioStatus (`~/VSCode/BiblioStatus`) is the pattern to reuse. Ask before deploying anything or creating cloud resources, and before touching GitHub secrets, DNS or the repo's visibility.

*Last updated: 2026-10-17, after Milestone 7 (deployed).*

---

## 0. Status at a glance

| # | Milestone | Status | Key commit(s) |
|---|---|---|---|
| 1 | Explore the API, save a fixture | Done | `577c6cf` |
| 2 | Data layer (`api.R`, `functions.R`) + tests | Done | `ec426ed` |
| 3 | Minimal app, live data, shared cache | Done | `7d00d99` |
| 4 | Geolocation, favourites, N selector (mode toggle later removed) | Done | `4ca9c42`, `fc28dc7` |
| 5 | Map tab, dark mode, styling | Done | `eafcaf0`, `5d2de01`, `b84ce76`, `6c3fab7`, `75f1ce5`, `146ea39` |
| 6 | Off-season and error states | Done | `72d9c41` |
| 7 | Docker + Cloud Run deploy | **Done, live** | `d0358e7`, `ca8c2d9`, `40051f3` |
| 8 | README, CLAUDE.md, screenshot, favicon | **Next** | — |

**Pushed but not yet deployed:** the "Loading map…" placeholder (`fd1a23c`). The user chose to batch the redeploy with Milestone 8.

**Not done yet (needs the user's say-so):** GitHub Actions auto-deploy, custom domain `fillaristatus.youcanbeapirate.com`, making the repo public (then add the repo link to the footer).

**Never verified (be honest about these):** phone browsers and Safari/Firefox (only desktop Chrome was driven; the user once reported an intermittent empty map box in "another desktop browser"), behaviour at a real season change (stations are live now), Cloud Run cold-start duration, and Carto's 503 behaviour under bursts.

## 1. Why

- The Kaupunkifillarit app is no longer free.
- The same station data is publicly available (HSL / Digitransit), but the HSL website UI is clunky for the one question that matters: *"Are there bikes near me right now?"*
- Goal: answer that question in under 3 seconds on a phone.

## 2. Scope

### Delivered in v1 (as built, which differs from the first draft; see §11)
- **N nearest stations** from the browser's location (selector 1–20, default 5) as cards: name with station number in brackets (`Kamppi (077)`), distance, a large **bike count**, colour bar (empty 0 / low 1–2 / plenty 3+), directions link (Google Maps, walking).
- Distance shown as whole metres under 1 km and kilometres with a decimal comma from 1 km (`642 m`, `1,64 km`).
- **Bikes only.** Free docks are fetched and parsed (`docks`) but not shown: a bike can be returned to a full station, so the count of bikes is the question.
- **Search** by name or station number, always available. A non-blank search replaces the nearest list (still sorted by distance from the user, still capped by N); clearing it restores the list. While searching, the map fits the results only, so a far-away match doesn't zoom out to include the user.
- **Favourites** (per browser, `localStorage`): a favourite inside the N nearest takes one of the N slots; favourites outside it are added on top. Pinned first. Star on list cards and in map popups.
- **Map tab** (leaflet, Carto tiles): markers coloured by status with the bike count printed on them, popups mirroring the card (with the favourite star), a ring-and-dot "you are here" marker, drawn through `leafletProxy` so pan/zoom survive the refresh. Shows "Loading map…" until drawn.
- **Auto-refresh** every 60 s plus "Updated 6 min ago"; manual Refresh button (rate-limited).
- **Dark mode** (bslib toggle, follows the system), mobile-first single column.
- **States:** off-season ("City bike season is over…", not an error), failed refresh with older data (keeps showing it, warns how old), failed first load (plain message, never raw error text), location denied (notice + search), empty search.
- Footer: HSL / Digitransit CC BY 4.0 attribution, a privacy line, credit.
- English UI; all text lives in `app/www/strings.R` so Finnish can be added later.

### Out of scope (v1)
- Historical data / predictions ("usually empty by 08:15"), see §9.
- User accounts, rentals, payments.
- Vantaa or other cities' systems (the API returns only the `smoove` network).
- Showing free docks. (The "I need a dock" mode from the first draft was built, then removed on the user's request.)

## 3. Data source (verified against the live API, 2026-10-17)

**Digitransit Routing API (GraphQL), HSL router.**

- Docs: https://digitransit.fi/en/developers/apis/1-routing-api/bicycles-scooters-cars/
- **Endpoint: `https://api.digitransit.fi/routing/v2/hsl/gtfs/v1`** (no `/graphql` suffix; the first draft had one).
- Auth: free key from https://portal-api.digitransit.fi/, sent as header `digitransit-subscription-key`. Env var `DIGITRANSIT_SUBSCRIPTION_KEY`, server-side only.
- Licence: data © HSL / Digitransit, CC BY 4.0, attributed in the footer.
- The API sends `access-control-allow-origin: *`, so a browser-only app could call it directly. That is why a static GitHub Pages rewrite is *technically* possible, but it would expose the key and need a full JavaScript rewrite; it was rejected (see §8).

### Query as implemented (`app/www/api.R`)

```graphql
{
  vehicleRentalStations {
    stationId name lat lon capacity allowPickup allowDropoff operative realtime
    rentalNetwork { networkId }
    availableVehicles { total byType { count vehicleType { formFactor } } }
    availableSpaces { total }
  }
}
```

### What the real data looks like
- 455 stations, a single network `smoove`, every vehicle `BICYCLE`/`HUMAN` (no e-bikes), all `operative`, `realtime`, pickup and dropoff allowed (in-season).
- **`availableSpaces.byType` is empty for every station; free docks only exist as `availableSpaces.total`.**
- Bikes: sum of `byType` counts where `formFactor == "BICYCLE"` (`total` matches for 454 of 455 stations; `smoove:129` disagreed once).
- `capacity` ≠ bikes + docks for ~100 stations; don't derive anything from it.
- Station numbers: `smoove:077` → the physical station number `077`.
- GraphQL introspection is rate-limited ("BadFaithIntrospection"); don't loop `__type` queries.
- A saved real response is the test fixture: `tests/testthat/fixtures/stations.json` (168 KB, no key in it).

### Fallback (no key)
CityBikes' GBFS feed (`https://api.citybik.es/gbfs/2/<network-id>/station_status.json`). Not implemented; only if Digitransit becomes a problem.

## 4. Architecture (as built)

A single Shiny app, server-side, deployed like BiblioStatus. No separate backend.

```
Browser ──(location, favourites, search, N)──▶ Shiny server (Cloud Run)
                                                │
                                                ├─ get_stations()  ← memoised, 60 s TTL, shared by ALL sessions
                                                │     └─ httr2 POST → Digitransit GraphQL (key from env var)
                                                │
                                                └─ per session: filter / distance / sort / render (list + leafletProxy)
```

- **Live fetch, not a scheduled pipeline** (counts change by the minute; BiblioStatus' daily pipeline would always be stale).
- **Shared cache:** `get_stations()` is `memoise::memoise(..., cache_mem(max_age = 60))`. Many users cost one upstream call per minute.
- **Never throws:** `fetch_stations_safe()` returns `list(data, stale, error, fetched_at, attempted_at)`. On error it falls back to the last good data (`stale = TRUE`), or `data = NULL` if there never was any. `fetched_at` = last *successful* fetch, `attempted_at` = last *try*; the Refresh rate limit uses `attempted_at` so clicks during an outage don't each fire a slow failing request.
- **State machine:** `stations_state()` → `ok` / `off_season` (0 rows, no error: not an error) / `stale` / `error`.
- **Privacy by construction:** favourites live in the browser (`localStorage` ↔ Shiny input `favourites`, try/catch-guarded); the location goes to the server for the distance maths, is held in memory per session, and is never stored or logged (verified by grepping the code). The only server-wide state is the public station cache.
- **API key stays server-side.** (Carto's tile key does reach the browser inside tile URLs; see §12.)
- **Cold starts** lose the in-memory cache; the first request just fetches fresh data.
- Turso is not used.

## 5. Repo structure (as built)

```
FillariStatus/
├── fillaristatus-plan.md      # this file
├── DEPLOY.md                  # how to run locally and deploy
├── Dockerfile  .dockerignore  # allowlist ignore: secrets can't end up in the image
├── docker-compose.yml         # local run of the production image on :8083, keys from .Renviron
├── deploy.sh                  # Cloud Run deploy (confirm prompt, DRY_RUN=1)
├── .Rprofile  renv.lock  renv/ # renv (R 4.6.1)
├── .Renviron                  # git-ignored: DIGITRANSIT_SUBSCRIPTION_KEY, CARTO_API_KEY
├── app/
│   ├── run.R                  # entry point (PORT env var)
│   ├── global.R               # libraries, sources www/*.R, carto_api_key
│   ├── ui.R                   # tabs, controls, footer; CSS custom properties; asset() cache-busting
│   ├── server.R               # reactive logic, list rendering, map via leafletProxy
│   └── www/
│       ├── variables.R        # thresholds, colour palettes, map settings, defaults
│       ├── strings.R          # ALL user-facing text
│       ├── api.R              # query, fetch, parse, stale fallback, memoised get_stations()
│       ├── functions.R        # distance, status, nearest, search, formatting, popup/icon helpers, states
│       ├── geolocation.js     # navigator.geolocation → Shiny inputs
│       ├── favourites.js      # localStorage ↔ Shiny; capture-phase click; re-opens popup after redraw
│       └── styles.css
└── tests/testthat/
    ├── fixtures/stations.json
    ├── test-api.R  test-functions.R  test-server.R   # ~170 expectations
```

`app/www/` is served as static files, so the R files in it are downloadable from the running app. They contain no secrets (keys come from the environment).

## 6. Implementation notes (as built)

### Data layer
- `parse_stations()` → one row per station: `station_id, name, lat, lon, capacity, bikes, docks, allow_pickup, allow_dropoff, operative, network_id`. Empty list → zero-row tibble with the right types (`empty_stations()`).
- `nearest_stations(stations, user_lat, user_lon, n, favourites)`: keeps operative stations that allow pickup, adds `distance_m`, `status`, `favourite`; returns the n nearest plus any favourites outside them, favourites first. **Argument names are `user_lat`/`user_lon` on purpose** — plain `lat`/`lon` were masked by the data columns inside `mutate()` and gave distance 0 for every station (found only by a live run).
- `filter_by_name()` matches name or station number, case-insensitive, fixed-string (no regex).
- Colour: palette in `variables.R` (Okabe-Ito-based light, brighter dark variants), injected into the page as CSS custom properties by `ui.R`, so there is one source of truth.

### UI/server
- Tabs List/Map under shared Search + Stations (1–20) + Refresh + "My location".
- Search is `debounce()`d 300 ms. `searching()` drives the map-fit rule and the empty-list message.
- Map: base map in `renderLeaflet`; markers via `leafletProxy` once `input$map_bounds` shows the map exists (see §12). The view re-fits only when the station set or the location changes; popups pan to stay ≥60 px from the left edge (clear of the zoom buttons).
- Marker label (bike count) is black text (≥5.4:1 on every status fill). The user marker is an SVG ring-and-dot icon so it doesn't rely on colour.

### Accessibility findings (measured, not assumed)
- Status colours were simulated for protan/deutan/tritan (Machado 2009, ΔE2000): the three statuses stay distinguishable (worst: light "empty" vs "low" under deuteranopia, ΔE 12.5). The bike count is on every card and marker, so colour is never the only cue.
- **Don't darken the amber "low" colour** to reach 3:1 contrast on white: it becomes indistinguishable from "empty" for deuteranopia (ΔE 3.1 at `#C28200`, 0.5 at `#B87A00`). The bar is decorative next to the number. Only the favourite star got a darker amber (`#B87A00`, 3.6:1), since it is never compared with the status colours.
- A solid red "you are here" dot was nearly identical to the vermillion "empty" marker for deuteranopia (ΔE 1.5), hence the ring-and-dot shape.

## 7. Testing

- `testthat` 3 with the saved fixture; no live API calls. HTTP mocked with `httr2::local_mocked_responses()`. `testServer()` for the server logic with a configurable `get_stations()` mock (`mock_result`) covering ok / off-season / stale / no-data.
- Covered: parsing (real fixture, bikes-only counting, empty list), missing key, GraphQL errors, stale fallback and timestamps, haversine, status thresholds, nearest + favourites rules, search, distance formatting, colour/tile/popup/icon helpers (including HTML escaping of station names), state classification, refresh rate-limit, server inputs (location, N 1–20, favourites, search, map readiness, dark mode).
- Run: `Rscript -e 'testthat::test_dir("tests/testthat", reporter = "summary")'`. Clean up the `_problems/` folder and `testthat-problems.rds` it can leave behind (both git-ignored).
- **Real-browser checks** were done by driving Chrome (the extension tools): list, map, popups, favourites, search, dark mode, the three data states (via a throwaway harness faking `get_stations()`), the container, and the live site. Not driven: Safari, Firefox, phones.
- Caveat learned: `testServer()` doesn't step `debounce()` timers for a value that was already read; tests read `searching()`/`nearest()` for the first time *after* the input change, and the live debounce was confirmed in the browser.

## 8. Deployment (as deployed)

- **GitHub Pages was considered and rejected.** Pages only hosts static files; this is an R Shiny app that needs a server process. A JS rewrite would expose the Digitransit key in the page, lose the shared cache, and discard the built and tested app.
- **Where:** Google Cloud Run, project `bibliostatus-app` (shared with BiblioStatus, as decided), region `europe-north1`, service `fillaristatus-app`, public (`--allow-unauthenticated`), 1 GiB, `--max-instances 3`, `--concurrency 20`, `--session-affinity`, timeout 3600 s. Revision `fillaristatus-app-00001-kcc` served 100 % of traffic after the first deploy.
- **Secrets:** Secret Manager `digitransit-subscription-key` (created by `deploy.sh` from `.Renviron`) and the existing `carto-api-key`, both exposed as env vars through `--set-secrets`; the runtime service account `884476669514-compute@developer.gserviceaccount.com` has `secretAccessor`. A `github-deploy` service account already exists in the project (BiblioStatus uses it for Actions).
- **Image:** `rocker/r-ver:4.6.1` (Ubuntu 24.04), system libraries from Posit Package Manager's sysreqs API, `renv::restore()` from P3M Linux binaries, renv cache **disabled** at build, non-root user `fillari`, ~889 MB. Built by Cloud Build (`gcloud builds submit`), ~7 min.
- **Deploy:** `./deploy.sh` (asks for confirmation; `DRY_RUN=1` prints the plan). Locally: `docker compose up --build` → http://localhost:8083.
- Observed: cold start 3.3 s, warm response ~0.24 s; Cloud Run logs clean; the only non-2xx is `GET /favicon.ico` 404.
- **Cost:** within the free tier expected; no budget alert was set up. `--min-instances 1` would remove cold starts at a small recurring cost (not applied; the user decides).

## 9. Later ideas (v2+)
- **Tile robustness:** retry failed tiles. On one live load Carto answered 8 of 9 starting-zoom tiles with HTTP 503 (all fine moments later). Also avoid the throwaway zoom-13 starting view (request tiles only for the fitted view).
- **Redeploy** with the loading placeholder (batched with Milestone 8).
- Restrict the Carto key to the FillariStatus domain(s) in Carto's dashboard (the key is visible in tile URLs).
- **History & patterns:** snapshot station status every 10–15 min into Turso, show "typically empty by 08:15 on weekdays". GitHub Actions cron is too unreliable at that granularity; use Cloud Scheduler → a tiny Cloud Run job.
- Walking time via Digitransit routing instead of straight-line distance.
- PWA manifest (install to home screen); favicon (Milestone 8).
- Finnish/Swedish UI (strings are already centralised).
- Optional `--min-instances 1`; a Cloud Billing budget alert.
- Companion course module, reusing the BiblioStatus course format.

## 10. Milestones

1. **Explore** — Done. Key obtained, endpoint and fields verified, fixture saved.
2. **Data layer** — Done. `api.R` + `functions.R` + tests against the fixture.
3. **Minimal app** — Done. Hardcoded location, list, live data, cache.
4. **Geolocation + favourites + N selector** — Done. (The bike/dock toggle was built here and removed shortly after, at the user's request.)
5. **Map tab + dark mode + styling** — Done, then refined: markers drawn only once the map exists; popups with favourite star; popups clear of zoom controls; Stations dropdown no longer hidden behind the map's zoom buttons (`isolation: isolate` on the map).
6. **Off-season & error states** — Done.
7. **Docker + Cloud Run deploy** — Done and live.
8. **README, CLAUDE.md, screenshot, favicon** — **Next.** Also: redeploy with the loading placeholder; decide on GitHub Actions auto-deploy, the custom domain and making the repo public.

## 11. Decisions (originally "open questions")

| Question | Decision |
|---|---|
| Name | FillariStatus (kept) |
| Default N | 5, user-selectable 1–20 |
| E-bikes / other vehicles | Bikes only (the API only has human-powered bikes anyway) |
| GCP project | Same as BiblioStatus (`bibliostatus-app`) |
| Finnish UI in v1 | No: English only, strings centralised |
| Bike/dock mode | Removed: "a bike can be returned to a full station", so only bikes matter |
| Station search | Always available, overrides the location list when non-empty |
| Station numbers | Shown in brackets after the name |
| Distance format | m below 1 km, km with decimal comma above |
| Favourites vs N | A favourite inside the N nearest takes a slot; others are added on top |
| "You are here" colour | Red (user's request), as a ring-and-dot icon for accessibility |
| Popups vs zoom buttons | Can't be drawn on top (Leaflet puts controls above the map pane); popups pan to stay clear |
| Static hosting on GitHub Pages | Rejected (§8) |
| Redeploy timing | Batch with Milestone 8 |

## 12. Conventions and lessons learned

### Conventions
- R, tidyverse style (`|>`, `dplyr`, `purrr`, `tidyr`, `stringr`), `renv`. Config (thresholds, colours, defaults, map settings) in `variables.R`; all UI text in `strings.R`.
- Small commits tied to milestones; after every commit/push verify the remote (`git ls-remote origin refs/heads/main` equals `HEAD`). Never suppress errors in scripts that call GitHub/GCP APIs.
- Show the user the running app after every visible change (`PORT=8083 Rscript app/run.R`; stop it by port, never `pkill -f app/run.R`, which also matches BiblioStatus' container).
- When something fails: read the full error, find the root cause, explain it, propose 2–3 ranked fixes, implement the top one; don't retry the same thing.

### Gotchas that cost time
- **Carto returns HTTP 200 with a watermark tile ("API KEY REQUIRED") when the key is missing.** Check tile *size/content*, not status (real ≈ 13–23 KB, watermark ≈ 2 KB). `CARTO_API_KEY` lives in `.Renviron` locally and in Secret Manager in the cloud.
- **Leaflet drops `leafletProxy` messages for a map that doesn't exist yet.** The map is in a hidden tab, so Shiny doesn't render it until first shown; drawing waits for `input$map_bounds`.
- **Leaflet fires `layeradd` before popups are bound**, and stops click propagation inside popups: `favourites.js` listens in the capture phase and re-opens the popup after the settle.
- **Leaflet's own z-indexes (controls 1000) beat page UI** unless the map container has `isolation: isolate`.
- **Browsers cache `styles.css`/JS.** `ui.R`'s `asset()` appends the file's mtime; it is evaluated once at startup, so restart the app after editing assets.
- **Shiny `debounce()` + `testServer()`:** see §7.
- **`mutate()` data masking:** don't name function arguments like data columns (§6).
- **Docker/renv:** (1) the base image needs the system libraries listed by P3M's sysreqs API (missing `libuv` broke the `fs` binary); (2) renv by default installs into the *build user's* cache and symlinks, so a non-root runtime user got "no package called 'shiny'" — set `RENV_CONFIG_CACHE_ENABLED=FALSE` at build. A Docker build piped through `tee`/`tail` reports the pipe's exit code: capture `docker build`'s own exit code and check that the image exists.
- **Same for `deploy.sh`:** the real exit code is the log's last line, not the background task's.
- **gcloud prompts:** run read-only gcloud commands with stdin closed (`</dev/null`) so a "enable this API?" prompt can't be auto-confirmed.
- Chrome-extension quirks: refs go stale; a scroll wheel over the map zooms the map; bslib's dark-mode toggle needs a *real* click; don't call `location.reload()` inside a script.
- Carto key is exposed in tile URLs by design (as in BiblioStatus); restrict it by domain in Carto's dashboard once there is a stable domain.

## 13. Next steps (in order)
1. **Milestone 8:** `README.md` (what it is, screenshot, local run, link to DEPLOY.md), `CLAUDE.md` (adapt BiblioStatus': commands, architecture, gotchas from §12), screenshot (Chrome), favicon, then **redeploy** (placeholder + favicon).
2. Decide with the user: GitHub Actions auto-deploy (needs the `github-deploy` key as a secret in this repo: ask first), custom domain `fillaristatus.youcanbeapirate.com` (DNS CNAME to `ghs.googlehosted.com`), making the repo public (then add the repo link to the footer).
3. v2 candidates from §9 (tile retry, history/patterns, walking time, PWA, Finnish UI).
