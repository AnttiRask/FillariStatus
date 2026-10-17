## Logic: distance, status classification, sorting

haversine_m <- function(lat1, lon1, lat2, lon2) {
    r <- 6371000
    to_rad <- pi / 180
    dlat <- (lat2 - lat1) * to_rad
    dlon <- (lon2 - lon1) * to_rad
    a <- sin(dlat / 2)^2 +
        cos(lat1 * to_rad) * cos(lat2 * to_rad) * sin(dlon / 2)^2
    2 * r * asin(pmin(1, sqrt(a)))
}

classify_status <- function(n) {
    dplyr::case_when(
        is.na(n)                          ~ NA_character_,
        n <= status_thresholds$empty_max  ~ "empty",
        n <= status_thresholds$low_max    ~ "low",
        .default = "plenty"
    )
}

# "smoove:077" -> "077", the number printed on the physical station
station_number <- function(station_id) {
    stringr::str_remove(station_id, "^[^:]*:")
}

nearest_stations <- function(
    stations,
    user_lat,
    user_lon,
    n = default_n_nearest,
    favourites = character()
) {
    ranked <- stations |>
        dplyr::filter(
            dplyr::coalesce(.data$operative, TRUE),
            dplyr::coalesce(.data$allow_pickup, TRUE)
        ) |>
        dplyr::mutate(
            distance_m = haversine_m(user_lat, user_lon, .data$lat, .data$lon),
            status     = classify_status(.data$bikes),
            favourite  = .data$station_id %in% favourites
        ) |>
        dplyr::arrange(.data$distance_m)

    # The n nearest stations, plus any favourites outside them; favourites are
    # pinned first. A favourite within the n nearest takes one of the n slots.
    dplyr::bind_rows(
        dplyr::filter(ranked, .data$favourite),
        dplyr::slice_head(ranked, n = n) |> dplyr::filter(!.data$favourite)
    )
}

# Matches the station name or its number; a blank query keeps everything
filter_by_name <- function(stations, query) {
    query <- stringr::str_squish(query %||% "")
    if (!nzchar(query)) {
        return(stations)
    }
    haystack <- paste(stations$name, station_number(stations$station_id))
    dplyr::filter(
        stations,
        stringr::str_detect(
            stringr::str_to_lower(haystack),
            stringr::fixed(stringr::str_to_lower(query))
        )
    )
}

# Whole metres below 1 km, kilometres with two decimals (decimal comma) from
# 1 km up, e.g. 642 -> "642 m", 1636 -> "1,64 km". Rounds first so 999.6 m
# becomes "1,00 km" rather than "1000 m".
format_distance <- function(metres) {
    metres <- round(metres)
    dplyr::if_else(
        metres < 1000,
        paste0(metres, " m"),
        paste0(format(round(metres / 1000, 2), nsmall = 2, decimal.mark = ","), " km")
    )
}

directions_url <- function(lat, lon) {
    sprintf(
        "https://www.google.com/maps/dir/?api=1&destination=%s,%s&travelmode=walking",
        lat, lon
    )
}

# "Name (077)"
station_title <- function(name, station_id) {
    paste0(name, " (", station_number(station_id), ")")
}

# Colour for a status ("empty" / "low" / "plenty" / NA) in light or dark mode
status_colour <- function(status, dark = FALSE) {
    palette <- if (dark) status_colours$dark else status_colours$light
    out <- unlist(palette[status])
    out[is.na(status) | !status %in% c("empty", "low", "plenty")] <- palette$unknown
    unname(out)
}

# Basemap tile URL template; the key is only appended when one is configured
carto_tile_url <- function(dark = FALSE, key = "") {
    url <- paste0(
        "https://{s}.basemaps.cartocdn.com/",
        if (dark) "dark_all" else "light_all",
        "/{z}/{x}/{y}{r}.png"
    )
    if (nzchar(key)) paste0(url, "?key=", key) else url
}

# The favourite star, used on list cards and in map popups. favourites.js
# handles the click for every `.fs-fav` button.
favourite_button <- function(station_id, favourite, strings) {
    htmltools::tags$button(
        type = "button",
        class = paste("fs-fav", if (favourite) "is-fav"),
        `data-station-id` = station_id,
        `aria-pressed` = tolower(favourite),
        `aria-label` = if (favourite) strings$fav_remove else strings$fav_add,
        if (favourite) "\u2605" else "\u2606"
    )
}

# Popup content for one station row; mirrors the list card. All text goes
# through htmltools so station names are escaped.
station_popup <- function(station, strings) {
    bikes_label <- if (station$bikes == 1) strings$bike_one else strings$bike_many
    as.character(htmltools::tags$div(
        htmltools::tags$div(
            favourite_button(station$station_id, station$favourite, strings),
            htmltools::tags$strong(station_title(station$name, station$station_id))
        ),
        format_distance(station$distance_m),
        htmltools::tags$br(),
        paste(station$bikes, bikes_label),
        htmltools::tags$br(),
        htmltools::tags$a(
            href = directions_url(station$lat, station$lon),
            target = "_blank",
            rel = "noopener",
            strings$directions
        )
    ))
}

# What the app should show for a get_stations() result:
#   "ok"         stations to show
#   "off_season" no stations (the bike season is over), not an error
#   "stale"      the latest refresh failed, showing older data
#   "error"      the fetch failed and there is no data at all
stations_state <- function(res) {
    if (is.null(res$data)) {
        return("error")
    }
    if (nrow(res$data) == 0) {
        return("off_season")
    }
    if (!is.null(res$error)) "stale" else "ok"
}

# 45 -> "45 s", 400 -> "6 min", 7300 -> "2 h"
format_age <- function(seconds) {
    seconds <- max(0, as.integer(seconds))
    dplyr::case_when(
        seconds < 60   ~ paste(seconds, "s"),
        seconds < 3600 ~ paste(seconds %/% 60, "min"),
        .default       = paste(seconds %/% 3600, "h")
    )
}

# Whether a manual refresh may re-fetch, given when the cache last *tried* to
# (successfully or not)
should_refetch <- function(attempted_at, now = Sys.time(), min_age = min_manual_refresh_s) {
    is.null(attempted_at) ||
        as.numeric(difftime(now, attempted_at, units = "secs")) >= min_age
}

# The "you are here" marker: a red ring with a centre dot and a white halo. Its
# shape (not just its colour) sets it apart from the numbered station discs;
# the red alone is too close to the "empty" colour for some colour-blind users.
me_icon_svg <- function(colour = status_colours$light$me) {
    sprintf(
        paste0(
            '<svg xmlns="http://www.w3.org/2000/svg" width="28" height="28" viewBox="0 0 28 28">',
            '<circle cx="14" cy="14" r="13" fill="#FFFFFF" fill-opacity="0.9"/>',
            '<circle cx="14" cy="14" r="8.5" fill="#FFFFFF" stroke="%1$s" stroke-width="4"/>',
            '<circle cx="14" cy="14" r="3.5" fill="%1$s"/>',
            '</svg>'
        ),
        colour
    )
}

me_icon <- function(colour = status_colours$light$me) {
    leaflet::makeIcon(
        iconUrl = paste0(
            "data:image/svg+xml;utf8,",
            utils::URLencode(me_icon_svg(colour), reserved = TRUE)
        ),
        iconWidth = 28, iconHeight = 28,
        iconAnchorX = 14, iconAnchorY = 14
    )
}
