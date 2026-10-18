# FillariStatus — Project Plan

> A free, fast "nearest city bike stations" app for Helsinki & Espoo, built as a sibling of [BiblioStatus](https://github.com/AnttiRask/BiblioStatus).
>
> **Live:** https://fillaristatus.youcanbeapirate.com (also https://fillaristatus-app-884476669514.europe-north1.run.app) · **Repo:** https://github.com/AnttiRask/FillariStatus (public, MIT) · **Project page:** https://youcanbeapirate.com/FillariStatus/
>
> **For Claude Code:** read this whole file first. §0 says where the project stands, §12 lists the gotchas that cost time. BiblioStatus (`~/VSCode/BiblioStatus`) is the pattern to reuse. Pushes to `main` that change `app/**` or the build files **deploy automatically** (GitHub Actions), so run the tests first and batch app changes. Ask before creating or changing cloud resources, GitHub secrets, DNS or the repo's visibility.

*Last updated: 2026-10-17, after the post-launch work (theme, security headers, GitHub hygiene, project page, automatic deploys, the custom domain, and the switch to keyless Esri map tiles). Revision 6 is live.*

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
| 8 | README, CLAUDE.md, screenshot, favicon, MIT licence, redeploy | **Done, live** | `576c627`, `ee53e68` |
| 9 | Post-launch: GitHub Actions auto-deploy, youcanbeapirate theme, security headers, GitHub hygiene, project page, keyless Esri map tiles (and the missing tile attribution fixed) | **Done, live** | `b3adaac`, `2d71b9f`, `634b5cf`, `99f3442`, `0792569`, `092838d` |

**Deployed:** revision `fillaristatus-app-00006-l94` serves 100 % of traffic (the Esri map tiles; the service now has the Digitransit secret only). Deploys are automatic now: a push to `main` that touches `app/**` or the build files runs the GitHub Actions workflow (build, deploy, smoke test).

**Also done:** the FillariStatus card is on the main site (`AnttiRask.github.io`, added in `ad3c4f4`, moved directly below the BiblioStatus card; a first attempt, `1e673fc`, nested it and the cards after it inside the BiblioStatus card, and `0ace6b2` fixed that — see §12; View App / View Project / View Source all verified, 200).

**BiblioStatus (the sibling app) was switched to the same keyless Esri tiles** (repo `AnttiRask/BiblioStatus`, commits `950ecd1`, `0047b33`; revision `bibliostatus-app-00295-7cw`, verified live: Esri host only, attribution shown, nothing above tile zoom 16, no Carto request, the service has only the two Turso secrets). Its map's dark mode never worked (`isTRUE(input$dark_mode)` on bslib's string value, introduced when `0242f04` silenced an error); `e9add2d` fixes it with an `is_dark()` reactive and regression tests (80 tests pass; verified locally with real clicks) and is live as revision `bibliostatus-app-00296-fj7` (100% of traffic, only the two Turso secrets). Verified on the live site on 2026-10-17 with real clicks on the toggle: light mode has Light Gray tiles and the light palette (`#0072B2` open); dark mode has Dark Gray base + reference tiles only, no broken tiles, the dark palette (`#00C0FF`, `#FFD700`, `#FFFFFF`), attribution intact and no Shiny errors; switching back restores light.

**Carto clean-up (done 2026-10-17):** the GitHub Actions secret `CARTO_API_KEY` in `AnttiRask/BiblioStatus` was deleted by the user, the Carto lines were removed from the local gitignored files (`~/VSCode/BiblioStatus/app/secret.R`, `secret.R`, and this repo's `.Renviron`, which is a hidden file), and **both versions of the Secret Manager secret `carto-api-key` were disabled** (reversible; nothing reads it: no Cloud Run service binds it, no tracked code refers to it, and the other apps don't use Carto). Delete the secret for good later if nothing breaks. The old key was never committed to either repo's history. Nothing is required from the user; everything else open is optional (§13).

