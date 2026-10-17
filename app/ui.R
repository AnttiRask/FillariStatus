page_fluid(
    title = "FillariStatus",
    theme = bs_theme(version = 5),
    tags$head(tags$link(rel = "stylesheet", href = "styles.css")),
    div(
        class = "fs-container",
        h1("FillariStatus", class = "fs-title"),
        div(
            class = "fs-meta",
            textOutput("updated", inline = TRUE)
        ),
        uiOutput("station_list")
    )
)
