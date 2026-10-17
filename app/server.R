function(input, output, session) {
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

    tile_options <- tileOptions(
        subdomains = "abcd", maxZoom = 19, attribution = carto_attribution
    )

    # Base map only; stations are drawn through the proxy below, so panning
    # and zooming survive the 60 s data refresh
    output$map <- renderLeaflet({
        leaflet() |>
            addTiles(
                urlTemplate = carto_tile_url(isolate(is_dark()), carto_api_key),
                layerId = "basemap",
                options = tile_options
            ) |>
            setView(default_location$lon, default_location$lat, map_default_zoom)
    })

    observeEvent(is_dark(), {
        leafletProxy("map") |>
            removeTiles("basemap") |>
            addTiles(
                urlTemplate = carto_tile_url(is_dark(), carto_api_key),
                layerId = "basemap",
                options = tile_options
            )
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
            me_colour <- if (dark) status_colours$dark$me else status_colours$light$me
            proxy |>
                addCircleMarkers(
                    lng = loc$lon, lat = loc$lat,
                    group = "me",
                    radius = map_user_marker_radius,
                    # White outline keeps the red dot distinct from the
                    # "empty" station markers
                    color = "#FFFFFF",
                    fillColor = me_colour,
                    fillOpacity = 1,
                    weight = 2.5,
                    popup = strings$you_are_here
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
