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

# Configure renv to use Bioconductor and restore all packages
# This step takes 10-30 min on first build; cached on subsequent builds
RUN R -e " \
    repos <- c( \
      CRAN = 'https://cloud.r-project.org', \
      BioCsoft = 'https://bioconductor.org/packages/3.18/bioc', \
      BioCann  = 'https://bioconductor.org/packages/3.18/data/annotation' \
    ); \
    options(renv.config.repos.override = repos, repos = repos); \
    tryCatch(renv::restore(prompt = FALSE), error = function(e) message('renv::restore reported errors, will patch missing packages: ', conditionMessage(e))); \
    lock <- renv::lockfile_read('renv.lock'); \
    pkgs <- names(lock\$Packages); \
    missing_pkgs <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]; \
    if (length(missing_pkgs) > 0) { \
      message('Installing missing packages: ', paste(missing_pkgs, collapse = ', ')); \
      install.packages(missing_pkgs, repos = repos) \
    }; \
    still_missing <- missing_pkgs[!sapply(missing_pkgs, requireNamespace, quietly = TRUE)]; \
    if (length(still_missing) > 0) stop('Still failed to install: ', paste(still_missing, collapse = ', ')) \
"

# ── Copy app files ────────────────────────────────────────────────────────────
COPY app_v1.0.4.R          ./
COPY variant_upload_module.R ./
COPY lolliplot_module.R      ./

# Create directories that will be bind-mounted from the host
RUN mkdir -p annotations New_genotypes www

# ── Runtime ───────────────────────────────────────────────────────────────────
EXPOSE 3838

# Run the Shiny app directly (no Shiny Server needed for single-app deploy)
CMD ["R", "-e", \
    "shiny::runApp('/app/app_v1.0.4.R', host='0.0.0.0', port=3838, launch.browser=FALSE)"]
