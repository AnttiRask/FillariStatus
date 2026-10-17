source(here::here("app/www/variables.R"))
source(here::here("app/www/api.R"))

fixture <- function() {
    jsonlite::read_json(
        here::here("tests/testthat/fixtures/stations.json"),
        simplifyVector = FALSE
    )
}

reset_last_good <- function() rm(list = ls(.last_good), envir = .last_good)

test_that("parse_stations parses the real fixture", {
    out <- parse_stations(fixture())

    expect_s3_class(out, "tbl_df")
    expect_named(out, names(station_cols))
    expect_equal(nrow(out), length(fixture()$data$vehicleRentalStations))
    expect_false(anyDuplicated(out$station_id) > 0)
    expect_true(all(out$bikes >= 0 & out$docks >= 0))
    expect_true(all(out$network_id == "smoove"))
    expect_equal(
        vapply(out, \(x) class(x)[1], character(1)) |> unname(),
        c("character", "character", "numeric", "numeric", "integer",
          "integer", "integer", "logical", "logical", "logical", "character")
    )
})

test_that("docks come from availableSpaces.total, bikes from BICYCLE counts", {
    out <- parse_stations(fixture())
    row <- out[out$station_id == "smoove:900", ]
    expect_equal(row$bikes, 15L)
    expect_equal(row$docks, 5L)
})

test_that("non-bicycle vehicles are not counted as bikes", {
    body <- list(data = list(vehicleRentalStations = list(list(
        stationId = "x:1", name = "X", lat = 60, lon = 24,
        availableVehicles = list(byType = list(
            list(count = 3, vehicleType = list(formFactor = "BICYCLE")),
            list(count = 4, vehicleType = list(formFactor = "SCOOTER"))
        )),
        availableSpaces = list(total = 2)
    ))))
    expect_equal(parse_stations(body)$bikes, 3L)
})

test_that("an empty station list is off-season, not an error", {
    out <- parse_stations(list(data = list(vehicleRentalStations = list())))
    expect_equal(nrow(out), 0)
    expect_named(out, names(station_cols))
})

test_that("fetch_stations_raw errors without a key", {
    expect_error(fetch_stations_raw(key = ""), "not set")
})

test_that("fetch_stations_raw sends the key and parses the response", {
    httr2::local_mocked_responses(function(req) {
        expect_equal(
            req$headers[["digitransit-subscription-key"]], "test-key"
        )
        httr2::response_json(body = fixture())
    })
    body <- fetch_stations_raw(key = "test-key")
    expect_gt(nrow(parse_stations(body)), 0)
})

test_that("GraphQL errors are surfaced", {
    httr2::local_mocked_responses(function(req) {
        httr2::response_json(body = list(errors = list(list(message = "boom"))))
    })
    expect_error(fetch_stations_raw(key = "k"), "boom")
})

test_that("an API error falls back to the last good data", {
    reset_last_good()
    good <- fetch_stations_safe(fetch = fixture)
    expect_false(good$stale)
    expect_null(good$error)

    bad <- fetch_stations_safe(fetch = function() stop("network down"))
    expect_true(bad$stale)
    expect_equal(bad$error, "network down")
    expect_equal(bad$data, good$data)
})

test_that("an API error with no prior data returns NULL data", {
    reset_last_good()
    bad <- fetch_stations_safe(fetch = function() stop("network down"))
    expect_false(bad$stale)
    expect_null(bad$data)
    expect_equal(bad$error, "network down")
})
