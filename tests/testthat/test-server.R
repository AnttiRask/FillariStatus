library(shiny)
library(leaflet)

# Server logic against the saved fixture; get_stations() is mocked so no
# live API call is made
server_env <- new.env(parent = globalenv())
for (f in c("variables", "strings", "api", "functions")) {
    sys.source(here::here("app/www", paste0(f, ".R")), envir = server_env)
}
# Mirror what global.R provides
server_env$carto_api_key <- ""
# The test blocks below are evaluated in this file's environment, so bring in
# the helpers they call directly instead of relying on other test files
haversine_m <- server_env$haversine_m
default_location <- server_env$default_location

fixture_body <- jsonlite::read_json(
    here::here("tests/testthat/fixtures/stations.json"),
    simplifyVector = FALSE
)
fixture_stations <- server_env$parse_stations(fixture_body)
server_env$get_stations <- function() {
    list(data = fixture_stations, stale = FALSE, error = NULL, fetched_at = Sys.time())
}
server_fn <- source(here::here("app/server.R"), local = server_env)$value

test_that("defaults to 5 stations and the fallback location", {
    testServer(server_fn, {
        session$flushReact()
        expect_false(has_location())
        expect_equal(location(), default_location)
        expect_equal(nrow(nearest()), 5)
    })
})

test_that("uses the browser location and the selected n", {
    testServer(server_fn, {
        session$setInputs(
            user_location = list(lat = 60.2, lon = 24.95, accuracy = 20), n = "3"
        )
        expect_true(has_location())
        out <- nearest()
        expect_equal(nrow(out), 3)
        expect_equal(
            out$distance_m,
            haversine_m(60.2, 24.95, out$lat, out$lon)
        )
        expect_false(is.unsorted(out$distance_m))
    })
})

test_that("favourites from the browser are pinned, an empty list is fine", {
    testServer(server_fn, {
        far <- fixture_stations$station_id[which.max(fixture_stations$lat)]
        session$setInputs(favourites = far)
        expect_equal(favourites(), far)
        expect_equal(nearest()$station_id[1], far)
        expect_equal(nrow(nearest()), 6)

        session$setInputs(favourites = list())
        expect_equal(favourites(), character())
        expect_equal(nrow(nearest()), 5)
    })
})

test_that("n can be anywhere from 1 to 20", {
    testServer(server_fn, {
        session$setInputs(n = "1")
        expect_equal(nrow(nearest()), 1)
        session$setInputs(n = "20")
        expect_equal(nrow(nearest()), 20)
    })
})

test_that("a search overrides the nearest list, even with a location", {
    testServer(server_fn, {
        session$setInputs(user_location = list(lat = 60.17, lon = 24.94))
        expect_equal(nrow(nearest()), 5)

        session$setInputs(search = "Kamppi")
        session$elapse(500)
        out <- nearest()
        expect_gt(nrow(out), 0)
        expect_true(all(grepl("kamppi", out$name, ignore.case = TRUE)))
        # still measured from the user's location
        expect_equal(out$distance_m, haversine_m(60.17, 24.94, out$lat, out$lon))
        expect_false(is.unsorted(out$distance_m))
    })
})

test_that("emptying the search restores the location-based list", {
    testServer(server_fn, {
        session$setInputs(user_location = list(lat = 60.17, lon = 24.94))
        session$setInputs(search = "Kamppi")
        session$elapse(500)
        searched <- nearest()

        session$setInputs(search = "")
        session$elapse(500)
        expect_equal(nrow(nearest()), 5)
        expect_false(identical(nearest()$station_id, searched$station_id))

        session$setInputs(search = "   ")
        session$elapse(500)
        expect_equal(nrow(nearest()), 5)
    })
})

test_that("a search with no matches gives an empty list", {
    testServer(server_fn, {
        session$setInputs(search = "zzzz-no-such-station")
        session$elapse(500)
        expect_equal(nrow(nearest()), 0)
    })
})

test_that("markers are only drawn once leaflet reports the map exists", {
    testServer(server_fn, {
        session$flushReact()
        expect_false(map_ready())
        expect_null(last_fit())

        session$setInputs(map_bounds = list(north = 60.2, east = 25, south = 60.1, west = 24.9))
        session$flushReact()
        expect_true(map_ready())
        # The first draw fitted the view to the stations
        expect_false(is.null(last_fit()))
    })
})

test_that("the map code path runs for tab, dark mode and location changes", {
    testServer(server_fn, {
        session$setInputs(
            map_bounds = list(north = 60.2, east = 25, south = 60.1, west = 24.9)
        )
        session$setInputs(tab = "map", dark_mode = "dark")
        expect_true(is_dark())
        session$setInputs(user_location = list(lat = 60.17, lon = 24.94))
        session$setInputs(search = "zzzz-no-such-station")
        session$elapse(500)
        session$setInputs(dark_mode = "light", tab = "list")
        session$flushReact() # run the tile/marker observers before teardown
        expect_false(is_dark())
        expect_equal(nrow(nearest()), 0)
    })
})

# testServer doesn't step debounce timers for a value that was already read,
# so each case reads searching() for the first time after the input changes.
# (The live debounce behaviour was checked in a browser.)
test_that("searching is true for a non-blank search", {
    testServer(server_fn, {
        session$setInputs(search = "Kamppi")
        session$elapse(500)
        expect_true(searching())
    })
})

test_that("searching is false for no search and for blank input", {
    testServer(server_fn, {
        session$flushReact()
        expect_false(searching())
    })
    testServer(server_fn, {
        session$setInputs(search = "   ")
        session$elapse(500)
        expect_false(searching())
    })
})
