page_fluid(
    title = strings$title,
    theme = bs_theme(version = 5),
    tags$head(
        tags$link(rel = "stylesheet", href = "styles.css"),
        tags$script(src = "geolocation.js"),
        tags$script(src = "favourites.js")
    ),
    div(
        class = "fs-container",
        h1(strings$title, class = "fs-title"),
        div(
            class = "fs-controls",
            radioButtons(
                "mode",
                strings$mode_label,
                choices = c(
                    setNames("bike", strings$mode_bike),
                    setNames("dock", strings$mode_dock)
                ),
                inline = TRUE
            ),
            selectInput(
                "n",
                strings$n_label,
                choices = n_choices,
                selected = default_n_nearest,
                width = "6rem"
            )
        ),
        div(
            class = "fs-meta",
            textOutput("updated", inline = TRUE),
            actionLink("refresh", strings$refresh),
            tags$a(id = "locate", href = "#", strings$locate)
        ),
        uiOutput("location_notice"),
        uiOutput("station_list")
    )
)
