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

test_that("a favourite within the n nearest takes one of the n slots", {
    out <- nearest_stations(
        stations_tbl, 60.1702, 24.9385, n = 2, favourites = "a"
    )
    expect_equal(anyDuplicated(out$station_id), 0)
    expect_equal(nrow(out), 2)
    # favourite pinned first, then the rest by distance
    expect_equal(out$station_id, c("a", "c"))
    expect_equal(out$favourite, c(TRUE, FALSE))
})

test_that("only favourites outside the n nearest are added on top", {
    out <- nearest_stations(
        stations_tbl, 60.1702, 24.9385, n = 2, favourites = c("a", "b")
    )
    # n nearest are c and a; b is a far favourite, so 3 rows in total
    expect_equal(sort(out$station_id), c("a", "b", "c"))
    expect_equal(out$station_id[1:2], c("a", "b"))
    expect_equal(out$station_id[3], "c")
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

test_that("map_tile_urls gives a base and a labels layer per theme, in Esri's z/y/x order", {
    light <- map_tile_urls(FALSE)
    dark <- map_tile_urls(TRUE)
    expect_named(light, c("base", "labels"))
    expect_true(endsWith(light$base, "World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}"))
    expect_true(endsWith(light$labels, "World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}"))
    expect_match(dark$base, "World_Dark_Gray_Base/", fixed = TRUE)
    expect_match(dark$labels, "World_Dark_Gray_Reference/", fixed = TRUE)
    # no API key in any URL, and everything comes from the one allowed host
    expect_false(any(grepl("key=", c(unlist(light), unlist(dark)))))
    expect_true(all(startsWith(c(unlist(light), unlist(dark)), map_tiles_host)))
})

test_that("tiles are capped at the last real Esri zoom", {
    expect_equal(map_tile_max_native_zoom, 16)
    expect_gte(map_max_zoom, map_tile_max_native_zoom)
    # the automatic fit never asks for a zoom without real tiles
    expect_lte(map_max_fit_zoom, map_tile_max_native_zoom)
    expect_match(map_attribution, "Esri", fixed = TRUE)
    expect_match(map_attribution, "OpenStreetMap", fixed = TRUE)
})

test_that("station_popup mirrors the card and escapes names", {
    st <- tibble::tibble(
        name = "<script>x</script> & Co", station_id = "smoove:077",
        distance_m = 1636, bikes = 1L, lat = 60.1, lon = 24.9, favourite = FALSE
    )
    strings <- list(
        bike_one = "bike", bike_many = "bikes", directions = "Directions",
        fav_add = "Add to favourites", fav_remove = "Remove from favourites"
    )
    html <- station_popup(st, strings)
    expect_match(html, "(077)", fixed = TRUE)
    expect_match(html, "1,64 km", fixed = TRUE)
    expect_match(html, "1 bike\\s*<br")
    expect_match(html, "Directions", fixed = TRUE)
    expect_false(grepl("<script>", html, fixed = TRUE))
    expect_match(html, "&lt;script&gt;", fixed = TRUE)
    expect_match(station_popup(transform(st, bikes = 5L), strings), "5 bikes", fixed = TRUE)
})

test_that("favourite_button reflects the favourite state", {
    strings <- list(fav_add = "Add to favourites", fav_remove = "Remove from favourites")
    off <- as.character(favourite_button("smoove:077", FALSE, strings))
    on <- as.character(favourite_button("smoove:077", TRUE, strings))
    expect_match(off, 'data-station-id="smoove:077"', fixed = TRUE)
    expect_match(off, 'aria-pressed="false"', fixed = TRUE)
    expect_match(off, "Add to favourites", fixed = TRUE)
    expect_match(off, "\u2606", fixed = TRUE)
    expect_match(on, 'aria-pressed="true"', fixed = TRUE)
    expect_match(on, "is-fav", fixed = TRUE)
    expect_match(on, "Remove from favourites", fixed = TRUE)
    expect_match(on, "\u2605", fixed = TRUE)
})

test_that("the popup carries a favourite star for its station", {
    strings <- list(
        bike_one = "bike", bike_many = "bikes", directions = "Directions",
        fav_add = "Add to favourites", fav_remove = "Remove from favourites"
    )
    st <- tibble::tibble(
        name = "Kamppi", station_id = "smoove:077", distance_m = 100,
        bikes = 3L, lat = 60.1, lon = 24.9, favourite = TRUE
    )
    html <- station_popup(st, strings)
    expect_match(html, 'class="fs-fav is-fav"', fixed = TRUE)
    expect_match(html, 'data-station-id="smoove:077"', fixed = TRUE)
})

test_that("stations_state distinguishes ok, off-season, stale and error", {
    some <- tibble::tibble(station_id = "a")
    none <- tibble::tibble(station_id = character())
    expect_equal(stations_state(list(data = some, error = NULL)), "ok")
    expect_equal(stations_state(list(data = none, error = NULL)), "off_season")
    expect_equal(stations_state(list(data = some, error = "boom")), "stale")
    expect_equal(stations_state(list(data = NULL, error = "boom")), "error")
    # Off-season data we couldn't refresh is still just off-season
    expect_equal(stations_state(list(data = none, error = "boom")), "off_season")
})

test_that("format_age picks a readable unit", {
    expect_equal(format_age(0), "0 s")
    expect_equal(format_age(45), "45 s")
    expect_equal(format_age(60), "1 min")
    expect_equal(format_age(400), "6 min")
    expect_equal(format_age(3600), "1 h")
    expect_equal(format_age(7300), "2 h")
    expect_equal(format_age(-5), "0 s")
    expect_equal(format_age(as.difftime(125, units = "secs")), "2 min")
})

test_that("should_refetch rate-limits on the last attempt", {
    now <- Sys.time()
    expect_true(should_refetch(NULL, now))
    expect_false(should_refetch(now - 3, now, min_age = 10))
    expect_true(should_refetch(now - 10, now, min_age = 10))
    expect_true(should_refetch(now - 300, now, min_age = 10))
})

test_that("nearest_stations copes with an empty station list", {
    empty <- tibble::tibble(
        station_id = character(), name = character(), lat = double(), lon = double(),
        bikes = integer(), allow_pickup = logical(), operative = logical()
    )
    out <- nearest_stations(empty, 60.17, 24.94, n = 5, favourites = "x")
    expect_equal(nrow(out), 0)
})

test_that("the location marker is a ring-and-dot icon in the configured colour", {
    svg <- me_icon_svg("#FF0000")
    expect_match(svg, 'stroke="#FF0000"', fixed = TRUE)
    expect_match(svg, 'fill="#FF0000"', fixed = TRUE)
    # a ring (white fill + stroke), a centre dot and a halo: three circles
    expect_equal(lengths(regmatches(svg, gregexpr("<circle", svg))), 3)

    icon <- me_icon()
    expect_match(icon$iconUrl, "^data:image/svg\\+xml;utf8,")
    # URL-encoded: no raw angle brackets or spaces left in the data URI
    expect_false(grepl("[<> ]", sub("^data:image/svg\\+xml;utf8,", "", icon$iconUrl)))
    expect_equal(c(icon$iconWidth, icon$iconHeight), c(28, 28))
    expect_equal(c(icon$iconAnchorX, icon$iconAnchorY), c(14, 14))
})

test_that("add_basemap adds a base layer with the attribution and a labels layer without", {
    calls <- leaflet::leaflet() |> add_basemap(FALSE) |> (\(m) m$x$calls)()
    tiles <- Filter(\(x) x$method == "addTiles", calls)
    expect_length(tiles, 2)
    base <- tiles[[1]]$args
    labels <- tiles[[2]]$args

    expect_equal(base[[2]], "basemap")
    expect_equal(labels[[2]], "labels")
    expect_true(endsWith(base[[1]], "World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}"))
    expect_true(endsWith(labels[[1]], "World_Light_Gray_Reference/MapServer/tile/{z}/{y}/{x}"))

    # The regression: the attribution was lost when passed through tileOptions()
    expect_equal(base[[4]]$attribution, map_attribution)
    expect_match(base[[4]]$attribution, "Esri", fixed = TRUE)
    expect_null(labels[[4]]$attribution)

    # tile requests are capped at the last real zoom, closer views are scaled up
    expect_equal(base[[4]]$maxNativeZoom, map_tile_max_native_zoom)
    expect_equal(labels[[4]]$maxNativeZoom, map_tile_max_native_zoom)
    expect_equal(base[[4]]$maxZoom, map_max_zoom)
})

test_that("add_basemap switches both layers for dark mode and works on a proxy-style call chain", {
    tiles <- leaflet::leaflet() |> add_basemap(TRUE) |> (\(m) Filter(\(x) x$method == "addTiles", m$x$calls))()
    expect_match(tiles[[1]]$args[[1]], "World_Dark_Gray_Base", fixed = TRUE)
    expect_match(tiles[[2]]$args[[1]], "World_Dark_Gray_Reference", fixed = TRUE)
})
