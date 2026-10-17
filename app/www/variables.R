## Config: thresholds, colours, refresh interval, N nearest

digitransit_endpoint <- "https://api.digitransit.fi/routing/v2/hsl/gtfs/v1"

refresh_ms <- 60 * 1000
cache_max_age_s <- 60
default_n_nearest <- 5L

# Counts at or below these thresholds are classified as empty / low
status_thresholds <- list(
    empty_max = 0L,
    low_max   = 2L
)

# Okabe-Ito based, colour-blind friendly. `unknown` is for missing data and
# `me` marks the user's own location.
status_colours <- list(
    light = list(
        empty = "#D55E00", low = "#E69F00", plenty = "#009E73",
        unknown = "#999999", me = "#FF0000"
    ),
    dark  = list(
        empty = "#FF4444", low = "#FFD700", plenty = "#00D9A0",
        unknown = "#BBBBBB", me = "#FF0000"
    )
)

# Map
map_default_zoom <- 13
map_marker_radius <- 14
map_user_marker_radius <- 8
map_max_fit_zoom <- 16
carto_attribution <- paste0(
    '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors ',
    '&copy; <a href="https://carto.com/attributions">CARTO</a>'
)

# Used until (or unless) the browser shares its location: Rautatientori
default_location <- list(lat = 60.1699, lon = 24.9384)

n_choices <- 1:20

# Manual refresh won't re-fetch if the cached data is younger than this
min_manual_refresh_s <- 10