**Never verified (be honest about these):** phone browsers and Safari/Firefox (only desktop Chrome was driven; the user once reported an intermittent empty map box in "another desktop browser"), behaviour at a real season change (stations are live now), Cloud Run cold-start duration, and Esri's availability and current terms for the keyless tiles (no SLA; I could not read the terms from here).

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
- **Map tab** (leaflet, Esri World Light/Dark Gray tiles with a labels layer, no API key): markers coloured by status with the bike count printed on them, popups mirroring the card (with the favourite star), a ring-and-dot "you are here" marker, drawn through `leafletProxy` so pan/zoom survive the refresh. Shows "Loading map…" until drawn.
- **Auto-refresh** every 60 s plus "Updated 6 min ago"; the only manual control is "Update my location" (the data needs no manual refresh).
- **Light by default** with a dark mode toggle (bslib; it used to follow the OS setting), mobile-first single column, youcanbeapirate brand colours and Gotham font (§6).
- **States:** off-season ("City bike season is over…", not an error), failed refresh with older data (keeps showing it, warns how old), failed first load (plain message, never raw error text), location denied (notice + search), empty search.
- Footer: HSL / Digitransit CC BY 4.0 attribution, a privacy line, links to the sibling projects (BiblioStatus, Gallery of the Day, TrackTeller, TuneTeller) and to the source repo, credit.
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
- **API key stays server-side.** The map tiles are keyless (Esri), so no key reaches the browser. (Until 2026-10-17 a Carto tile key was visible in the tile URLs; see §6.)
- **Cold starts** lose the in-memory cache; the first request just fetches fresh data.
- **Entry point:** `app/run.R` sets the working directory to `app/`, builds the app with `shinyAppDir()` and wraps its page handler with the security headers (§6). Pushes that touch `app/**` or the build files redeploy automatically (§8).
- Turso is not used.

## 5. Repo structure (as built)

```
FillariStatus/
├── README.md  LICENSE         # public README (screenshot, features, run, deploy) and MIT licence
├── CLAUDE.md                  # guidance for Claude Code: commands, architecture, gotchas
├── fillaristatus-plan.md      # this file
├── DEPLOY.md                  # run locally, deploy, auto-deploy, security headers, domain, Pages
├── screenshot.png             # README image (list + map, taken at the Rautatientori fallback position)
├── Dockerfile  .dockerignore  # allowlist ignore: secrets can't end up in the image
├── docker-compose.yml         # local run of the production image on :8083, keys from .Renviron
├── deploy.sh                  # Cloud Run deploy (confirm prompt, DRY_RUN=1)
├── .Rprofile  renv.lock  renv/ # renv (R 4.6.1)
├── .gitignore                 # ignores .Renviron, renv/library, test artifacts, the scheduler lock file
├── .Renviron                  # git-ignored: DIGITRANSIT_SUBSCRIPTION_KEY
├── .github/
│   ├── workflows/deploy_shiny_app.yml  # auto-deploy to Cloud Run on pushes touching app/build files; smoke test
│   └── dependabot.yml                  # weekly updates for the pinned actions and the Docker base image
├── docs/                      # the project page (GitHub Pages: main, /docs): index.html, screenshot.png, favicon.png
├── app/
│   ├── run.R                  # entry point: sets the working dir, builds the app, wraps the page handler with the security headers
│   ├── global.R               # libraries, sources www/*.R
│   ├── ui.R                   # theme, tabs, controls, footer; CSS custom properties; asset() cache-busting
│   ├── server.R               # reactive logic, list rendering, map via leafletProxy
│   └── www/
│       ├── variables.R        # thresholds, status + brand palettes, map settings, links, defaults
│       ├── strings.R          # ALL user-facing text
│       ├── api.R              # query, fetch, parse, stale fallback, memoised get_stations()
│       ├── functions.R        # distance, status, nearest, search, formatting, popup/icon helpers, states
│       ├── security.R         # security headers and with_security_headers()
│       ├── geolocation.js     # navigator.geolocation → Shiny inputs
│       ├── favourites.js      # localStorage ↔ Shiny; capture-phase click; re-opens popup after redraw
│       ├── styles.css
│       └── favicon.png  favicon.ico
└── tests/testthat/
    ├── fixtures/stations.json
    └── test-api.R  test-functions.R  test-security.R  test-server.R   # 220 expectations (30 / 113 / 25 / 52)
```

