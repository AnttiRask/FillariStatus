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
