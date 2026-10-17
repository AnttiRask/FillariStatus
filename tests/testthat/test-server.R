library(shiny)

# Server logic against the saved fixture; get_stations() is mocked so no
# live API call is made
server_env <- new.env(parent = globalenv())
for (f in c("variables", "strings", "api", "functions")) {
    sys.source(here::here("app/www", paste0(f, ".R")), envir = server_env)
}
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
