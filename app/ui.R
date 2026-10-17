# Status colours are defined once (variables.R) and exposed to the CSS here
status_css <- function(palette) {
    paste0(
        "--fs-empty:", palette$empty, ";",
        "--fs-low:", palette$low, ";",
        "--fs-plenty:", palette$plenty, ";",
        "--fs-me:", palette$me, ";"
    )
}

# Versioned asset URLs, so browsers don't keep serving a stale stylesheet or
# script after a change or a deploy
asset <- function(file) {
    paste0(file, "?v=", as.integer(file.mtime(file.path("www", file))))
}

page_fluid(
    title = strings$title,
    theme = bs_theme(version = 5, primary = "#0072B2"),
    tags$head(
        tags$style(HTML(paste0(
            ":root{", status_css(status_colours$light), "}",
            "[data-bs-theme=dark]{", status_css(status_colours$dark), "}"
        ))),
        tags$link(rel = "stylesheet", href = asset("styles.css")),
        tags$script(src = asset("geolocation.js")),
        tags$script(src = asset("favourites.js"))
    ),
    div(
        class = "fs-container",
        div(
            class = "fs-header",
            h1(strings$title, class = "fs-title"),
            input_dark_mode(id = "dark_mode")
        ),
        div(
            class = "fs-controls",
            textInput("search", strings$search_label, width = "100%"),
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
        uiOutput("data_notice"),
        uiOutput("location_notice"),
        navset_underline(
            id = "tab",
            nav_panel(
                strings$tab_list,
                value = "list",
                uiOutput("station_list")
            ),
            nav_panel(
                strings$tab_map,
                value = "map",
                leafletOutput("map", height = "60vh")
            )
        ),
        tags$footer(
            class = "fs-footer",
            p(strings$attribution),
            p(strings$privacy),
            p(
                strings$credit, " ",
                a(href = "https://www.linkedin.com/in/AnttiRask/", "Antti Rask"),
                " | ",
                a(href = "https://youcanbeapirate.com", "youcanbeapirate.com")
            )
        )
    )
)
