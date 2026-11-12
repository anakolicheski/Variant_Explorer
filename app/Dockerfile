# Cooper Lab Variant Database
# Base: rocker/shiny with R 4.3.3
FROM rocker/shiny:4.3.3

# ── System libraries ──────────────────────────────────────────────────────────
# Required by tidyverse, httr, XML, Cairo (for trackViewer graphics),
# readxl, and Bioconductor packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    pkg-config \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libcairo2-dev \
    libxt-dev \
    libfontconfig1-dev \
    libharfbuzz-dev \
    libfribidi-dev \
    libfreetype6-dev \
    libpng-dev \
    libtiff5-dev \
    libjpeg-dev \
    libwebp-dev \
    libuv1-dev \
    libbz2-dev \
    liblzma-dev \
    zlib1g-dev \
    pandoc \
    && rm -rf /var/lib/apt/lists/*

# ── R package installation via renv ──────────────────────────────────────────
# Copy lockfile first so Docker caches the package layer separately from
# app code changes — rebuilds after editing R files skip package install.
WORKDIR /app

RUN R -e "install.packages('renv', repos='https://cloud.r-project.org')"

COPY renv.lock renv.lock

# Restore all packages in ONE layer. The three steps run in separate R
# sessions (chained with &&) but share a single Docker layer, so if anything
# fails, nothing is cached and the next build retries from scratch. (Separate
# RUN layers let a silently failed restore get cached and reused forever.)
#
# CRAN comes from Posit Package Manager's prebuilt Linux binaries for Ubuntu
# 22.04 (jammy, the base of rocker/shiny:4.3.3). No compiling: much faster
# builds everywhere, and reliable on Apple Silicon Macs, where compiling
# hundreds of packages under amd64 emulation is slow and fragile.
# Bioconductor packages still come from Bioconductor.
ENV R_REPOS="c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest', BioCsoft = 'https://bioconductor.org/packages/3.18/bioc', BioCann = 'https://bioconductor.org/packages/3.18/data/annotation', BioCexp = 'https://bioconductor.org/packages/3.18/data/experiment')"

# Step 1: restore what renv can (errors reported, not fatal)
# Step 2: fresh session, install anything still missing directly
# Step 3: fresh session, verify; THIS one fails the build if anything is missing
RUN R -e " \
      repos <- eval(parse(text = Sys.getenv('R_REPOS'))); \
      options(renv.config.repos.override = repos, repos = repos); \
      tryCatch(renv::restore(prompt = FALSE), error = function(e) message('renv::restore reported errors, will patch missing packages: ', conditionMessage(e)))" \
 && R -e " \
      repos <- eval(parse(text = Sys.getenv('R_REPOS'))); \
      pkgs <- names(renv::lockfile_read('renv.lock')\$Packages); \
      missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; \
      if (length(missing_pkgs) > 0) { \
        message('Installing missing packages: ', paste(missing_pkgs, collapse = ', ')); \
        install.packages(missing_pkgs, repos = repos) \
      } else message('Nothing missing.')" \
 && R -e " \
      pkgs <- names(renv::lockfile_read('renv.lock')\$Packages); \
      still_missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; \
      if (length(still_missing) > 0) stop('Still failed to install: ', paste(still_missing, collapse = ', ')) else message('All packages verified installed.')"

# Load every package the app attaches at startup, so a broken install fails
# the BUILD with a clear error instead of crash-looping the container later.
RUN R -e " \
    pkgs <- c('stringr', 'shiny', 'shinythemes', 'tidyverse', 'readxl', 'DT', 'jsonlite', \
              'httr', 'purrr', 'dplyr', 'readr', 'biomaRt', 'trackViewer', \
              'GenomicRanges'); \
    for (p in pkgs) suppressPackageStartupMessages(library(p, character.only = TRUE)); \
    message('All app packages load OK.')"

# ── Copy app files ────────────────────────────────────────────────────────────
# The app file is copied in under a stable name (app.R), so a new version
# only means changing the source filename on the next line.
COPY app_v1.0.5.R            ./app.R
COPY variant_upload_module.R ./
# The [d] glob makes the guide optional: the build still works if
# APP_GUIDE.md is not in the folder.
COPY lolliplot_module.R APP_GUIDE.m[d] ./

# Create directories that will be bind-mounted from the host
RUN mkdir -p annotations New_genotypes app_state www

# How to Use tab: convert the guide to an HTML fragment with pandoc
# (installed above), so the image does not need the R 'markdown' package.
# Adding that package pulled in a newer xfun that broke trackViewer loading.
RUN if [ -f APP_GUIDE.md ]; then \
      pandoc APP_GUIDE.md -f gfm -t html -o app_guide.html; \
    fi
ENV APP_STATE_DIR=/app/app_state

# ── Runtime ───────────────────────────────────────────────────────────────────
EXPOSE 3838

# Run the Shiny app directly (no Shiny Server needed for single-app deploy)
CMD ["R", "-e", \
    "shiny::runApp('/app/app.R', host='0.0.0.0', port=3838, launch.browser=FALSE)"]
