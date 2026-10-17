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

classify_status <- function(n, mode = c("bike", "dock")) {
    mode <- match.arg(mode)
    dplyr::case_when(
        is.na(n)                          ~ NA_character_,
        n <= status_thresholds$empty_max  ~ "empty",
        n <= status_thresholds$low_max    ~ "low",
        .default = "plenty"
    )
}

nearest_stations <- function(
    stations,
    user_lat,
    user_lon,
    n = default_n_nearest,
    mode = c("bike", "dock"),
    favourites = character()
) {
    mode <- match.arg(mode)
    count_col <- if (mode == "bike") "bikes" else "docks"
    allow_col <- if (mode == "bike") "allow_pickup" else "allow_dropoff"

    ranked <- stations |>
        dplyr::filter(
            dplyr::coalesce(.data$operative, TRUE),
            dplyr::coalesce(.data[[allow_col]], TRUE)
        ) |>
        dplyr::mutate(
            distance_m = haversine_m(user_lat, user_lon, .data$lat, .data$lon),
            count      = .data[[count_col]],
            status     = classify_status(.data$count, mode),
            favourite  = .data$station_id %in% favourites
        ) |>
        dplyr::arrange(.data$distance_m)

    # Favourites are always shown, pinned first, in addition to the n nearest
    dplyr::bind_rows(
        dplyr::filter(ranked, .data$favourite),
        dplyr::filter(ranked, !.data$favourite) |> dplyr::slice_head(n = n)
    )
}

filter_by_name <- function(stations, query) {
    query <- stringr::str_squish(query %||% "")
    if (!nzchar(query)) {
        return(stations)
    }
    dplyr::filter(
        stations,
        stringr::str_detect(
            stringr::str_to_lower(.data$name),
            stringr::fixed(stringr::str_to_lower(query))
        )
    )
}
