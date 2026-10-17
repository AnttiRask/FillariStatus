library(shiny)
library(bslib)
library(dplyr)
library(stringr)
library(leaflet)

source("www/variables.R")
source("www/strings.R")
source("www/api.R")
source("www/functions.R")

# Optional: Carto basemap tiles work without a key today, but a key can be
# supplied through the environment (as in BiblioStatus) if that changes
carto_api_key <- Sys.getenv("CARTO_API_KEY")