`app/www/` is served as static files, so the R files in it are downloadable from the running app. They contain no secrets (keys come from the environment).

## 6. Implementation notes (as built)

### Data layer
- `parse_stations()` → one row per station: `station_id, name, lat, lon, capacity, bikes, docks, allow_pickup, allow_dropoff, operative, network_id`. Empty list → zero-row tibble with the right types (`empty_stations()`).
- `nearest_stations(stations, user_lat, user_lon, n, favourites)`: keeps operative stations that allow pickup, adds `distance_m`, `status`, `favourite`; returns the n nearest plus any favourites outside them, favourites first. **Argument names are `user_lat`/`user_lon` on purpose** — plain `lat`/`lon` were masked by the data columns inside `mutate()` and gave distance 0 for every station (found only by a live run).
- `filter_by_name()` matches name or station number, case-insensitive, fixed-string (no regex).
- Colour: palette in `variables.R` (Okabe-Ito-based light, brighter dark variants), injected into the page as CSS custom properties by `ui.R`, so there is one source of truth.

### UI/server
- Tabs List/Map under shared Search + Stations (1–20) + an "Update my location" link. The position is read when the page connects and again on each tap of that link (`geolocation.js`, `maximumAge: 0` for taps; the link text shows "Locating…" / "Location unavailable"). The old Refresh link and `should_refetch()` are gone: the data refreshes itself every 60 s. The "you are here" marker lives in its own map pane (z 390, below the stations' overlay pane at 400) and is 44 px, so a station dot sitting on it hides only its centre and the ring still shows.
- Search is `debounce()`d 300 ms. `searching()` drives the map-fit rule and the empty-list message.
- Map: base map in `renderLeaflet`; markers via `leafletProxy` once `input$map_bounds` shows the map exists (see §12). The view re-fits only when the station set or the location changes; popups pan to stay ≥60 px from the left edge (clear of the zoom buttons).
- Marker label (bike count) is black text (≥5.4:1 on every status fill). The user marker is an SVG ring-and-dot icon so it doesn't rely on colour.

### Basemap (Esri, keyless)
- **Why:** the Carto key could no longer be restricted or rotated (the free trial ended and the user lost dashboard access) and was visible in the tile URLs of public sites; if Carto ever ended the grace period both apps' maps would break at once.
- **What:** Esri's World Light Gray and World Dark Gray canvases, each a base layer plus a labels ("Reference") layer on top. They look almost like Carto's light and dark styles, need no key or account, and swap with the dark-mode toggle. Chosen over OpenStreetMap standard (busy, no dark version, usage policy) and over a keyed provider (another account to maintain); Stadia returned tiles without a key but only because they don't enforce their terms yet.
- **Limits:** real tiles stop at zoom 16 (17+ is a grey placeholder), so requests are capped at 16 and scaled up; the automatic fit already stops at 16. No SLA, and Esri's current terms could not be verified from here. Attribution ("Tiles (c) Esri ...") is shown on the map.
- **Code:** `map_tiles_host`, `map_tile_max_native_zoom`, `map_max_zoom`, `map_attribution` in `variables.R`; `map_tile_urls()` and `add_basemap()` in `functions.R` (tested, including the attribution); CSP `img-src` in `security.R`.
- **Verified in Chrome:** both layers load from the one host, nothing is requested above zoom 16 even at map zoom 18, the attribution shows, the dark toggle swaps both layers, no CSP violations.

### Theme (youcanbeapirate brand)
- Brand colours live in `variables.R` (`brand_colours`: red `#C1272D`, lighter red `#F26B70` for dark mode, grey, dark background `#191414`), the font is Gotham from `fonts.cdnfonts.com` (as in the BiblioStatus app; a system-font stack is the fallback). The app is **light by default** (`input_dark_mode(mode = "light")`); it used to follow the OS setting.
- Brand red is 5.8:1 on white (fine for text) but only 3.1:1 on `#191414`, so dark mode links use `#F26B70` (6.2:1). `ui.R` exposes one `--fs-accent` custom property per theme for the title's first part ("Fillari", red, like the project pages' `<span>Biblio</span>Status`) and the active tab underline. Brand red is for chrome only; status colours are unchanged (the "empty" status is its own red-orange).
- Footer links to BiblioStatus, Gallery of the Day, TrackTeller, TuneTeller and the source repo; the favicon is a white bicycle on brand red.

