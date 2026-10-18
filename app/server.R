function(input, output, session) {
    # Reconnect quietly if the websocket drops, e.g. when Cloud Run closes it at
    # the 3600 s timeout. TRUE would do nothing here: the client only reconnects
    # if the host (Shiny Server, Posit Connect) allows it too; "force" makes it
    # reconnect anyway. The server can't resume the old session, so a new one
    # starts and the browser re-sends its inputs. That is fine for this app,
    # whose state is its inputs, the favourites in localStorage and the shared
    # station cache.
    session$allowReconnect("force")

    n <- reactive(as.integer(input$n %||% default_n_nearest))
    favourites <- reactive(as.character(unlist(input$favourites)))

    # A non-blank search overrides the location-based list; blank restores it
    search <- debounce(reactive(input$search), 300)
    searching <- reactive(nzchar(str_squish(search() %||% "")))

    has_location <- reactive(!is.null(input$user_location))
    location <- reactive({
        loc <- input$user_location
        if (is.null(loc)) default_location else list(lat = loc$lat, lon = loc$lon)
    })

    # Shared, memoised data (60 s cache); re-read every refresh interval
    stations <- reactive({
        invalidateLater(refresh_ms)
        get_stations()
    })

    state <- reactive(stations_state(stations()))

    # Off-season, a failed refresh and a failed first load each get their own
    # message; none of them is shown as a crash
    output$data_notice <- renderUI({
        switch(
            state(),
            off_season = div(class = "alert alert-info", role = "status", strings$season_over),
            stale = {
                age <- difftime(Sys.time(), stations()$fetched_at, units = "secs")
                div(
                    class = "alert alert-warning", role = "status",
                    sprintf(strings$stale_data, format_age(age))
                )
            },
            error = div(class = "alert alert-warning", role = "status", strings$no_data),
            NULL
        )
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
        sprintf(strings$updated, format_age(difftime(Sys.time(), fetched_at, units = "secs")))
    })

    output$station_list <- renderUI({
        # Off-season and error states are explained by the notice above the tabs
        if (!state() %in% c("ok", "stale")) {
            return(NULL)
        }
        st <- nearest()
        if (nrow(st) == 0) {
            return(div(
                class = "fs-notice",
                if (searching()) strings$no_matches else strings$none_available
            ))
        }

        tagList(lapply(seq_len(nrow(st)), function(i) {
            s <- st[i, ]
            div(
                class = paste("fs-card", paste0("fs-", s$status)),
                div(
                    class = "fs-card-main",
                    div(
                        class = "fs-name",
                        favourite_button(s$station_id, s$favourite, strings),
                        station_title(s$name, s$station_id)
                    ),
                    div(class = "fs-distance", format_distance(s$distance_m)),
                    tags$a(
                        class = "fs-directions",
                        href = directions_url(s$lat, s$lon),
                        target = "_blank",
                        rel = "noopener",
                        strings$directions
                    )
                ),
                div(class = "fs-count", s$bikes)
            )
        }))
    })

    # ---- Map ----------------------------------------------------------------
    is_dark <- reactive(identical(input$dark_mode, "dark"))

    # Base map only; stations are drawn through the proxy below, so panning
    # and zooming survive the 60 s data refresh
    output$map <- renderLeaflet({
        leaflet(options = leafletOptions(maxZoom = map_max_zoom)) |>
            # "You are here" sits below the station markers (overlay pane is 400),
            # so a station right next to the user is never hidden by it
            addMapPane("me", zIndex = 390) |>
            add_basemap(isolate(is_dark())) |>
            setView(default_location$lon, default_location$lat, map_default_zoom)
    })

    observeEvent(is_dark(), {
        leafletProxy("map") |>
            removeTiles("basemap") |>
            removeTiles("labels") |>
            add_basemap(is_dark())
    }, ignoreInit = TRUE)

    # The map sits in a hidden tab, so Shiny doesn't render it until first
    # shown, and leaflet drops proxy messages for a map that doesn't exist yet.
    # Leaflet reports its bounds once it does, which is our cue to start drawing.
    map_ready <- reactiveVal(FALSE)
    observeEvent(input$map_bounds, map_ready(TRUE), once = TRUE)

    # Only re-fit the view when the set of stations or the location changes
    last_fit <- reactiveVal(NULL)
    observeEvent(input$tab, last_fit(NULL))

    observe({
        req(map_ready())
        res <- stations()
        req(res$data)
        st <- nearest()
        dark <- is_dark()
        loc <- location()
        me <- has_location()
        input$tab # redraw (and re-fit) when the map tab is shown

        proxy <- leafletProxy("map") |>
            clearGroup("stations") |>
            clearGroup("me")

        if (nrow(st) > 0) {
            colours <- status_colour(st$status, dark)
            popups <- vapply(
                seq_len(nrow(st)),
                function(i) station_popup(st[i, ], strings),
                character(1)
            )
            proxy |>
                addCircleMarkers(
                    data = st,
                    lng = ~lon, lat = ~lat,
                    layerId = ~station_id,
                    group = "stations",
                    radius = map_marker_radius,
                    color = colours,
                    fillColor = colours,
                    fillOpacity = 0.9,
                    weight = 2,
                    popup = popups,
                    popupOptions = popupOptions(
                        autoPanPaddingTopLeft = map_popup_pan_padding
                    ),
                    # The bike count on the marker doubles as a non-colour cue
                    label = as.character(st$bikes),
                    labelOptions = labelOptions(
                        noHide = TRUE,
                        direction = "center",
                        textOnly = TRUE,
                        className = "fs-marker-label"
                    )
                )
        }

        if (me) {
            proxy |>
                addMarkers(
                    lng = loc$lon, lat = loc$lat,
                    group = "me",
                    icon = me_icon(),
                    popup = strings$you_are_here,
                    popupOptions = popupOptions(
                        autoPanPaddingTopLeft = map_popup_pan_padding
                    ),
                    options = markerOptions(title = strings$you_are_here, pane = "me")
                )
        }

        # While searching, fit the results only: a far-away match shouldn't
        # force the view to also include where the user is. The dot is still
        # drawn, and is simply off-screen if it is far from the results.
        fit_me <- me && !searching()
        lons <- c(st$lon, if (fit_me) loc$lon)
        lats <- c(st$lat, if (fit_me) loc$lat)
        fit_key <- paste(
            paste(sort(st$station_id), collapse = ","), fit_me,
            if (fit_me) paste(round(loc$lat, 3), round(loc$lon, 3))
        )
        if (length(lons) > 0 && !identical(isolate(last_fit()), fit_key)) {
            last_fit(fit_key)
            proxy |>
                fitBounds(
                    min(lons), min(lats), max(lons), max(lats),
                    options = list(padding = c(30, 30), maxZoom = map_max_fit_zoom)
                )
        }
    })
}
