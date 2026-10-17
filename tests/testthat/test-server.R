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

test_that("defaults to bike mode, 5 stations, fallback location", {
    testServer(server_fn, {
        session$flushReact()
        expect_false(has_location())
        expect_equal(location(), default_location)
        expect_equal(nrow(nearest()), 5)
        expect_equal(mode(), "bike")
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

test_that("dock mode counts docks", {
    testServer(server_fn, {
        session$setInputs(mode = "dock")
        out <- nearest()
        expect_equal(out$count, out$docks)
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

test_that("search only applies while location is unavailable", {
    testServer(server_fn, {
        session$setInputs(location_error = list(code = 1), search = "Kamppi")
        out <- nearest()
        expect_gt(nrow(out), 0)
        expect_true(all(grepl("kamppi", out$name, ignore.case = TRUE)))

        session$setInputs(user_location = list(lat = 60.17, lon = 24.94))
        expect_equal(nrow(nearest()), 5)
    })
})
