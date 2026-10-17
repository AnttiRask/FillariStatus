# R 4.6.1 matches renv.lock; r-ver is much smaller than rocker/shiny and we
# only need R, because run.R starts the app with shiny::runApp()
FROM rocker/r-ver:4.6.1

# Runtime/system libraries for the spatial packages leaflet pulls in
# (sf, terra, s2, raster) and for curl/openssl/xml2
RUN for i in 1 2 3; do \
        apt-get update && apt-get install -y --no-install-recommends \
            libcurl4-openssl-dev \
            libssl-dev \
            libxml2-dev \
            libpng-dev \
            libgdal-dev \
            gdal-bin \
            libgeos-dev \
            libproj-dev \
            libudunits2-dev \
            libsqlite3-dev \
            curl \
        && break || { echo "apt attempt $i failed, retrying in $((i*15))s"; sleep $((i*15)); }; \
    done \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# renv infrastructure first, so the (slow) package layer is cached until the
# lockfile changes
COPY renv.lock renv.lock
COPY .Rprofile .Rprofile
COPY renv/activate.R renv/activate.R
COPY renv/settings.json renv/settings.json

# Restore from Posit Package Manager's prebuilt Linux binaries for this distro
# (compiling terra/sf/s2 from source takes 20+ minutes)
RUN CODENAME="$(. /etc/os-release && echo "$VERSION_CODENAME")" \
    && R -q -e "options(renv.config.repos.override = c(CRAN = 'https://p3m.dev/cran/__linux__/${CODENAME}/latest')); renv::restore(prompt = FALSE)"

COPY app app

# Don't run as root
RUN useradd --system --create-home --shell /usr/sbin/nologin fillari \
    && chown -R fillari:fillari /app
USER fillari

# Cloud Run sets PORT; DIGITRANSIT_SUBSCRIPTION_KEY and CARTO_API_KEY are
# injected at runtime (Secret Manager), never baked into the image
ENV PORT=8080
EXPOSE 8080

CMD ["Rscript", "app/run.R"]
