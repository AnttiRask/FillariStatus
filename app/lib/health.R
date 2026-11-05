## Health check for the uptime monitor: GET /health (with_health_check() below,
## wrapped around the app in run.R). 200 and "ok" when the station data is
## healthy, 503 and a short reason when it is not. A page that answers 200 on "/"
## is not enough: the page shell loads even when Digitransit has been failing for
## hours. The reasons carry no error details.
##
## Problems reported:
##   unavailable  no station data has been fetched successfully since the start
##   stale        the last successful fetch is older than health_max_age_s (one
##                failed refresh is normal: the app keeps showing the last data and
##                tries again every minute, so only a long streak is a problem)
## An empty station list without an error is the off-season, not a problem.

# The answer for one get_stations() result: list(ok, body). Pure, so every case
# is tested.
health_status <- function(res, now = Sys.time(), max_age_s = health_max_age_s) {
    if (is.null(res$data) || is.null(res$fetched_at)) {
        return(list(ok = FALSE, body = "unavailable: no station data has been fetched"))
    }

    age_s <- as.numeric(difftime(now, res$fetched_at, units = "secs"))
    if (age_s > max_age_s) {
        return(list(
            ok = FALSE,
            body = sprintf("stale: the last successful fetch was %s ago", format_age(age_s))
        ))
    }

    list(ok = TRUE, body = if (nrow(res$data) == 0) "ok (off season)" else "ok")
}

# get_stations() is shared by all sessions and cached for a minute, so a monitor
# checking from several places adds no extra calls to Digitransit.
with_health_check <- function(app, path = "/health",
                              check = function() health_status(get_stations())) {
    original <- app$httpHandler
    app$httpHandler <- function(req) {
        method <- req$REQUEST_METHOD
        if (identical(req$PATH_INFO, path) && (is.null(method) || method %in% c("GET", "HEAD"))) {
            result <- tryCatch(
                check(),
                error = function(e) {
                    message("The health check failed: ", conditionMessage(e))
                    list(ok = FALSE, body = "unavailable: the health check itself failed")
                }
            )
            return(shiny::httpResponse(
                status       = if (result$ok) 200L else 503L,
                content_type = "text/plain; charset=utf-8",
                content      = result$body,
                headers      = list("Cache-Control" = "no-store")
            ))
        }
        original(req)
    }
    app
}
