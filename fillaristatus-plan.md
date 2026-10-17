# FillariStatus — Project Plan

> Working name. A free, fast "nearest city bike stations" app for Helsinki & Espoo, built as a sibling of [BiblioStatus](https://github.com/AnttiRask/BiblioStatus).
>
> **For Claude Code:** read this whole file first, then skim the BiblioStatus repo (`app/`, `Dockerfile`, `deploy.sh`, `DEPLOY.md`, `CLAUDE.md`) before writing code. Reuse its patterns wherever they fit. Ask before deploying anything or creating cloud resources.

---

## 1. Why

- The Kaupunkifillarit app is no longer free.
- The same station data is publicly available (HSL / Digitransit), but the HSL website UI is clunky for the one question that matters: *"Are there bikes (or free docks) near me right now?"*
- Goal: answer that question in under 3 seconds on a phone.

## 2. Scope

### In scope (v1)
- Use the browser's location to list the **N nearest stations** (default 5) with:
  - bikes available
  - free docks available
  - walking-ish distance (straight-line metres)
  - colour status: empty / low / plenty
- **Mode toggle:** "I need a bike" vs "I need a dock" (end of ride). Changes sorting/colouring.
- **Map view** (leaflet) as a toggle/tab, markers colour-coded like BiblioStatus.
- **Auto-refresh** about every 60 s, plus a "last updated X s ago" stamp.
- **Favourites** pinned to the top (per-browser, localStorage).
- **Station search** by name (fallback when GPS is denied).
- **Off-season state:** when the API returns no stations, show a friendly "City bike season is over" message, not an error.
- Dark mode, mobile-first layout (reuse BiblioStatus `styles.css` approach).
- "Get directions" link (Google Maps), as in BiblioStatus.

### Out of scope (v1)
- Historical data / predictions ("usually empty by 08:15"). This is a v2 idea; see §9.
- User accounts, rentals, payments.
- Vantaa or other cities' bike systems (unless trivially included by the same query; see §3).

## 3. Data source

**Digitransit Routing API (GraphQL), HSL router.**

- Docs: https://digitransit.fi/en/developers/apis/1-routing-api/bicycles-scooters-cars/
- GraphiQL explorer: https://api.digitransit.fi/graphiql/hsl/v2/gtfs/v1
- Endpoint (**verify in docs before use**): `https://api.digitransit.fi/routing/v2/hsl/gtfs/v1/graphql`
- Auth: free API key from https://portal-api.digitransit.fi/. Send it as header `digitransit-subscription-key: <key>`.
- Licence/attribution: data © HSL / Digitransit, CC BY 4.0. Show attribution in the app footer.
- Seasonality: stations can disappear from the API outside the bike season.

### Starting query

```graphql
{
  vehicleRentalStations {
    stationId
    name
    lat
    lon
    capacity
    allowPickup
    allowDropoff
    operative
    realtime
    rentalNetwork { networkId }
    availableVehicles { byType { count vehicleType { formFactor } } }
    availableSpaces  { byType { count vehicleType { formFactor } } }
  }
}
```

**Verify in GraphiQL before coding against it:**
- [ ] Exact endpoint URL and that the key header works.
- [ ] Which of the fields above exist in the current schema (`operative`, `realtime`, `rentalNetwork`, `capacity` in particular). Drop any that don't.
- [ ] Which `networkId`(s) cover the Helsinki + Espoo city bike stations (station IDs look like `smoove:396`). Decide whether to filter out other networks.
- [ ] Response size and latency for the full station list (expected: a few hundred stations, which is fine to pull in one go).
- [ ] Save one real response as a test fixture: `tests/testthat/fixtures/stations.json`.

### Fallback (no key)
CityBikes publishes a re-normalised GBFS feed (`https://api.citybik.es/gbfs/2/<network-id>/station_status.json`). It's a third party, so freshness isn't guaranteed. Implement only if Digitransit becomes a problem.

## 4. Architecture

A single Shiny app, server-side, deployed like BiblioStatus. No separate API backend.

```
Browser ──(geolocation, mode, favourites)──▶ Shiny server (Cloud Run)
                                              │
                                              ├─ get_stations()  ← memoised, 60 s TTL, shared by ALL sessions
                                              │      └─ httr2 POST → Digitransit GraphQL (key from env var)
                                              │
                                              └─ per session: filter / distance / sort / render
```

Key decisions:
- **Live fetch, not a scheduled pipeline.** BiblioStatus uses daily GitHub Actions → Turso because library hours change daily. Bike counts change by the minute, so a scheduled pipeline would always be stale.
- **Shared cache.** `get_stations()` is defined at global level and wrapped with `memoise::memoise(..., cache = cachem::cache_mem(max_age = 60))`. Many users then cost one upstream call per minute, and the app is polite to Digitransit's rate limits.
- **API key stays server-side.** The key is read from env var `DIGITRANSIT_SUBSCRIPTION_KEY` and never sent to the browser. (This is why a Shinylive or static deployment is not an option here.)
- **Per-session refresh.** `invalidateLater(60000)` triggers a re-read of the (cached) data and a re-render.
- **Cold starts:** Cloud Run may scale to zero, which loses the in-memory cache. That's acceptable; the first request just fetches fresh data.
- **Turso is not used in v1.**

## 5. Proposed repo structure

Mirror BiblioStatus so the two projects feel familiar:

```
FillariStatus/
├── CLAUDE.md                 # conventions for Claude Code (copy/adapt from BiblioStatus)
├── README.md
├── DEPLOY.md
├── Dockerfile
├── docker-compose.yml        # local dev on e.g. port 8083
├── deploy.sh                 # Cloud Run deploy (adapt from BiblioStatus)
├── .Rprofile / renv.lock / renv/
├── .github/workflows/
│   └── deploy_shiny_app.yml  # deploy on push to main (adapt from BiblioStatus)
├── R/                        # (optional) dev-only scripts, e.g. explore_api.R
├── app/
│   ├── run.R                 # entry point (host/port), as in BiblioStatus
│   ├── global.R              # libraries, config, memoised get_stations()
│   ├── ui.R
│   ├── server.R
│   └── www/
│       ├── api.R             # build query, call Digitransit, parse to tibble
│       ├── functions.R       # distance, status classification, sorting
│       ├── variables.R       # colours, thresholds, refresh interval, N nearest
│       ├── geolocation.js    # navigator.geolocation → Shiny.setInputValue (reuse BiblioStatus approach)
│       ├── favourites.js     # localStorage ↔ Shiny input, wrapped in try/catch
│       └── styles.css
└── tests/testthat/
    ├── fixtures/stations.json
    ├── test-api.R
    └── test-functions.R
```

## 6. Implementation details

### 6.1 Fetch & parse (`app/www/api.R`)
- `fetch_stations_raw()`: `httr2::request(endpoint) |> req_headers("digitransit-subscription-key" = key) |> req_body_json(list(query = query)) |> req_timeout(10) |> req_retry(max_tries = 2) |> req_perform()`.
- `parse_stations(json)` returns a tibble with one row per station: `station_id, name, lat, lon, capacity, bikes, docks, allow_pickup, allow_dropoff, operative, network_id`.
  - `bikes` = sum of `availableVehicles$byType$count` (consider filtering `formFactor == "BICYCLE"`).
  - `docks` = sum of `availableSpaces$byType$count`.
  - Use `purrr` + `tidyr::unnest_*` and tidyverse style throughout.
- `get_stations()` is the memoised wrapper. On error it returns the last good result if one exists (keep a module-level "last good" object) plus a flag, so the UI can show "data may be stale".
- Empty list means off-season, which is a distinct state from an error.

### 6.2 Logic (`app/www/functions.R`)
- `haversine_m(lat1, lon1, lat2, lon2)`: vectorised, no extra dependency. Alternatively reuse BiblioStatus's distance code if it's already there.
- `classify_status(n, mode)`: `0` → empty (red), `1–2` → low (amber), `3+` → plenty (green). Keep thresholds in `variables.R`.
- `nearest_stations(stations, lat, lon, n, mode, favourites)`: add distance, keep stations that are operative and allow pickup/dropoff as relevant to the mode, pin favourites first, then sort by distance, take `n`.

### 6.3 UI (`app/ui.R`)
- Top: mode toggle (🚲 Bike / 🅿️ Dock), "updated X s ago", refresh button.
- Default tab **List**: cards with name, distance, a big number for bikes or docks (depending on mode) with the other number small, colour bar, ⭐ favourite toggle, directions link.
- Tab **Map**: leaflet with user location plus colour-coded station markers; popups match the card content.
- Fallback when location is denied: search box plus a message explaining why location helps.
- Footer: data attribution (HSL / Digitransit, CC BY 4.0), link to the repo, "You Can Be a Pirate" branding consistent with BiblioStatus.
- Language: start with English UI and keep strings in one place so Finnish can be added later. Show station names as returned by the API.

### 6.4 Server (`app/server.R`)
- Inputs from JS: `input$user_location` (lat, lon, accuracy), `input$favourites` (vector of station IDs).
- `stations <- reactive({ invalidateLater(refresh_ms); get_stations() })`.
- `nearest <- reactive(nearest_stations(stations()$data, ...))`.
- Render the list and map. Use `leafletProxy` to update markers without re-rendering the whole map.

## 7. Testing
- `testthat` with the saved fixture. No live API calls in tests.
- Mock HTTP with `httr2::local_mocked_responses()` (or `with_mocked_responses()`).
- Cases:
  - parse a normal response
  - parse an empty station list (off-season)
  - API error falls back to last good data
  - haversine against a known distance (e.g. Rautatientori → Kamppi, roughly 1 km)
  - nearest-station sorting with favourites pinned
  - status thresholds
- Manual: test on a real phone (geolocation requires HTTPS, which Cloud Run provides).

## 8. Deployment
- Same as BiblioStatus: Docker → Google Cloud Run via `deploy.sh` and GitHub Actions.
- Secret: put `DIGITRANSIT_SUBSCRIPTION_KEY` in Google Secret Manager and expose it to the Cloud Run service as an env var. Use a GitHub secret only if the workflow needs it. Never commit the key; add `.Renviron` to `.gitignore`.
- Local dev: `.Renviron` with the key; `docker compose up --build`.
- Domain: e.g. `fillaristatus.youcanbeapirate.com` (TBD).

## 9. Later ideas (v2+)
- **History & patterns:** snapshot station status every 10–15 min into Turso and show "typically empty by 08:15 on weekdays". Note that GitHub Actions cron is unreliable at that granularity, so consider Cloud Scheduler → a tiny Cloud Run job instead.
- Walking time via Digitransit routing instead of straight-line distance.
- PWA manifest so the app can be "installed" on the home screen.
- Finnish/Swedish UI.
- Companion course module, reusing the BiblioStatus course format.

## 10. Milestones

1. **Explore:** get the API key, verify the query in GraphiQL (§3 checklist), save the fixture.
2. **Data layer:** `api.R` + `functions.R` + tests passing against the fixture.
3. **Minimal app:** hardcoded location, list view, live data, cache working.
4. **Geolocation + favourites + mode toggle.**
5. **Map tab + dark mode + styling** (port from BiblioStatus).
6. **Off-season & error states.**
7. **Docker + Cloud Run deploy** (ask Antti before creating cloud resources).
8. **README, DEPLOY.md, CLAUDE.md, screenshot.**

## 11. Open questions for Antti
- Final name? (FillariStatus is a placeholder.)
- Default N nearest: 5? Configurable?
- Include e-bikes or other vehicle types if the API exposes them, or bikes only?
- Separate GCP project/service from BiblioStatus, or the same project?
- Should v1 include the Finnish UI from the start?

## 12. Conventions
- R, tidyverse style (`|>`, `dplyr`, `purrr`, `tidyr`), `renv` for dependencies.
- Packages: `shiny`, `bslib` (if helpful), `shinyjs`, `leaflet`, `httr2`, `jsonlite`, `dplyr`, `purrr`, `tidyr`, `stringr`, `memoise`, `cachem`, `here`, `testthat`.
- Keep config (thresholds, colours, refresh interval, N) in `variables.R`, not scattered through the code.
- Small, focused commits, each tied to a milestone.
