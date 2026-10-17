source(here::here("app/www/variables.R"))
source(here::here("app/www/functions.R"))
library(stringr)

stations_tbl <- tibble::tibble(
    station_id     = c("a", "b", "c", "d"),
    name           = c("A", "B", "C", "D"),
    lat            = c(60.1710, 60.1690, 60.1700, 60.2000),
    lon            = c(24.9400, 24.9300, 24.9380, 24.9500),
    bikes          = c(0L, 2L, 10L, 5L),
    docks          = c(5L, 0L, 3L, 4L),
    allow_pickup   = c(TRUE, TRUE, TRUE, TRUE),
    allow_dropoff  = c(TRUE, TRUE, TRUE, FALSE),
    operative      = c(TRUE, TRUE, TRUE, TRUE)
)

test_that("haversine_m matches a known distance", {
    # Rautatientori -> Kamppi is roughly 1 km
    d <- haversine_m(60.1710, 24.9440, 60.1685, 24.9315)
    expect_gt(d, 600)
    expect_lt(d, 1200)
    expect_equal(haversine_m(60, 24, 60, 24), 0)
})

test_that("classify_status applies thresholds", {
    expect_equal(
        classify_status(c(0, 1, 2, 3, 20)),
        c("empty", "low", "low", "plenty", "plenty")
    )
    expect_equal(classify_status(NA_integer_), NA_character_)
})

test_that("nearest_stations sorts by distance and respects n", {
    out <- nearest_stations(stations_tbl, 60.1702, 24.9385, n = 2)
    expect_equal(nrow(out), 2)
    expect_true(all(out$distance_m > 0))
    expect_false(is.unsorted(out$distance_m))
    # Stations are measured from the user, not from themselves
    expect_equal(
        out$distance_m,
        haversine_m(60.1702, 24.9385, out$lat, out$lon)
    )
    expect_equal(out$station_id, c("c", "a"))
})

test_that("nearest_stations pins favourites first", {
    out <- nearest_stations(
        stations_tbl, 60.1705, 24.9390, n = 4, favourites = "d"
    )
    expect_equal(out$station_id[1], "d")
    expect_true(out$favourite[1])
})

test_that("favourites are shown in addition to the n nearest", {
    out <- nearest_stations(
        stations_tbl, 60.1702, 24.9385, n = 1, favourites = "b"
    )
    # The favourite (b) is kept even though it is far; plus the 1 nearest (c)
    expect_equal(out$station_id, c("b", "c"))
    expect_equal(out$favourite, c(TRUE, FALSE))
})

test_that("a favourite is not duplicated when it is also nearest", {
    out <- nearest_stations(
        stations_tbl, 60.1702, 24.9385, n = 2, favourites = "c"
    )
    expect_equal(anyDuplicated(out$station_id), 0)
    expect_equal(out$station_id[1], "c")
    expect_equal(nrow(out), 3)
})

test_that("filter_by_name matches case-insensitively and ignores blanks", {
    st <- tibble::tibble(
        station_id = c("smoove:077", "smoove:102", "smoove:230"),
        name = c("Kamppi", "Kiasma", "Töölö")
    )
    expect_equal(filter_by_name(st, "kam")$name, "Kamppi")
    expect_equal(filter_by_name(st, "  K ")$name, c("Kamppi", "Kiasma"))
    expect_equal(filter_by_name(st, "TÖÖ")$name, "Töölö")
    expect_equal(nrow(filter_by_name(st, "")), 3)
    expect_equal(nrow(filter_by_name(st, NULL)), 3)
    expect_equal(nrow(filter_by_name(st, "(")), 0)
    # Matches the station number too, but not the network prefix
    expect_equal(filter_by_name(st, "230")$name, "Töölö")
    expect_equal(nrow(filter_by_name(st, "smoove")), 0)
})

test_that("station_number drops the network prefix", {
    expect_equal(station_number(c("smoove:077", "smoove:900")), c("077", "900"))
    expect_equal(station_number("123"), "123")
})

test_that("format_distance uses m below 1 km and km with a decimal comma above", {
    expect_equal(format_distance(0), "0 m")
    expect_equal(format_distance(41.9), "42 m")
    expect_equal(format_distance(999.4), "999 m")
    expect_equal(format_distance(999.6), "1,00 km")
    expect_equal(format_distance(1000), "1,00 km")
    expect_equal(format_distance(1636), "1,64 km")
    expect_equal(format_distance(1600), "1,60 km")
    expect_equal(format_distance(12345), "12,35 km")
    expect_equal(
        format_distance(c(250, 1636)),
        c("250 m", "1,64 km")
    )
})

test_that("station_title and directions_url", {
    expect_equal(station_title("Kamppi", "smoove:077"), "Kamppi (077)")
    expect_match(directions_url(60.17, 24.94), "destination=60.17,24.94&travelmode=walking", fixed = TRUE)
})

test_that("status_colour picks the right palette and handles unknowns", {
    expect_equal(
        status_colour(c("empty", "low", "plenty")),
        c("#D55E00", "#E69F00", "#009E73")
    )
    expect_equal(status_colour("empty", dark = TRUE), "#FF4444")
    expect_equal(status_colour(c(NA, "weird")), rep("#999999", 2))
    expect_length(status_colour(character()), 0)
})

test_that("carto_tile_url switches theme and only adds a key when set", {
    expect_match(carto_tile_url(FALSE), "/light_all/", fixed = TRUE)
    expect_match(carto_tile_url(TRUE), "/dark_all/", fixed = TRUE)
    expect_false(grepl("key=", carto_tile_url(TRUE)))
    expect_match(carto_tile_url(FALSE, key = "abc"), "?key=abc", fixed = TRUE)
})

test_that("station_popup mirrors the card and escapes names", {
    st <- tibble::tibble(
        name = "<script>x</script> & Co", station_id = "smoove:077",
        distance_m = 1636, bikes = 1L, lat = 60.1, lon = 24.9
    )
    strings <- list(bike_one = "bike", bike_many = "bikes", directions = "Directions")
    html <- station_popup(st, strings)
    expect_match(html, "(077)", fixed = TRUE)
    expect_match(html, "1,64 km", fixed = TRUE)
    expect_match(html, "1 bike\\s*<br")
    expect_match(html, "Directions", fixed = TRUE)
    expect_false(grepl("<script>", html, fixed = TRUE))
    expect_match(html, "&lt;script&gt;", fixed = TRUE)
    expect_match(station_popup(transform(st, bikes = 5L), strings), "5 bikes", fixed = TRUE)
})
