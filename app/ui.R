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
    theme = bs_theme(
        version = 5,
        primary = brand_colours$red,
        base_font = font_collection(
            font_link("Gotham", href = gotham_css_url),
            "system-ui", "-apple-system", "Segoe UI", "Roboto",
            "Helvetica Neue", "Arial", "sans-serif"
        )
    ) |>
        # Bootstrap's dark-mode palette, in the BiblioStatus dark background and
        # with a lighter brand red for links (brand red is too dim on dark)
        bs_add_variables(
            "body-bg-dark"          = brand_colours$dark_bg,
            "link-color-dark"       = brand_colours$red_on_dark,
            "link-hover-color-dark" = brand_colours$red_on_dark
        ),
    tags$head(
        tags$style(HTML(paste0(
            ":root{", status_css(status_colours$light),
            # Brand accent for the title and the active tab (chrome only)
            "--fs-accent:", brand_colours$red, ";",
            # The map placeholder text lives in strings.R, like all UI text
            "--fs-map-loading:",
            jsonlite::toJSON(strings$loading_map, auto_unbox = TRUE), ";}",
            "[data-bs-theme=dark]{", status_css(status_colours$dark),
            "--fs-accent:", brand_colours$red_on_dark, ";}"
        ))),
        tags$link(rel = "icon", type = "image/png", href = asset("favicon.png")),
        tags$link(rel = "icon", href = asset("favicon.ico"), sizes = "any"),
        tags$link(rel = "apple-touch-icon", href = asset("favicon.png")),
        tags$link(rel = "stylesheet", href = asset("styles.css")),
        tags$script(src = asset("geolocation.js")),
        tags$script(src = asset("favourites.js"))
    ),
    div(
        class = "fs-container",
        div(
            class = "fs-header",
            # Built as one string: separate child nodes would be rendered with
            # whitespace between them ("Fillari Status")
            h1(
                class = "fs-title",
                # First part in the brand colour, like the youcanbeapirate project pages
                HTML(paste0(
                    '<span class="fs-title-accent">',
                    htmltools::htmlEscape(strings$title_first),
                    "</span>",
                    htmltools::htmlEscape(strings$title_second)
                ))
            ),
            # Light by default (like BiblioStatus); the toggle is still there
            input_dark_mode(id = "dark_mode", mode = "light")
        ),
        p(class = "fs-description", strings$description),
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
            # Re-reads the browser location (geolocation.js); the station data
            # refreshes itself every minute
            actionLink(
                "update_location", strings$update_location,
                `data-busy` = strings$locating,
                `data-failed` = strings$location_failed
            )
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
                strings$more_projects, " ",
                tags$span(
                    class = "fs-footer-links",
                    lapply(sibling_apps, function(app) a(href = app$url, app$name))
                )
            ),
            p(
                a(href = repo_url, strings$source_code),
                " | ",
                strings$credit, " ",
                a(href = "https://www.linkedin.com/in/AnttiRask/", "Antti Rask"),
                " | ",
                a(href = site_url, "youcanbeapirate.com")
            )
        )
    )
)