### Security headers
- `app/www/security.R` defines the headers and `with_security_headers()`; `app/run.R` wraps the app's `httpHandler` with it (Shiny's `shiny.http.response.filter` option was tested and does nothing; wrapping `httpHandler` was tested and works, and handles NULL / plain / promised responses). Static assets don't get the headers (they don't need them).
- Enforced: `X-Frame-Options: DENY`, CSP `frame-ancestors 'none'; base-uri 'self'; object-src 'none'; form-action 'self'`, `Referrer-Policy`, `Permissions-Policy` (geolocation for self only), HSTS (1 year, no subdomains, no preload), `nosniff`. Report-only: a full CSP allowing exactly the app, `services.arcgisonline.com` (tiles) and `fonts.cdnfonts.com` (with `'unsafe-inline'`/`'unsafe-eval'` for Shiny and htmlwidgets). Verified in Chrome: no violations during real use; every host the page loaded from is on the list.
- Not exercised: the effect of enforcing the full CSP. See DEPLOY.md for how to tighten it.

### Accessibility findings (measured, not assumed)
- Status colours were simulated for protan/deutan/tritan (Machado 2009, ΔE2000): the three statuses stay distinguishable (worst: light "empty" vs "low" under deuteranopia, ΔE 12.5). The bike count is on every card and marker, so colour is never the only cue.
- **Don't darken the amber "low" colour** to reach 3:1 contrast on white: it becomes indistinguishable from "empty" for deuteranopia (ΔE 3.1 at `#C28200`, 0.5 at `#B87A00`). The bar is decorative next to the number. Only the favourite star got a darker amber (`#B87A00`, 3.6:1), since it is never compared with the status colours.
- A solid red "you are here" dot was nearly identical to the vermillion "empty" marker for deuteranopia (ΔE 1.5), hence the ring-and-dot shape.

## 7. Testing

- `testthat` 3 with the saved fixture; no live API calls. HTTP mocked with `httr2::local_mocked_responses()`. `testServer()` for the server logic with a configurable `get_stations()` mock (`mock_result`) covering ok / off-season / stale / no-data.
- 220 expectations in four files (api 30, functions 113, security 25, server 52). Covered: parsing (real fixture, bikes-only counting, empty list), missing key, GraphQL errors, stale fallback and timestamps, haversine, status thresholds, nearest + favourites rules, security headers and the handler wrapper (plain, NULL and promised responses), search, distance formatting, colour/tile/popup/icon helpers (including HTML escaping of station names), state classification, refresh rate-limit, server inputs (location, N 1–20, favourites, search, map readiness, dark mode).
- Run: `Rscript -e 'testthat::test_dir("tests/testthat", reporter = "summary")'`. Clean up the `_problems/` folder and `testthat-problems.rds` it can leave behind (both git-ignored).
- **Real-browser checks** were done by driving Chrome (the extension tools): list, map, popups, favourites, search, dark mode, the three data states (via a throwaway harness faking `get_stations()`), the container, and the live site. Not driven: Safari, Firefox, phones.
- Caveat learned: `testServer()` doesn't step `debounce()` timers for a value that was already read; tests read `searching()`/`nearest()` for the first time *after* the input change, and the live debounce was confirmed in the browser.

