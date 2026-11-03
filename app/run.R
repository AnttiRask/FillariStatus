library(shiny)

# Run from the app directory so ui.R / global.R find their www/ files
source("app/www/security.R")
source("app/www/health.R")   # GET /health answers the uptime monitor
setwd("app")

port <- as.integer(Sys.getenv("PORT", "8080"))
# The health check sits inside the security wrapper, so its answer gets the headers too
app <- with_security_headers(with_health_check(shinyAppDir(".")))
runApp(app, host = "0.0.0.0", port = port)
