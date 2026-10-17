function(input, output, session) {
    n <- reactive(as.integer(input$n %||% default_n_nearest))
    favourites <- reactive(as.character(unlist(input$favourites)))

    # A non-blank search overrides the location-based list; blank restores it
    search <- debounce(reactive(input$search), 300)

    has_location <- reactive(!is.null(input$user_location))
    location <- reactive({
        loc <- input$user_location
        if (is.null(loc)) default_location else list(lat = loc$lat, lon = loc$lon)
    })

    # Shared, memoised data; re-read every refresh interval and on demand
    refresh_count <- reactiveVal(0)
    stations <- reactive({
        invalidateLater(refresh_ms)
        refresh_count()
        get_stations()
    })

    observeEvent(input$refresh, {
        fetched_at <- get_stations()$fetched_at
        age <- if (is.null(fetched_at)) Inf else as.numeric(difftime(Sys.time(), fetched_at, units = "secs"))
        # The cache is shared by all sessions, so don't let a click hammer upstream
        if (age >= min_manual_refresh_s) {
            memoise::forget(get_stations)
        }
        refresh_count(refresh_count() + 1)
    })

    output$location_notice <- renderUI({
        if (has_location() || is.null(input$location_error)) {
            return(NULL)
        }
        div(class = "fs-notice", strings$location_denied)
    })

    nearest <- reactive({
        res <- stations()
        req(res$data)
        loc <- location()
        res$data |>
            filter_by_name(search()) |>
            nearest_stations(loc$lat, loc$lon, n = n(), favourites = favourites())
    })

    # Ticks every second so "updated X s ago" stays current
    now <- reactiveTimer(1000)

    output$updated <- renderText({
        now()
        fetched_at <- stations()$fetched_at
        if (is.null(fetched_at)) {
            return(strings$no_data_yet)
        }
        sprintf(strings$updated, as.integer(difftime(Sys.time(), fetched_at, units = "secs")))
    })

    output$station_list <- renderUI({
        if (is.null(stations()$data)) {
            return(div(class = "fs-notice", strings$no_data))
        }
        st <- nearest()
        if (nrow(st) == 0) {
            return(div(class = "fs-notice", strings$no_matches))
        }

        tagList(lapply(seq_len(nrow(st)), function(i) {
            s <- st[i, ]
            directions_url <- sprintf(
                "https://www.google.com/maps/dir/?api=1&destination=%s,%s&travelmode=walking",
                s$lat, s$lon
            )
            div(
                class = paste("fs-card", paste0("fs-", s$status)),
                div(
                    class = "fs-card-main",
                    div(
                        class = "fs-name",
                        tags$button(
                            type = "button",
                            class = paste("fs-fav", if (s$favourite) "is-fav"),
                            `data-station-id` = s$station_id,
                            `aria-pressed` = tolower(s$favourite),
                            `aria-label` = if (s$favourite) strings$fav_remove else strings$fav_add,
                            if (s$favourite) "★" else "☆"
                        ),
                        paste0(s$name, " (", station_number(s$station_id), ")")
                    ),
                    div(class = "fs-distance", format_distance(s$distance_m)),
                    tags$a(
                        class = "fs-directions",
                        href = directions_url,
                        target = "_blank",
                        rel = "noopener",
                        strings$directions
                    )
                ),
                div(class = "fs-count", s$bikes)
            )
        }))
    })
}