## 8. Deployment (as deployed)

- **GitHub Pages was considered and rejected.** Pages only hosts static files; this is an R Shiny app that needs a server process. A JS rewrite would expose the Digitransit key in the page, lose the shared cache, and discard the built and tested app.
- **Where:** Google Cloud Run, project `bibliostatus-app` (shared with BiblioStatus, as decided), region `europe-north1`, service `fillaristatus-app`, public (`--allow-unauthenticated`), 1 GiB, `--max-instances 3`, `--concurrency 20`, `--session-affinity`, timeout 3600 s. Revision `fillaristatus-app-00001-kcc` served 100 % of traffic after the first deploy.
- **Secrets:** Secret Manager `digitransit-subscription-key` (created by `deploy.sh` from `.Renviron`) exposed as an env var through `--set-secrets` (which replaces all existing secrets, so a deploy also drops the old `CARTO_API_KEY` binding; the `carto-api-key` secret itself is now disabled, both versions, because neither app uses it); the runtime service account `884476669514-compute@developer.gserviceaccount.com` has `secretAccessor`. A `github-deploy` service account already exists in the project (BiblioStatus uses it for Actions).
- **Image:** `rocker/r-ver:4.6.1` (Ubuntu 24.04), system libraries from Posit Package Manager's sysreqs API, `renv::restore()` from P3M Linux binaries, renv cache **disabled** at build, non-root user `fillari`, ~890 MB compressed in the registry (`docker image ls` shows ~3 GB unpacked). Built by Cloud Build (`gcloud builds submit`), ~7 min.
- **Deploy:** automatically through GitHub Actions on pushes to `main` that touch `app/**` or the build files (`.github/workflows/deploy_shiny_app.yml`, keyless Workload Identity login, secret `GCP_PROJECT_ID`, pinned actions, serialised runs, smoke test; the first push-triggered run and a manual run both succeeded), or by hand with `./deploy.sh` (asks for confirmation; `DRY_RUN=1` prints the plan). Locally: `docker compose up --build` → http://localhost:8083. The workflow's service account `github-deploy` is shared with BiblioStatus and has broad roles; the workflow uses a second key for it (id starts `59985cf8`); the old key must not be deleted. Workload Identity Federation (keyless) would be the more secure setup.
- **Custom domain: live.** `fillaristatus.youcanbeapirate.com` is mapped to the service (`gcloud beta run domain-mappings`), DNS at NS1 has `CNAME fillaristatus -> ghs.googlehosted.com.`. The first certificate attempt ran before the record was visible and Google backed off; deleting and recreating the mapping with DNS in place (09:21 UTC) got a certificate in ~17 minutes (issuer Google Trust Services, valid to 2027-01-15, auto-renewed). For ~2 minutes after the mapping reported Ready some TLS handshakes still failed, then 10 consecutive connections succeeded. Verified on the domain: HTTP 200, trusted certificate, all security headers, same app version as the `run.app` address, http redirects to https, map with real tiles, favourites, no Shiny errors, and no CSP violations during real use (the only ones seen came from my own `fetch()` test probe, which `connect-src` covers).
- **Project page:** `docs/` published by GitHub Pages (main, /docs) at https://youcanbeapirate.com/FillariStatus/; verified live (HTTP 200, valid certificate, identical to the repo file).
- **Repo settings (via the API):** secret scanning + push protection, Dependabot alerts + security updates, `main` protected against force-push and deletion (configuration verified; enforcement not exercised because testing it would rewrite `main`), Actions token read-only by default, actions pinned to SHAs, `dependabot.yml` for Actions and Docker.
- Observed: cold start 3.3 s, warm response ~0.24 s; Cloud Run logs clean. The only non-2xx used to be `GET /favicon.ico` 404 (44 of them, all before 08:16 UTC); revision 2 serves the favicon and has had no 404s. Revision 2 was verified in Chrome over HTTPS (icons 200, placeholder CSS live, 5 markers with real tiles, favourites, no Shiny errors).
- **Cost:** within the free tier expected; no budget alert was set up. `--min-instances 1` would remove cold starts at a small recurring cost (not applied; the user decides).

