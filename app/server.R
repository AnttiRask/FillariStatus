function(input, output, session) {
    mode <- reactive(input$mode %||% "bike")
    n <- reactive(as.integer(input$n %||% default_n_nearest))
    favourites <- reactive(as.character(unlist(input$favourites)))

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

    # Search is the fallback when location isn't available
    output$location_notice <- renderUI({
        if (has_location() || is.null(input$location_error)) {
            return(NULL)
        }
        div(
            class = "fs-notice",
            p(strings$location_denied),
            textInput("search", strings$search_label, width = "100%")
        )
    })

    nearest <- reactive({
        res <- stations()
        req(res$data)
        loc <- location()
        res$data |>
            filter_by_name(if (has_location()) NULL else input$search) |>
            nearest_stations(
                loc$lat, loc$lon,
                n = n(), mode = mode(), favourites = favourites()
            )
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

        is_bike <- mode() == "bike"
        tagList(lapply(seq_len(nrow(st)), function(i) {
            s <- st[i, ]
            big <- if (is_bike) s$bikes else s$docks
            small <- if (is_bike) paste(s$docks, strings$docks) else paste(s$bikes, strings$bikes)
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
                        s$name
                    ),
                    div(class = "fs-distance", paste0(round(s$distance_m), " m")),
                    div(class = "fs-small", small),
                    tags$a(
                        class = "fs-directions",
                        href = directions_url,
                        target = "_blank",
                        rel = "noopener",
                        strings$directions
                    )
                ),
                div(class = "fs-count", big)
            )
        }))
    })
}
