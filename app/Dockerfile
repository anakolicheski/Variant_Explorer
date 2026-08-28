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
    options(renv.config.repos.override = c( \
      CRAN = 'https://cloud.r-project.org', \
      BioCsoft = 'https://bioconductor.org/packages/3.18/bioc', \
      BioCann  = 'https://bioconductor.org/packages/3.18/data/annotation' \
    )); \
    renv::restore(prompt = FALSE) \
"

# ── Copy app files ────────────────────────────────────────────────────────────
COPY app_v1.0.4.R          ./
COPY variant_upload_module.R ./
COPY lolliplot_module.R      ./

# Optional files — copy if they exist (won't fail if missing)
COPY col_state_v2.json*      ./ 2>/dev/null || true
COPY candidates.csv*         ./ 2>/dev/null || true
COPY column_mapping_config.json* ./ 2>/dev/null || true
COPY FRESH_DATABASE_SETUP_GUIDE.md* ./ 2>/dev/null || true

# Create directories that will be bind-mounted from the host
RUN mkdir -p annotations New_genotypes www

# ── Runtime ───────────────────────────────────────────────────────────────────
EXPOSE 3838

# Run the Shiny app directly (no Shiny Server needed for single-app deploy)
CMD ["R", "-e", \
    "shiny::runApp('/app/app_v1_0_1.R', host='0.0.0.0', port=3838, launch.browser=FALSE)"]
