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

    # Favourites are always shown, pinned first, in addition to the n nearest
    dplyr::bind_rows(
        dplyr::filter(ranked, .data$favourite),
        dplyr::filter(ranked, !.data$favourite) |> dplyr::slice_head(n = n)
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

# Popup content for one station row; mirrors the list card. All text goes
# through htmltools so station names are escaped.
station_popup <- function(station, strings) {
    bikes_label <- if (station$bikes == 1) strings$bike_one else strings$bike_many
    as.character(htmltools::tags$div(
        htmltools::tags$strong(station_title(station$name, station$station_id)),
        htmltools::tags$br(),
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
