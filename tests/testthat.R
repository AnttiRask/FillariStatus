# Runs the whole suite from the project root, the way CI does:
#   Rscript tests/testthat.R
# (the files find the app code with here::here(), so no setup is needed).
# stop_on_failure makes Rscript exit non-zero, so CI goes red on a failing test.
library(testthat)

test_dir(here::here("tests", "testthat"), reporter = "summary", stop_on_failure = TRUE)
