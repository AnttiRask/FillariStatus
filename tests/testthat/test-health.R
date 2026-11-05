source(here::here("app/lib/variables.R"))
source(here::here("app/lib/functions.R"))   # format_age()
source(here::here("app/lib/health.R"))

now <- as.POSIXct("2026-11-03 12:00:00", tz = "UTC")

result <- function(rows = 3L, fetched_s_ago = 30, error = NULL) {
    list(
        data = tibble::tibble(station_id = seq_len(rows)),
        stale = !is.null(error),
        error = error,
        fetched_at = now - fetched_s_ago,
        attempted_at = now
    )
}

test_that("fresh data is healthy", {
    r <- health_status(result(), now = now)
    expect_true(r$ok)
    expect_equal(r$body, "ok")
})

test_that("the off-season (no stations, no error) is healthy", {
    r <- health_status(result(rows = 0L), now = now)
    expect_true(r$ok)
    expect_match(r$body, "off season")
})

test_that("one failed refresh with recent data is not a problem", {
    r <- health_status(result(fetched_s_ago = 150, error = "timeout"), now = now)
    expect_true(r$ok)
})

test_that("data older than the limit is stale", {
    r <- health_status(result(fetched_s_ago = health_max_age_s + 60, error = "timeout"), now = now)
    expect_false(r$ok)
    expect_match(r$body, "^stale: the last successful fetch was 11 min ago$")
})

test_that("the limit itself is still healthy", {
    expect_true(health_status(result(fetched_s_ago = health_max_age_s), now = now)$ok)
})

test_that("no data at all is unavailable", {
    r <- health_status(list(data = NULL, stale = FALSE, error = "boom", fetched_at = NULL), now = now)
    expect_false(r$ok)
    expect_match(r$body, "^unavailable")
})

test_that("the reasons never contain error details", {
    r <- health_status(list(data = NULL, error = "key abc123 http://x", fetched_at = NULL), now = now)
    expect_false(grepl("abc123|http|key", r$body))
    s <- health_status(result(fetched_s_ago = 5000, error = "secret-token"), now = now)
    expect_false(grepl("secret-token", s$body))
})

# ---- the HTTP wrapper ----
inner <- list(httpHandler = function(req) "inner")
request <- function(path, method = "GET") list(PATH_INFO = path, REQUEST_METHOD = method)

test_that("/health answers 200 or 503 with plain text and no caching", {
    ok <- with_health_check(inner, check = function() list(ok = TRUE, body = "ok"))
    r <- ok$httpHandler(request("/health"))
    expect_equal(r$status, 200L)
    expect_equal(r$content, "ok")
    expect_match(r$content_type, "text/plain")
    expect_equal(r$headers[["Cache-Control"]], "no-store")

    bad <- with_health_check(inner, check = function() list(ok = FALSE, body = "stale: x"))
    expect_equal(bad$httpHandler(request("/health", "HEAD"))$status, 503L)
})

test_that("other paths and methods go to the app", {
    app <- with_health_check(inner, check = function() list(ok = TRUE, body = "ok"))
    expect_equal(app$httpHandler(request("/")), "inner")
    expect_equal(app$httpHandler(request("/health", "POST")), "inner")
})

test_that("a failing check is a 503 without the error text", {
    app <- with_health_check(inner, check = function() stop("secret detail"))
    r <- suppressMessages(app$httpHandler(request("/health")))
    expect_equal(r$status, 503L)
    expect_false(grepl("secret", r$content))
})
