# Shiny serves everything in app/www/ to anyone who asks for it (the browser needs
# the scripts and the styles from there). The R code must not be in it: until
# 2026-11-05 functions.R, security.R, health.R and the rest could be downloaded
# from the live site. The R code lives in app/lib/ (not app/R/, which Shiny
# loads by itself in alphabetical order).

test_that("no R file is served from app/www", {
    served <- list.files(here::here("app", "www"), recursive = TRUE, all.files = TRUE)
    expect_false(any(grepl("\\.[Rr]$", served)))
    # the guard looks at the right folder
    expect_true(all(c("styles.css", "mode-toggle.js", "map-tiles.js") %in% served))
})

test_that("the R code Shiny loads is where global.R and run.R say", {
    for (f in c("api", "functions", "variables", "strings", "health", "security")) {
        expect_true(file.exists(here::here("app", "lib", paste0(f, ".R"))), info = f)
    }
})
