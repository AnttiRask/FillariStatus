## Digitransit API: build query, call, parse to tibble

stations_query <- "{
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
    availableVehicles { total byType { count vehicleType { formFactor } } }
    availableSpaces { total }
  }
}"

station_cols <- c(
    station_id = "character", name = "character", lat = "double",
    lon = "double", capacity = "integer", bikes = "integer", docks = "integer",
    allow_pickup = "logical", allow_dropoff = "logical",
    operative = "logical", network_id = "character"
)

empty_stations <- function() {
    purrr::map(station_cols, ~ vector(.x, 0)) |>
        tibble::as_tibble()
}

fetch_stations_raw <- function(
    key = Sys.getenv("DIGITRANSIT_SUBSCRIPTION_KEY"),
    endpoint = digitransit_endpoint
) {
    if (!nzchar(key)) {
        stop("DIGITRANSIT_SUBSCRIPTION_KEY is not set", call. = FALSE)
    }

    resp <- httr2::request(endpoint) |>
        httr2::req_headers("digitransit-subscription-key" = key) |>
        httr2::req_body_json(list(query = stations_query)) |>
        httr2::req_timeout(10) |>
        httr2::req_retry(max_tries = 2) |>
        httr2::req_perform()

    body <- httr2::resp_body_json(resp)

    if (!is.null(body$errors)) {
        msg <- purrr::map_chr(body$errors, "message") |> paste(collapse = "; ")
        stop("Digitransit GraphQL error: ", msg, call. = FALSE)
    }
    body
}

# `body` is the parsed JSON (lists, not simplified). An empty station list
# (off-season) gives a zero-row tibble, which is not an error.
parse_stations <- function(body) {
    stations <- body$data$vehicleRentalStations
    if (length(stations) == 0) {
        return(empty_stations())
    }

    count_bikes <- function(x) {
        x$availableVehicles$byType |>
            purrr::keep(~ identical(.x$vehicleType$formFactor, "BICYCLE")) |>
            purrr::map_int(~ as.integer(.x$count)) |>
            sum()
    }

    purrr::map(stations, \(s) {
        tibble::tibble(
            station_id    = s$stationId %||% NA_character_,
            name          = s$name %||% NA_character_,
            lat           = as.numeric(s$lat %||% NA_real_),
            lon           = as.numeric(s$lon %||% NA_real_),
            capacity      = as.integer(s$capacity %||% NA_integer_),
            bikes         = count_bikes(s),
            # availableSpaces.byType is empty in the live API; use total
            docks         = as.integer(s$availableSpaces$total %||% NA_integer_),
            allow_pickup  = s$allowPickup %||% NA,
            allow_dropoff = s$allowDropoff %||% NA,
            operative     = s$operative %||% NA,
            network_id    = s$rentalNetwork$networkId %||% NA_character_
        )
    }) |>
        dplyr::bind_rows()
}

# Last successful result, so a failed refresh can fall back to stale data
.last_good <- new.env(parent = emptyenv())

# Returns list(data, stale, error, fetched_at); never throws.
# `data` is NULL only if there has never been a successful fetch.
fetch_stations_safe <- function(fetch = fetch_stations_raw) {
    tryCatch(
        {
            data <- fetch() |> parse_stations()
            res <- list(
                data = data, stale = FALSE, error = NULL, fetched_at = Sys.time()
            )
            .last_good$value <- res
            res
        },
        error = function(e) {
            prev <- .last_good$value
            list(
                data       = prev$data,
                stale      = !is.null(prev),
                error      = conditionMessage(e),
                fetched_at = prev$fetched_at
            )
        }
    )
}

# Shared by all sessions; one upstream call per cache window
get_stations <- memoise::memoise(
    function() fetch_stations_safe(),
    cache = cachem::cache_mem(max_age = cache_max_age_s)
)