## 9. Later ideas (v2+)
- **Live location:** re-read the position on every 60 s refresh and when the tab becomes visible again, so distances follow a walking user (considered when the "My location" link was removed; one location read a minute while the page is open and permission is granted).
- **Tile robustness:** Esri has no SLA. Consider retrying failed tiles and falling back to another provider (e.g. OpenStreetMap) on tile errors. (With Carto, one live load got 8 of 9 starting-zoom tiles refused with HTTP 503, all fine moments later.) Also avoid the throwaway zoom-13 starting view (request tiles only for the fitted view).
- Revisit the tile provider if Esri's terms or availability change (alternatives in DEPLOY.md > Map tiles). Apply the same keyless switch to BiblioStatus, which still uses the unrestrictable Carto key.
- **History & patterns:** snapshot station status every 10–15 min into Turso, show "typically empty by 08:15 on weekdays". GitHub Actions cron is too unreliable at that granularity; use Cloud Scheduler → a tiny Cloud Run job.
- Walking time via Digitransit routing instead of straight-line distance.
- PWA manifest (install to home screen). The favicon (PNG + ICO bicycle on the app blue) already exists.
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
8. **README, CLAUDE.md, screenshot, favicon** — Done. Plus an MIT `LICENSE`, and a redeploy (revision 2) with the loading placeholder. The screenshot was taken from `127.0.0.1` (no location permission) so it shows the fallback position, not a real one. Still to decide with the user: GitHub Actions auto-deploy, the custom domain, making the repo public.
9. **Post-launch** — Done: GitHub Actions auto-deploy; the youcanbeapirate theme (brand red, Gotham, light by default); security headers; GitHub repository hygiene; the project page on GitHub Pages; the custom domain (live); keyless Esri map tiles replacing the Carto key (and the missing tile attribution fixed).

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
| Redeploy timing | Batched with Milestone 8 (done: revision 2) |
| Licence | MIT, copyright 2026 Antti Rask (same as BiblioStatus apart from the year) |
| Map tiles | Esri World Light/Dark Gray + labels, keyless (the Carto key could not be restricted or rotated any more) |
| Theme | youcanbeapirate brand red, Gotham (as the BiblioStatus app), **light by default**, lighter red links in dark mode, status colours unchanged |
| Security headers | Wrap the page handler (enforced framing/referrer/permissions/HSTS + report-only CSP) |
| GitHub hygiene | Secret scanning, push protection, Dependabot, protected `main`, SHA-pinned actions |
| "My location" link | Removed (it did nothing visible when the position hadn't changed, jumped the page to the top, and re-asking after a denial doesn't work in most browsers). The position was read once per page load. **Replaced on 2026-10-18** by an "Update my location" link that really re-reads the position (user feedback after riding: the app didn't know they had moved); it also replaced the Refresh link, since the data refreshes every 60 s anyway. |
| Project page | Yes: `docs/` on GitHub Pages, plus a card on the main site (both done) |
| Deploy credential | Superseded 2026-10-18: keyless Workload Identity Federation (pool `github`, provider `github-oidc`, only the FillariStatus and BiblioStatus repos) acting as `github-deploy`; both stored keys deleted. Runtime now `fillaristatus-runtime` (reads only the Digitransit secret); the default compute account lost `roles/editor` (keeps `cloudbuild.builds.builder`). A new IAM binding can take minutes to work: a first run failed with `getAccessToken denied` and a rerun passed. Billing budget alert: EUR 30/month (50/90/100 %) |

## 12. Conventions and lessons learned

### Conventions
- R, tidyverse style (`|>`, `dplyr`, `purrr`, `tidyr`, `stringr`), `renv`. Config (thresholds, colours, defaults, map settings) in `variables.R`; all UI text in `strings.R`.
- Small commits tied to milestones; after every commit/push verify the remote (`git ls-remote origin refs/heads/main` equals `HEAD`). Never suppress errors in scripts that call GitHub/GCP APIs.
- **Pushes to `main` that touch `app/**`, `Dockerfile`, `.dockerignore`, `renv.lock`, `.Rprofile` or `renv/activate.R|settings.json` deploy automatically.** Run the tests first, batch app changes into one push, and confirm the run from GitHub. Docs/tests/plan-only pushes don't deploy (checked).
- Show the user the running app after every visible change (`PORT=8083 Rscript app/run.R`; stop it by port, never `pkill -f app/run.R`, which also matches BiblioStatus' container).
- When something fails: read the full error, find the root cause, explain it, propose 2–3 ranked fixes, implement the top one; don't retry the same thing.

### Gotchas that cost time

- **Cloud Run `--concurrency` must exceed the number of parallel asset requests one page load makes.** BiblioStatus (about 25 JS/CSS files) was set to 20 in a hardening pass; the overflow requests were routed to freshly started instances, which answer **404 for Shiny's asset paths** (they are registered per instance), so the page came up blank or stuck on "Loading data". Back at 80 it was fine. Diagnose with Cloud Logging: group `httpRequest.status` by `labels.instanceId`; the 404s come from instances that never served the page. FillariStatus (fewer assets) runs at 20 with no 404s; re-check if its asset count grows.

- **Leaflet draws icon markers (markerPane, z 600) above circle markers (overlayPane, z 400)**, so a "you are here" icon covers a station dot however you order the `add*` calls. Put it in its own pane below 400 (`addMapPane("me", 390)` on the base map, `pane = "me"` in `markerOptions()`), and make the ring bigger than a station disc or it vanishes completely when the two coincide.
- **Tile providers answer HTTP 200 with placeholders.** Carto without a key: a ~2 KB "API KEY REQUIRED" watermark; Esri above zoom 16: an identical grey "Map data not yet available" tile (z17 and z18 are byte-identical). Check tile content/size, never just the status.
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
- **`addTiles()` silently drops an attribution passed through `tileOptions()`** (it runs `options$attribution <- attribution`). The tile credit was therefore missing from the map from the start; found while switching providers and fixed (`add_basemap()` + a test). Esri's tile URLs are `{z}/{y}/{x}`.
- **A key that can't be restricted or rotated is a liability.** The Carto trial ended, the dashboard became unreachable, and its key was visible in the tile URLs of public sites: the app switched to keyless Esri tiles.
- **Shiny has no response-header hook** (`shiny.http.response.filter` does nothing): wrap `app$httpHandler` (`app/www/security.R`, `app/run.R`).
- **The Chrome console tool does not capture CSP report-only violations.** Use a `securitypolicyviolation` listener in the page and prove it catches a deliberate probe first; also list the hosts from `performance.getEntriesByType('resource')`.
- **Geolocation permission can silently differ per loopback origin** (127.0.0.1 vs 127.0.0.2). Screenshots for the repo must force the fallback position with `Shiny.setInputValue('user_location', ...)`, be checked (first station Mannerheimintie, 42 m), and the raw captures deleted. One capture showed the user's real neighbourhood and was discarded.
- **zsh does not word-split unquoted variables**; shell snippets that loop over `"repo tag"` strings broke. Use explicit arguments or arrays.
- **`docker image ls` shows the unpacked size (~3 GB)**; the registry's compressed size (~890 MB) is what Cloud Run pulls. A background task's "exit code 0" can be the exit code of a pipe; read the real result (`gh run view`, the log's last line, the registry).
- **Custom-domain certificates:** if issuance stays pending after DNS is right, delete and recreate the mapping with the record in place to reset Google's retry back-off. After the mapping reports Ready, handshakes can fail for a minute or two while the front ends pick the certificate up: require many consecutive successes (and test with fresh connections) before calling it live.
- **A CSP probe can cause its own violations:** `fetch()` is governed by `connect-src`, so a test script that fetches tile URLs to measure them produces report-only violations that real use does not. Separate the listener's findings from the probe's.
- **Platform lag:** GitHub's Dependabot status and Google's certificate state lag behind the API call that changed them; re-check before concluding something failed. `--dry-run` on `git push` does not test server-side branch protection.

- **HTML edits: check the nesting, not the text.** Moving the FillariStatus card on the main site nested it (and the cards after it) inside the BiblioStatus card, and "same lines, balanced tags, titles in order" all passed, because those checks cannot see a misplaced closing tag. Two causes: the end of the card was found by searching for the first `</div>` indented 16 spaces, which also matches *inside* the 20-space line of the inner links div; and the check was blind to structure. Find block boundaries by counting `<div>`/`</div>` depth, and verify with a parser that every card is a *direct child of the grid* (and then look at the rendered page). The fix was one `</div>` (`0ace6b2`).
- **`isTRUE(x)` can silently turn a feature into a no-op.** BiblioStatus' map dark mode died when `if (input$dark_mode)` (which errored on bslib's string value) was wrapped in `isTRUE()`; the author later called the input "unreliable" and fixed only the chart. When silencing an error, check what the value actually is.
- **BiblioStatus' startup can stall on "Loading data, please wait"** when its `shiny:sessioninitialized` handler doesn't run (seen locally with geolocation in the "prompt" state, and once on the live site right after a deploy; three reloads in a row then started fine). Not caused by the tile change; worth watching.
- **Don't grep secret files.** A search that matched `~/VSCode/BiblioStatus/app/secret.R` printed the old Carto key into the session output; exclude secret files from searches.
- **Pull before editing a repo that a bot commits to:** the local BiblioStatus checkout was 18 data-refresh commits behind.
- **BiblioStatus deploys take ~35 minutes** (its image compiles the R packages from source) and its workflow only runs after the nightly data job or on demand (`gh workflow run deploy_shiny_app.yml`); it has no concurrency guard, so don't start two at once.

- **`<a href="#">` used as a button jumps the page to the top** (and leaves a stray `#` in the URL) unless the handler calls `preventDefault`. The old "My location" link did exactly that, which is one reason it was removed. Use a real button or `actionLink` for actions.

## 13. Next steps (in order)
The app, the project page, automatic deploys and the security work are done and live. What remains:
1. ~~Custom domain~~ done (live, see §8). The README and the project page already point at it.
2. ~~Main-site card~~ done (live on youcanbeapirate.com).
3. ~~Restrict the Carto key~~ not needed any more: neither app uses it (see §0 for the optional clean-up of the unused secrets).
4. Optional hardening: Workload Identity Federation with a dedicated least-privilege service account (then delete the new key `59985cf8…`, never the old BiblioStatus one); tighten the report-only CSP into an enforced one; a Cloud Billing budget alert; image/package vulnerability scanning; a test job in the workflow that gates deploys.
5. v2 candidates from §9: tile retry/fallback, history/patterns, walking time, PWA, Finnish UI; optionally `--min-instances 1`.
6. Still unverified: phones and non-Chrome browsers, the pinned-light default on a machine set to dark mode, a real season change, and whether the intermittent empty map box (reported once, in a non-Chrome desktop browser) still occurs now that a placeholder is shown.
