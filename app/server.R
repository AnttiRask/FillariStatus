function(input, output, session) {
    # Hardcoded location (Rautatientori) until geolocation lands in milestone 4
    user_location <- reactiveVal(list(lat = 60.1699, lon = 24.9384))

    # Re-read the shared, memoised data every refresh interval
    stations <- reactive({
        invalidateLater(refresh_ms)
        get_stations()
    })

    nearest <- reactive({
        res <- stations()
        req(res$data)
        loc <- user_location()
        nearest_stations(res$data, loc$lat, loc$lon, n = default_n_nearest, mode = "bike")
    })

    # Ticks every second so "updated X s ago" stays current
    now <- reactiveTimer(1000)

    output$updated <- renderText({
        now()
        fetched_at <- stations()$fetched_at
        if (is.null(fetched_at)) {
            return("No data yet")
        }
        secs <- as.integer(difftime(Sys.time(), fetched_at, units = "secs"))
        paste0("Updated ", secs, " s ago")
    })

    output$station_list <- renderUI({
        st <- nearest()
        tagList(lapply(seq_len(nrow(st)), function(i) {
            s <- st[i, ]
            div(
                class = paste("fs-card", paste0("fs-", s$status)),
                div(
                    class = "fs-card-main",
                    div(class = "fs-name", s$name),
                    div(class = "fs-distance", paste0(round(s$distance_m), " m")),
                    div(class = "fs-small", paste(s$docks, "free docks"))
                ),
                div(class = "fs-count", s$bikes)
            )
        }))
    })
}
