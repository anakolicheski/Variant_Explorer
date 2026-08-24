library(stringr)
library(shiny)
library(shinythemes)
library(tidyverse)
library(readxl)
library(DT)
library(jsonlite)
library(httr)
library(purrr)
library(dplyr)
library(readr)

# Source modules
cat("Sourcing variant_upload_module.R...\n")
source("variant_upload_module.R")
cat("✓ variant_upload_module.R loaded\n")

cat("Sourcing lolliplot_module.R...\n")
source("lolliplot_module.R")
cat("✓ lolliplot_module.R loaded\n")

cat(sprintf("variantUploadModuleUI exists: %s\n", exists("variantUploadModuleUI")))
cat(sprintf("variantUploadServer exists: %s\n", exists("variantUploadServer")))
cat("\n")

# ── Load genotypes ────────────────────────────────────────────────────────────
list_of_files <- list.files(path = "New_genotypes/", pattern = "_geno\\.tsv$", full.names = TRUE)

if (length(list_of_files) > 0) {
  Genotypes     <- lapply(list_of_files, function(f) {
    read_tsv(f, show_col_types = FALSE, col_types = cols(.default = "c"))
  })
  list_of_files <- tools::file_path_sans_ext(basename(list_of_files))
  list_of_files <- str_remove(list_of_files, "_geno$")
  names(Genotypes) <- list_of_files
  list2env(Genotypes, envir = .GlobalEnv)
} else {
  Genotypes     <- list()
  list_of_files <- character()
}

# Reload genotypes after a new upload
reload_genotypes <- function() {
  list_of_files <<- list.files(path = "New_genotypes/", pattern = "_geno\\.tsv$", full.names = TRUE)
  if (length(list_of_files) > 0) {
    Genotypes     <<- lapply(list_of_files, function(f) {
      read_tsv(f, show_col_types = FALSE, col_types = cols(.default = "c"))
    })
    list_of_files <<- tools::file_path_sans_ext(basename(list_of_files))
    list_of_files <<- str_remove(list_of_files, "_geno$")
    names(Genotypes) <<- list_of_files
    list2env(Genotypes, envir = .GlobalEnv)
  } else {
    Genotypes     <<- list()
    list_of_files <<- character()
  }
}

# ── UI ────────────────────────────────────────────────────────────────────────
ui <- fluidPage(
  theme = shinytheme("flatly"),
  titlePanel("Genetic Variants"),

  # ── Global CSS ────────────────────────────────────────────────────────────
  tags$style(HTML("

    /* ── Row height: truncate long cell content with ellipsis ─────────────
       Prevents wide/verbose fields (HGVSc, ClinVar, gnomAD notes) from
       stretching rows. Hover over a cell to see the full value via the
       browser tooltip (DataTables adds the title attribute automatically). */
    table.dataTable tbody td {
      white-space:     nowrap;
      overflow:        hidden;
      text-overflow:   ellipsis;
      max-width:       300px;
    }

    /* Keep zygosity colour spans readable — don't clip the background */
    table.dataTable tbody td span[style*='background'] {
      display: block;
      overflow: hidden;
      text-overflow: ellipsis;
    }

    /* ── Column filter inputs: bigger, clearer, always visible ─────────────
       DT renders filter inputs as input[type=search] inside th elements.
       The th inherits overflow:hidden from DataTables which clips text;
       we override that. Unquoted attribute selectors (valid CSS) avoid
       any escaping issues inside R strings. */

    /* Allow the header cell to show the full input without clipping */
    table.dataTable thead th,
    table.dataTable tfoot th {
      overflow: visible;
      position: relative;
    }

    /* Target DT filter inputs — unquoted attr values are valid CSS */
    table.dataTable thead input[type=search],
    table.dataTable thead input[type=text],
    table.dataTable thead select,
    table.dataTable tfoot input[type=search],
    table.dataTable tfoot input[type=text],
    table.dataTable tfoot select {
      width:            100% !important;
      box-sizing:       border-box !important;
      font-size:        13px;
      font-family:      inherit;
      height:           30px;
      padding:          3px 8px;
      border:           1px solid #c8c8c8;
      border-radius:    3px;
      background-color: #ffffff !important;
      color:            #222222 !important;
      overflow:         visible;
      text-overflow:    clip;
      white-space:      nowrap;
    }

    table.dataTable thead input[type=search]:focus,
    table.dataTable thead input[type=text]:focus,
    table.dataTable tfoot input[type=search]:focus,
    table.dataTable tfoot input[type=text]:focus {
      background-color: #fffde7 !important;
      border-color:     #2196F3 !important;
      color:            #000000 !important;
      outline:          none !important;
      box-shadow:       0 0 0 2px rgba(33,150,243,.25) !important;
      position:         relative;
      z-index:          10;
    }

    table.dataTable thead input[type=search]::placeholder,
    table.dataTable tfoot input[type=search]::placeholder {
      color:   #aaa;
      opacity: 1;
    }

  ")),

  # ── Global JS fixes applied once at page load ──────────────────────────
  tags$script(HTML("
    $(document).ready(function() {

      // ── Fix 1: Prevent horizontal scroll-jump when clicking filter inputs ──
      // When a filter input inside .dataTables_scrollHead gets focus, the
      // browser tries to scroll it into view, which resets scrollLeft.
      // We intercept the scroll event on the wrapper and lock it back.
      $(document).on('focus', '.dataTables_scrollHead input, .dataTables_scrollHead select', function() {
        var wrapper = $(this).closest('.dataTables_wrapper');
        var body    = wrapper.find('.dataTables_scrollBody');
        var head    = wrapper.find('.dataTables_scrollHead');
        var pos     = body.scrollLeft();

        // Lock scroll on both containers while input is active
        var lock = function() {
          body.scrollLeft(pos);
          head.scrollLeft(pos);
        };
        body.on('scroll.dtlock', lock);
        head.on('scroll.dtlock', lock);

        $(this).one('blur', function() {
          body.off('scroll.dtlock');
          head.off('scroll.dtlock');
        });
      });

      // ── Fix 2: Include NA rows when a numeric range filter is active ────────
      // DT's built-in range filter excludes rows where the cell value is NaN.
      // This extension re-adds them so that unscored variants (gnomAD NA,
      // CADD NA, etc.) stay visible when the user sets a range filter.
      $.fn.dataTable.ext.search.push(function(settings, data, dataIndex) {
        // Find all range filter inputs for this table
        var wrapper = $(settings.nTable).closest('.dataTables_wrapper');
        var inputs  = wrapper.find('thead input[type=search]');
        var pass    = true;

        inputs.each(function(idx) {
          var val = parseFloat(data[idx]);
          if (!isNaN(val)) return; // numeric value — let the normal filter handle it

          // Value is NaN (was NA in R). Check if the column actually has an
          // active range filter; if so, still include this row.
          var min = parseFloat($(this).attr('data-min') || '');
          var max = parseFloat($(this).attr('data-max') || '');
          if (!isNaN(min) || !isNaN(max)) {
            // NA row with an active range filter — include it (don't exclude)
            pass = true;
          }
        });

        return pass;
      });

    });
  ")),

  # Bootstrap popover initialisation
  tags$script(HTML(
    "$(function() {
       $(document).on('click', '[data-toggle=\"popover\"]', function(e) {
         e.stopPropagation();
         $(this).popover('toggle');
       });
       $(document).on('click', function(e) {
         if (!$(e.target).closest('[data-toggle=\"popover\"]').length) {
           $('[data-toggle=\"popover\"]').popover('hide');
         }
       });

     });"
  )),

  sidebarLayout(
    sidebarPanel(
      uiOutput("dynamic_sidebar")
    ),

    mainPanel(
      tabsetPanel(
        id = "main_tabs",
        selected = "Genetic Variants",

        # ── Genetic Variants ─────────────────────────────────────────────────
        tabPanel("Genetic Variants",
          fluidRow(
            column(4, plotOutput("ConsequencePieChart",  height = "300px")),
            column(4, plotOutput("PHRED_Histogram",      height = "300px"))
          ),
          br(),
          # ── Column layout controls ──────────────────────────────────────
          wellPanel(
            style = "padding: 8px 12px; background: #f0f4f8; border: 1px solid #c8d8e8;",
            fluidRow(
              column(12,
                tags$strong("Column Layout: "),
                tags$span(style = "font-size:12px; color:#888; margin-left:6px;",
                          "Reorder changes require a page refresh (F5) to display."),
                tags$span("Drag columns to reorder, use 'Columns' button to show/hide. ",
                          style = "color: #666; font-size: 0.9em;"),
                actionButton("save_col_layout",  "💾 Save Layout for Next Session",
                             class = "btn-sm btn-success", style = "margin-left:10px;"),
                actionButton("reset_col_layout", "↺ Reset All Layouts",
                             class = "btn-sm btn-warning", style = "margin-left:5px;"),
                tags$span(textOutput("col_layout_status", inline = TRUE),
                          style = "margin-left:10px; color: #555; font-size:0.9em;")
              )
            )
          ),
          DT::DTOutput("Variant_Type"),
          br(),
          DT::DTOutput("Matching_ID_Table"),
          h3("Variants + Genotypes"),
          DT::DTOutput("GeneList_Genotype_Table"),
          br(),
          downloadButton("downloadGeneListGenotypes", "Download Variants and Genotypes"),
          downloadButton("downloadVariantType",       "Download Variant Types")
        ),

        # ── Phenotypes ───────────────────────────────────────────────────────
        tabPanel("Phenotypes",
          fluidRow(
            column(12,
              h4("Phenotype Table"),
              helpText("Double-click any cell to edit. Add/remove rows and save changes below."),
              DT::DTOutput("Phenotypes_Table"),
              br(),
              actionButton("pheno_add_row",    "Add Row",             class = "btn-default"),
              actionButton("pheno_delete_row", "Delete Selected Row", class = "btn-danger"),
              actionButton("pheno_save",       "Save Changes",        class = "btn-success"),
              downloadButton("downloadPhenoTable", "Download Phenotype Table")
            )
          )
        ),

        # ── Common Variants ──────────────────────────────────────────────────
        tabPanel("Common Variants",
          tags$h4("Joined Table (Union of Variants Across Selected Samples/Families)"),
          tags$h5("All variants in the families selected on the sidebar. Download to sort and analyse."),
          DT::DTOutput("Joined_Table"),
          tags$h4("Variants Shared by Selected Samples/Families"),
          DT::DTOutput("Joined_Table_matching"),
          downloadButton("downloadJoinedTable",        "Download Joined Table"),
          downloadButton("downloadmatchedJoinedTable", "Download Matched Joined Table")
        ),

        # ── Common Genes ─────────────────────────────────────────────────────
        tabPanel("Common Genes by Patient Table",
          fluidRow(
            column(9, plotOutput("CommonGenesPlot", height = "420px")),
            column(3,
              br(),
              sliderInput("top_genes_n", "Top N genes to show:",
                          min = 5, max = 50, value = 20, step = 5),
              helpText("Bars show how many of the selected patients carry a variant in each gene.")
            )
          ),
          br(),
          DT::DTOutput("Joined_Gene_Table"),
          downloadButton("downloadGeneTable", "Download Gene Table")
        ),

        # ── Candidate Variants ───────────────────────────────────────────────
        tabPanel("Candidate Variants",
          h3("Candidate Variants for Review"),
          helpText("Select a row in any variant table then click one of the buttons below to capture it here. Double-click cells to edit notes."),
          fluidRow(
            column(3, actionButton("cand_from_variant_type",   "Add from Variant Table",         class = "btn-primary")),
            column(3, actionButton("cand_from_genotype_table", "Add from Variants+Genotypes",    class = "btn-primary")),
            column(3, actionButton("cand_from_matching",       "Add from Matching ID Table",     class = "btn-primary")),
            column(3, actionButton("cand_from_joined",         "Add from Joined Patients Table", class = "btn-primary"))
          ),
          br(),
          fluidRow(
            column(4, textInput("cand_new_col_name", "Add custom column:", placeholder = "e.g. Segregation")),
            column(2, br(), actionButton("cand_add_col", "Add Column", class = "btn-info"))
          ),
          br(),
          DT::DTOutput("candidate_variants_table"),
          br(),
          actionButton("cand_delete_row", "Delete Selected Row", class = "btn-danger"),
          actionButton("cand_save",       "Save Changes",        class = "btn-success"),
          downloadButton("downloadCandidateVariants", "Download Candidate Variants")
        ),

        # ── Lollipop Plot ────────────────────────────────────────────────────
        tabPanel("Lollipop Plot",
          lolliplotUI("geneLollipop")
        ),

        # ── Alignment Paths ──────────────────────────────────────────────────
        tabPanel("Alignment paths",
          DT::DTOutput("Cram_paths")
        ),

        # ── Variant Upload ───────────────────────────────────────────────────
        tabPanel("Variant Upload",
          variantUploadModuleUI("variant_upload"),
          hr(),
          actionButton("refresh_data", "Refresh Data After Upload", class = "btn-primary")
        ),

        # ── Tutorial ─────────────────────────────────────────────────────────
        tabPanel("Tutorial",
          if (file.exists("FRESH_DATABASE_SETUP_GUIDE.md")) {
            includeMarkdown("FRESH_DATABASE_SETUP_GUIDE.md")
          } else {
            p("Tutorial file (FRESH_DATABASE_SETUP_GUIDE.md) not found in the app directory.", style = "color:grey;")
          }
        )
      )
    )
  )
)

# ── Server ────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  options(shiny.maxRequestSize = 100 * 1024^2)

  cat("\n=== APP STARTUP DEBUG ===\n")
  cat(sprintf("Working directory: %s\n", getwd()))
  cat(sprintf("Annotation file exists: %s\n", file.exists("annotations/annotations_fordb.tsv")))
  if (dir.exists("annotations"))   cat(sprintf("Files in annotations/: %s\n",   paste(list.files("annotations",   full.names = TRUE), collapse = ", ")))
  if (dir.exists("New_genotypes")) cat(sprintf("Files in New_genotypes/: %s\n", paste(list.files("New_genotypes", pattern = "\\.tsv$"), collapse = ", ")))
  cat("=========================\n\n")

  # ── Load annotation data ──────────────────────────────────────────────────
  cat(">>> Loading variants\n")
  # Columns that should be numeric for DT range-slider filtering.
  # All data is read as character (col_types = "c") so we coerce these
  # explicitly before handing to datatable(). NA stays NA — DT handles it
  # correctly for numeric columns (excluded from range filter, shown as blank).
  # Only coerce columns that have range sliders in the TABLE itself.
  # gnomAD AF columns are intentionally excluded — they are filtered via the
  # sidebar slider (see gnomad_af_filter input) which avoids the scroll-jump
  # bug that occurs when numeric range sliders appear inside scrollX thead.
  NUMERIC_COLS <- c(
    "Pos", "PHRED",
    "CADD_RAW", "Alpha_Missense"
  )

  # Apply numeric coercion to any of NUMERIC_COLS that exist in df
  coerce_numeric <- function(df) {
    for (col in intersect(NUMERIC_COLS, names(df))) {
      df[[col]] <- suppressWarnings(as.numeric(df[[col]]))
    }
    df
  }

  # Clean duplicate columns (e.g. gnomADg_AF...58) created by readr when the
  # source file has repeated column names — keeps first occurrence, strips ...N
  dedup_columns <- function(df) {
    nms      <- names(df)
    # Strip readr auto-suffixes for duplicate/empty headers (e.g. ...25, ..26)
    base_nms <- sub("\\.\\.\\.\\d+$", "", nms)
    base_nms <- sub("\\.\\.\\d+$",      "", base_nms)
    base_nms <- trimws(base_nms)
    # Drop columns with empty names — caused by Excel saving blank header cells
    non_empty <- nchar(base_nms) > 0
    df        <- df[, non_empty, drop = FALSE]
    base_nms  <- base_nms[non_empty]
    # Drop duplicate column names, keep first occurrence
    keep      <- !duplicated(base_nms)
    df        <- df[, keep, drop = FALSE]
    names(df) <- base_nms[keep]
    df
  }
  initial_variants <- {
    anno_file <- "annotations/annotations_fordb.tsv"
    if (file.exists(anno_file)) {
      df <- read_tsv(anno_file, show_col_types = FALSE, col_types = cols(.default = "c"), name_repair = "minimal")
      df <- dedup_columns(df)
      cat(sprintf("Loaded annotation file: %d rows, %d columns\n", nrow(df), ncol(df)))
      cat(sprintf("First few columns: %s\n", paste(head(names(df), 10), collapse = ", ")))
      df
    } else {
      cat("No annotation file found, returning empty tibble\n")
      tibble(CHROM = character(), Pos = character(), Ref = character(), Alt = character(),
             GeneName = character(), Consequence = character(), ID = character())
    }
  }
  variants <- reactiveVal(initial_variants)
  cat(">>> Created variants reactiveVal\n")

  # ── Load phenotype / CRAM tables ─────────────────────────────────────────
  pheno_initial <- if (file.exists("Phenotypes.xlsx")) {
    read_excel("Phenotypes.xlsx")
  } else {
    tibble(Patient = character(), Term_1 = character(), Term_2 = character(),
           Term_3 = character(), Term_4 = character(), Term_5 = character())
  }

  crams <- if (file.exists("cram_paths.xlsx")) {
    read_excel("cram_paths.xlsx")
  } else {
    tibble(Patient = character(), CRAM_path = character())
  }

  # ── Reactives ─────────────────────────────────────────────────────────────
  uploaded_genes <- reactiveVal(NULL)
  all_genotypes  <- reactiveVal()
  pheno_rv       <- reactiveVal(pheno_initial)
  variant_col_reorder <- reactiveVal(NULL)
  
  # Persist sidebar selections across tab switches
  selected_phenotype_terms <- reactiveVal(character(0))
  selected_patients        <- reactiveVal(character(0))

  # Per-tab variant filter state — each of the three filter tabs (Genetic
  # Variants, Common Variants, Common Genes) keeps independent filter values
  # that are saved when inputs change and restored when switching back to that tab.
  saved_filters <- reactiveValues(gv = NULL, cv = NULL, cg = NULL)

  get_tab_key <- function(tab) switch(tab,
    "Genetic Variants"              = "gv",
    "Common Variants"               = "cv",
    "Common Genes by Patient Table" = "cg",
    NULL
  )

  # Capture current filter state; debounced so it reads AFTER inputs have
  # settled following a tab switch (the sidebar re-renders with defaults
  # before the restore observer fires — 600ms clears both)
  current_filter_state_raw <- reactive({
    list(
      tab               = input$main_tabs,
      Variant_Type      = input$Variant_Type,
      cadd_filter       = input$cadd_filter,
      gnomad_af_filter  = input$gnomad_af_filter,
      gnomad_novel_only = input$gnomad_novel_only,
      gnomad_af_col     = input$gnomad_af_col
    )
  })
  current_filter_state <- debounce(current_filter_state_raw, 600)

  observe({
    s   <- current_filter_state()
    key <- get_tab_key(s$tab)
    if (is.null(key)) return()
    saved_filters[[key]] <- s[setdiff(names(s), "tab")]
  })

  # Restore saved filter state when switching to a filter tab
  observeEvent(input$main_tabs, {
    key <- get_tab_key(input$main_tabs)
    if (is.null(key)) return()
    f <- saved_filters[[key]]
    if (is.null(f)) return()
    if (!is.null(f$Variant_Type))
      updateCheckboxGroupInput(session, "Variant_Type",      selected = f$Variant_Type)
    if (!is.null(f$cadd_filter))
      updateSliderInput(session,        "cadd_filter",        value    = f$cadd_filter)
    if (!is.null(f$gnomad_af_filter))
      updateSliderInput(session,        "gnomad_af_filter",   value    = f$gnomad_af_filter)
    if (!is.null(f$gnomad_novel_only))
      updateCheckboxInput(session,      "gnomad_novel_only",  value    = f$gnomad_novel_only)
    if (!is.null(f$gnomad_af_col))
      updateSelectizeInput(session,     "gnomad_af_col",      selected = f$gnomad_af_col)
  })

  # ── Column state: two layers ──────────────────────────────────────────────
  # col_state        – in-memory, updated live as user drags/hides (session only)
  # col_state_saved  – written to disk only when user clicks "Save Layout"
  #                    and loaded back on next app start
  col_state_file <- "col_state_v2.json"  # bumped: v1 files were saved under the old
                                          # rownames=TRUE column indexing and are no
                                          # longer structurally compatible

  # Load saved-to-disk preferences (persists across restarts)
  col_state_saved_init <- if (file.exists(col_state_file)) {
    tryCatch(jsonlite::read_json(col_state_file, simplifyVector = TRUE),
             error = function(e) list())
  } else list()

  # col_state: live session state (starts from saved prefs, updated as user works)
  col_state <- do.call(reactiveValues, col_state_saved_init)

  # Track whether the user has unsaved in-session changes
  col_state_dirty <- reactiveVal(FALSE)

  # ── Initialise all_genotypes ──────────────────────────────────────────────
  observe({
    cat(">>> Initialising all_genotypes\n")
    if (length(names(Genotypes)) > 0) {
      all_genotypes(bind_rows(lapply(names(Genotypes), function(patient_file) {
        df <- Genotypes[[patient_file]] %>%
          mutate_all(as.character) %>%
          mutate(across(where(is.character), trimws))
        df$Patient <- patient_file
        df
      })))
    } else {
      all_genotypes(tibble(ID = character(), Patient = character()))
    }
    cat(">>> all_genotypes initialised\n")
  })

  # ── Variant upload module ─────────────────────────────────────────────────
  cat("\nCalling variantUploadServer...\n")
  uploaded_data <- variantUploadServer("variant_upload")
  cat("✓ variantUploadServer call completed\n\n")

  # ── Dynamic sidebar ───────────────────────────────────────────────────────
  output$dynamic_sidebar <- renderUI({
    tab <- input$main_tabs

    if (tab == "Genetic Variants") {
      tagList(
        fileInput("geneListFile", "Upload Gene List", accept = c(".csv", ".tsv")),
        uiOutput("variant_type_filter"),
        sliderInput("cadd_filter", "Filter by CADD PHRED Score:",
                    min = 0, max = 50, value = c(0, 50), step = 1),
        helpText("PHRED scores > 20 are generally considered deleterious"),
        hr(),
        h5("gnomAD Population Frequency", style = "margin-bottom:4px;"),
        uiOutput("gnomad_col_selector"),
        sliderInput("gnomad_af_filter",
                    label    = "Max allele frequency:",
                    min      = 0, max = 1, value = 1, step = 0.001),
        checkboxInput("gnomad_novel_only",
                      label = "Show ONLY novel variants (absent from gnomAD)",
                      value = FALSE),
        helpText("Novel variants (NA) have no frequency in gnomAD — often de novo or population-specific.")
      )

    } else if (tab == "Common Variants") {
      tagList(
        selectInput("PhenotypeTerm", "Filter by Phenotype Term:",
                    choices = NULL, selected = NULL, multiple = TRUE),
        selectInput("Patient", "Filter by Sample/Family:",
                    choices  = if (length(names(Genotypes)) > 0) names(Genotypes) else character(0),
                    multiple = TRUE),
        hr(),
        h5("Variant Filters", style = "margin-bottom:4px;"),
        helpText("Independent of Genetic Variants and Common Genes filters."),
        fileInput("geneListFile", "Upload Gene List", accept = c(".csv", ".tsv")),
        uiOutput("variant_type_filter"),
        sliderInput("cadd_filter", "Filter by CADD PHRED Score:",
                    min = 0, max = 50, value = c(0, 50), step = 1),
        helpText("PHRED scores > 20 are generally considered deleterious"),
        hr(),
        h5("gnomAD Population Frequency", style = "margin-bottom:4px;"),
        uiOutput("gnomad_col_selector"),
        sliderInput("gnomad_af_filter",
                    label    = "Max allele frequency:",
                    min      = 0, max = 1, value = 1, step = 0.001),
        checkboxInput("gnomad_novel_only",
                      label = "Show ONLY novel variants (absent from gnomAD)",
                      value = FALSE),
        helpText("Slider filters by max population AF. Variants absent from gnomAD (NA) are always included unless \"Novel only\" is checked.")
      )

    } else if (tab == "Common Genes by Patient Table") {
      tagList(
        selectInput("PhenotypeTerm", "Filter by Phenotype Term:",
                    choices = NULL, selected = NULL, multiple = TRUE),
        selectInput("Patient", "Filter by Sample/Family:",
                    choices  = if (length(names(Genotypes)) > 0) names(Genotypes) else character(0),
                    multiple = TRUE),
        hr(),
        h5("Variant Filters", style = "margin-bottom:4px;"),
        helpText("Independent of Genetic Variants and Common Variants filters."),
        fileInput("geneListFile", "Upload Gene List", accept = c(".csv", ".tsv")),
        uiOutput("variant_type_filter"),
        sliderInput("cadd_filter", "Filter by CADD PHRED Score:",
                    min = 0, max = 50, value = c(0, 50), step = 1),
        helpText("PHRED scores > 20 are generally considered deleterious"),
        hr(),
        h5("gnomAD Population Frequency", style = "margin-bottom:4px;"),
        uiOutput("gnomad_col_selector"),
        sliderInput("gnomad_af_filter",
                    label    = "Max allele frequency:",
                    min      = 0, max = 1, value = 1, step = 0.001),
        checkboxInput("gnomad_novel_only",
                      label = "Show ONLY novel variants (absent from gnomAD)",
                      value = FALSE),
        helpText("Slider filters by max population AF. Variants absent from gnomAD (NA) are always included unless \"Novel only\" is checked.")
      )

    } else if (tab == "Phenotypes") {
      tagList(
        selectInput("PhenotypeTerm", "Filter by Phenotype Term:",
                    choices = NULL, selected = NULL, multiple = TRUE)
      )

    } else if (tab == "Lollipop Plot") {
      tagList(
        uiOutput("variant_type_filter"),
        sliderInput("cadd_filter", "Filter by CADD PHRED Score:",
                    min = 0, max = 50, value = c(0, 50), step = 1)
      )

    } else {
      helpText("No filters apply to this tab.")
    }
  })
  outputOptions(output, "dynamic_sidebar", suspendWhenHidden = FALSE)

  # ── gnomAD AF column selector ─────────────────────────────────────────────
  # Known AF column candidates in priority order — first one found in the
  # loaded annotation file is selected by default
  AF_COL_CANDIDATES <- c(
    "db_pop_freq_max", "db_pop_freq_max_AF",
    "gnomADe_AF", "gnomADg_AF", "gnomADw_AF",
    "MAX_AF", "AF"
  )

  output$gnomad_col_selector <- renderUI({
    av_cols <- names(variants())
    af_cols <- intersect(AF_COL_CANDIDATES, av_cols)
    # Also pick up any other columns that look like AF columns not in the list
    extra   <- av_cols[grepl("_AF$|^AF$|^MAX_AF", av_cols, ignore.case = TRUE)]
    choices <- unique(c(af_cols, extra))
    if (length(choices) == 0) {
      helpText("No allele frequency columns found in annotation file.")
    } else {
      selectInput("gnomad_af_col",
                  label    = "Frequency column:",
                  choices  = choices,
                  selected = choices[1])
    }
  })

  # ── Dynamic variant type filter UI ────────────────────────────────────────
  output$variant_type_filter <- renderUI({
    variant_data <- variants()
    if (nrow(variant_data) == 0 || !"Consequence" %in% names(variant_data)) {
      return(checkboxGroupInput("Variant_Type", "Filter by Variant Type:",
                                choices = c("Select All" = "all"), selected = "all"))
    }
    conseqs       <- sort(unique(na.omit(variant_data$Consequence)))
    display_names <- tools::toTitleCase(gsub("_", " ", conseqs))
    choices       <- c("Select All" = "all", "Deselect All" = "none", setNames(conseqs, display_names))
    checkboxGroupInput("Variant_Type", "Filter by Variant Type:", choices = choices, selected = "all")
  })

  # ── Refresh data after upload ─────────────────────────────────────────────
  observeEvent(input$refresh_data, {
    reload_genotypes()
    if (file.exists("annotations/annotations_fordb.tsv")) {
      df_refresh <- read_tsv("annotations/annotations_fordb.tsv",
                             show_col_types = FALSE, col_types = cols(.default = "c"),
                             name_repair = "minimal")
      variants(dedup_columns(df_refresh))
    }
    if (length(names(Genotypes)) > 0) {
      all_genotypes(bind_rows(lapply(names(Genotypes), function(patient_file) {
        df <- Genotypes[[patient_file]] %>%
          mutate_all(as.character) %>%
          mutate(across(where(is.character), trimws))
        df$Patient <- patient_file
        df
      })))
    } else {
      all_genotypes(tibble(ID = character(), Patient = character()))
    }
    updateSelectInput(session, "Patient",
                      choices = if (length(names(Genotypes)) > 0) names(Genotypes) else character(0))
    showModal(modalDialog(
      title = "Data Refreshed",
      sprintf("Reloaded!\n\nVariants: %d\nSamples: %d",
              nrow(variants()), length(names(Genotypes))),
      easyClose = TRUE
    ))
  })

  # ── Gene list upload ──────────────────────────────────────────────────────
  observeEvent(input$geneListFile, {
    req(input$geneListFile)
    gene_data <- read.csv(input$geneListFile$datapath)
    if ("Gene" %in% colnames(gene_data)) {
      uploaded_genes(gene_data$Gene)
    } else {
      showModal(modalDialog(title = "Error",
        "The uploaded file does not contain a column named 'Gene'.", easyClose = TRUE))
      uploaded_genes(NULL)
    }
  })

  # ── Zygosity colouring helper ─────────────────────────────────────────────
  # NOTE: previously used formatStyle(target = "cell"), which colors cells via
  # a JS callback fired on cell creation. That callback doesn't reliably re-fire
  # on every redraw (sort/search) once the ColReorder extension + our custom
  # columnDefs (for saved column visibility) are in the mix, so the color would
  # disappear after sorting. Baking the color into the cell's HTML itself makes
  # it part of the data, so it survives redraws regardless of row order.
  zygosity_color_map <- c(
    "Het" = "yellow", "het" = "yellow",
    "Hom Ref" = "lightgreen", "hom_ref" = "lightgreen", "hom ref" = "lightgreen",
    "Hom_Ref" = "lightgreen", "homref" = "lightgreen",
    "Hom Alt" = "tomato", "hom_alt" = "tomato", "hom alt" = "tomato",
    "Hom_Alt" = "tomato", "homalt" = "tomato"
  )

  color_zygosity_columns <- function(df) {
    genotype_cols <- names(df)[str_detect(names(df), "\\.zygosity$")]
    if (length(genotype_cols) == 0) return(df)

    for (col in genotype_cols) {
      vals  <- as.character(df[[col]])
      color <- unname(zygosity_color_map[vals])
      df[[col]] <- ifelse(
        !is.na(color),
        sprintf('<span style="display:block;margin:-4px -8px;padding:4px 8px;background-color:%s;">%s</span>',
                color, vals),
        vals
      )
    }
    df
  }


  
  #──── Table options: column visibility via ColVis, order via Shiny modal ──────
  dt_options <- function(id, extra_opts = list()) {
    base <- list(
      dom        = "Blfrtip",
      # Only ColVis in the buttons list — the Reorder button is injected via
      # DOM manipulation in initComplete to avoid DT's listButtons() choking
      # on a custom action button that has no 'extend' field.
      buttons    = list(),   # Reorder button injected via initComplete DOM
      scrollX        = TRUE,
      scrollCollapse = TRUE,
      autoWidth      = FALSE,
      pageLength     = 25,
      lengthMenu     = list(c(10, 25, 50, 100), c("10", "25", "50", "100")),

      initComplete = JS(sprintf("
        function(settings) {
          var api    = new $.fn.dataTable.Api(settings);
          var tblId  = '%s';

          // ── Inject Reorder button into the Buttons toolbar ────────────────
          // Done here rather than in the R buttons list because DT's internal
          // listButtons() errors on custom buttons without an 'extend' field.
          // Build button via DOM to avoid quote-escaping inside R strings
          var btn = document.createElement('button');
          btn.type = 'button';
          btn.className = 'dt-button';
          btn.style.marginLeft = '4px';
          btn.textContent = '\u21c5 Reorder Columns';
          $(btn).on('click', function() {
            Shiny.setInputValue('open_col_reorder', tblId, {priority: 'event'});
          });
          setTimeout(function() {
            var toolbar = $(api.table().container()).find('.dt-buttons');
            if (toolbar.length) toolbar.append(btn);
          }, 0);

          // ── Track column visibility for persistence ────────────────────────
          api.on('column-visibility', function() {
            var vis = [];
            api.columns().every(function() { vis.push(this.visible()); });
            Shiny.setInputValue('%s_col_vis', vis, {priority: 'event'});
          });
        }
      ", id, id))
    )
    modifyList(base, extra_opts)
  }

  #Helper Function so it easily applies to all tables and don't have to rewrite it to everyone of them 
  #just apply this to renderDT logic
  
  make_dt <- function(df, id, selection = "none", filter = "none", editable = FALSE) {

    zyg_cols  <- names(df)[str_detect(names(df), "\\.zygosity$")]
    df        <- color_zygosity_columns(df)
    # escape everything except the zygosity columns (which carry inline-styled HTML).
    # rownames = FALSE removes DT's hidden row-number column (column 0), which
    # previously shifted all column indices by 1 and caused ColReorder to drag
    # the wrong column. With rownames = FALSE, column indices match exactly
    # between R and the DataTables JS API.
    escape_arg <- if (length(zyg_cols) == 0) TRUE else -match(zyg_cols, names(df))

    # datatable() treats FALSE as "no editable" but a list enables cell editing
    # Read WITHOUT isolate so renderDT takes a reactive dependency on col_state[[id]].
    # This makes the table re-render immediately when Apply is clicked in the modal.
    state <- col_state[[id]]

    # ── Apply saved column order by reordering df before datatable() ───────────
    # No ColReorder JS needed — order is controlled entirely in R.
    if (!is.null(state$col_order_names)) {
      saved_ord <- unlist(state$col_order_names)
      valid     <- intersect(saved_ord, names(df))
      remaining <- setdiff(names(df), valid)
      df        <- df[, c(valid, remaining), drop = FALSE]
      # Recompute escape_arg for the new column positions
      zyg_cols_new <- names(df)[str_detect(names(df), "\\.zygosity$")]
      escape_arg   <- if (length(zyg_cols_new) == 0) TRUE else -match(zyg_cols_new, names(df))
    }

    # ── Build columnDefs for saved visibility (name-based) ────────────────────
    extra_col_defs <- list()
    vis       <- state$vis
    col_names <- state$col_names
    if (!is.null(vis) && all(vapply(vis, is.logical, logical(1))) &&
        !is.null(col_names) && length(col_names) == length(vis)) {
      saved_map <- setNames(unlist(vis), unlist(col_names))
      extra_col_defs <- Filter(Negate(is.null), lapply(seq_along(names(df)), function(i) {
        nm <- names(df)[i]
        v  <- saved_map[nm]
        if (!is.na(v)) list(targets = i - 1L, visible = as.logical(v)) else NULL
      }))
    }

    base_opts   <- dt_options(id)
    if (length(extra_col_defs) > 0)
      base_opts$columnDefs <- c(base_opts$columnDefs %||% list(), extra_col_defs)

    dt_args <- list(
      df,
      rownames   = FALSE,
      extensions = "Buttons",
      selection  = selection,
      filter     = filter,
      escape     = escape_arg,
      options    = base_opts
    )
    if (!isFALSE(editable)) dt_args$editable <- editable
    do.call(datatable, dt_args)
  }
  # ── Variant type select-all / deselect-all ────────────────────────────────
  observeEvent(input$Variant_Type, {
    req(input$Variant_Type)
    variant_data <- variants()
    all_variants <- if (nrow(variant_data) > 0 && "Consequence" %in% names(variant_data))
      sort(unique(na.omit(variant_data$Consequence))) else character(0)

    if ("all"  %in% input$Variant_Type && length(all_variants) > 0)
      updateCheckboxGroupInput(session, "Variant_Type", selected = all_variants)
    else if ("none" %in% input$Variant_Type)
      updateCheckboxGroupInput(session, "Variant_Type", selected = character(0))
  })

  # ── Sidebar state persistence ─────────────────────────────────────────────
  observe({ req(input$PhenotypeTerm); selected_phenotype_terms(input$PhenotypeTerm) })
  observe({ req(input$Patient);       selected_patients(input$Patient) })

  observe({
    req(input$main_tabs %in% c("Common Variants", "Common Genes by Patient Table", "Phenotypes"))
    all_terms <- sort(na.omit(unique(unlist(
      pheno_rv()[, intersect(c("Term_1","Term_2","Term_3","Term_4","Term_5"), names(pheno_rv()))]  ##add more terms if needed
    ))))
    updateSelectInput(session, "PhenotypeTerm",
                      choices = all_terms, selected = isolate(selected_phenotype_terms()))
  })

  observe({
    req(input$main_tabs %in% c("Common Variants", "Common Genes by Patient Table"))
    updateSelectInput(session, "Patient",
                      choices  = if (length(names(Genotypes)) > 0) names(Genotypes) else character(0),
                      selected = isolate(selected_patients()))
  })

  observeEvent(input$PhenotypeTerm, {
    req(input$PhenotypeTerm)
    matching_patients <- pheno_rv() %>%
      filter(if_any(starts_with("Term"), ~ . %in% input$PhenotypeTerm)) %>%
      pull(Patient) %>% unique()
    selected_patients(matching_patients)
    updateSelectInput(session, "Patient", selected = matching_patients)
  })

  # ── Variant_type_reac ─────────────────────────────────────────────────────
  Variant_type_reac_raw <- reactive({
    filtered_data <- variants()
    cat(sprintf("\n=== Variant_type_reac called ===\n"))
    cat(sprintf("Input data: %d rows, %d columns\n", nrow(filtered_data), ncol(filtered_data)))

    if (nrow(filtered_data) == 0) { cat("No data, returning empty\n"); return(filtered_data) }
    cat(sprintf("Column names: %s\n", paste(head(names(filtered_data), 10), collapse = ", ")))

    selected_types <- input$Variant_Type
    # NULL/empty means the checkbox UI has not rendered yet -- show all rows
    no_selection <- is.null(selected_types) || length(selected_types) == 0
    if (!no_selection && !("all" %in% selected_types)) {
      if ("Consequence" %in% names(filtered_data)) {
        cat(sprintf("Filtering by: %s\n", paste(selected_types, collapse = ", ")))
        filtered_data <- filtered_data %>% filter(Consequence %in% selected_types)
        cat(sprintf("After filter: %d rows\n", nrow(filtered_data)))
      }
    }

    if (!is.null(uploaded_genes()) && "GeneName" %in% names(filtered_data))
      filtered_data <- filtered_data %>% filter(GeneName %in% uploaded_genes())

    if (!is.null(input$cadd_filter) && "PHRED" %in% names(filtered_data)) {
      cadd_min <- input$cadd_filter[1]
      cadd_max <- input$cadd_filter[2]
      # No-op when slider is at its full default range (0–50)
      # Avoids silently dropping all unscored variants on startup
      is_cadd_noop <- (cadd_min == 0 && cadd_max >= 50)
      if (!is_cadd_noop) {
        cat(sprintf("CADD filter: %g - %g\n", cadd_min, cadd_max))
        # When the slider is moved from default, exclude unscored variants:
        # a PHRED threshold only makes sense for variants that have a score.
        filtered_data <- filtered_data %>%
          mutate(.phred = suppressWarnings(as.numeric(PHRED))) %>%
          filter(!is.na(.phred) & .phred >= cadd_min & .phred <= cadd_max) %>%
          dplyr::select(-.phred)
      }
    }

    # ── gnomAD AF sidebar filter ─────────────────────────────────────────────
    # The user picks which AF column to filter on via gnomad_af_col selector.
    # Falls back to first available candidate if the selector hasn't rendered yet.
    # Three modes:
    #   novel_only = TRUE  → show ONLY rows where AF is NA (not in gnomAD)
    #   novel_only = FALSE, include_na = TRUE  → AF <= slider threshold OR NA
    #   novel_only = FALSE, include_na = FALSE → AF <= slider threshold only
    af_col <- if (!is.null(input$gnomad_af_col) && input$gnomad_af_col %in% names(filtered_data)) {
      input$gnomad_af_col
    } else {
      # Fallback: use first available candidate column
      found <- intersect(AF_COL_CANDIDATES, names(filtered_data))
      if (length(found) > 0) found[1] else NULL
    }
    # gnomAD filter: NA variants are always included unless novel_only is checked.
    # Defaults: slider at 1.0, novel_only = FALSE → no filtering (show everything).
    gnomad_ready <- !is.null(input$gnomad_af_filter) && !is.null(af_col)
    if (gnomad_ready) {
      novel_only <- isTRUE(input$gnomad_novel_only)
      max_af     <- input$gnomad_af_filter
      is_noop    <- !novel_only && max_af >= 1
      if (!is_noop) {
        filtered_data <- filtered_data %>%
          mutate(.af = suppressWarnings(as.numeric(.data[[af_col]]))) %>%
          filter(
            if (novel_only) {
              is.na(.af)                                   # novel only: no gnomAD entry
            } else {
              is.na(.af) | (!is.na(.af) & .af <= max_af)  # rare + unobserved (always include NA)
            }
          ) %>%
          dplyr::select(-.af)
      }
    }

    # Coerce numeric columns so DT renders range-sliders (not text search)
    # for AF/PHRED fields, and NA is treated correctly as missing numeric
    filtered_data <- coerce_numeric(filtered_data)
    cat(sprintf("Output rows: %d, columns: %d\n", nrow(filtered_data), ncol(filtered_data)))
    filtered_data
  })
  # Simple debounce on the raw reactive — no bindCache wrapper.
  # bindCache(debounce(...)) adds delay even on cache hits; debounce(bindCache(...))
  # errors because debounce uses bindEvent internally.
  # 300ms collapses rapid startup/tab-switch invalidations without noticeable lag.
  Variant_type_reac <- debounce(Variant_type_reac_raw, 300)

  # ── Variant_Type DT – render ONCE, update data via proxy ─────────────────
  # renderDT is reactive to Variant_type_reac() so filtering works correctly.
  # ColReorder state is preserved by the shiny:value save + initComplete restore
  # in the global JS — no proxy/replaceData needed.
  output$Variant_Type <- renderDT({
    req(input$main_tabs == "Genetic Variants")
    df <- Variant_type_reac()
    make_dt(df, "Variant_Type", selection = "single", filter = "top")
  }, server = TRUE)

  # ── Column state save helpers ─────────────────────────────────────────────────────
  # Write current col_state to disk (called only on explicit user request)
  save_col_state_to_disk <- function() {
    tryCatch(
      jsonlite::write_json(isolate(reactiveValuesToList(col_state)),
                           col_state_file, auto_unbox = TRUE),
      error = function(e) warning("col_state save failed: ", e$message)
    )
  }
  # Save column order as a list of column NAMES (robust to column count changes)
  save_col_order_names <- function(id, col_name_vec) {
    state                  <- isolate(col_state[[id]]) %||% list()
    state$col_order_names  <- as.list(col_name_vec)
    col_state[[id]]        <- state
    col_state_dirty(TRUE)
  }


  save_col_vis <- function(id, vis) {
    state          <- isolate(col_state[[id]]) %||% list()
    state$vis      <- vis
    # Also store the column names at save-time so we can match by name
    # on restore even if the column count changes between sessions
    df_now <- tryCatch(
      isolate(switch(id,
        Variant_Type            = Variant_type_reac(),
        GeneList_Genotype_Table = GeneList_Genotype_Table(),
        Matching_ID_Table       = Matching_ID_Table(),
        Joined_Table            = Joined_Table(),
        Joined_Table_matching   = Joined_Table_matching(),
        Joined_Gene_Table       = Joined_Gene_Table(),
        candidate_variants_table = candidate_variants(),
        Phenotypes_Table        = pheno_rv(),
        Cram_paths              = crams,
        NULL
      )),
      error = function(e) NULL
    )
    if (!is.null(df_now)) state$col_names <- as.list(names(df_now))
    col_state[[id]] <- state
    col_state_dirty(TRUE)
  }

  # ── "Save Layout" button ──────────────────────────────────────────────────
  output$col_layout_status <- renderText({ "" })

  observeEvent(input$save_col_layout, {
    save_col_state_to_disk()
    col_state_dirty(FALSE)
    output$col_layout_status <- renderText({
      paste0("✓ Layout saved at ", format(Sys.time(), "%H:%M:%S"))
    })
    showNotification("Column layout saved for fixed tables. Common Variants and Common Genes layouts are session-only (patient-specific columns).",
                     type = "message", duration = 5)
  })

  # ── "Reset Layout" button ─────────────────────────────────────────────────
  observeEvent(input$reset_col_layout, {
    showModal(modalDialog(
      title = "Reset Column Layouts",
      "This will clear all saved column order and visibility preferences for ALL tables and reload the page.",
      footer = tagList(
        actionButton("confirm_reset_layout", "Yes, Reset", class = "btn-danger"),
        modalButton("Cancel")
      )
    ))
  })
  observeEvent(input$confirm_reset_layout, {
    # Wipe in-memory state
    all_table_ids <- c("Variant_Type", "GeneList_Genotype_Table", "Matching_ID_Table",
                       "Joined_Table", "Joined_Table_matching", "Joined_Gene_Table",
                       "candidate_variants_table", "Phenotypes_Table", "Cram_paths")
    for (id in all_table_ids) col_state[[id]] <- NULL
    # Wipe disk
    if (file.exists(col_state_file)) file.remove(col_state_file)
    col_state_dirty(FALSE)
    removeModal()
    showNotification("All column layouts reset. Reload the page to see default columns.",
                     type = "warning", duration = 5)
  })

  # ── One observeEvent per table for col order + visibility ─────────────────
  TABLE_IDS <- c("Variant_Type", "GeneList_Genotype_Table", "Matching_ID_Table",
                 "Joined_Table", "Joined_Table_matching", "Joined_Gene_Table",
                 "candidate_variants_table", "Phenotypes_Table", "Cram_paths")
  DYNAMIC_TABLE_IDS <- c("Joined_Table", "Joined_Table_matching", "Joined_Gene_Table")
  STATIC_TABLE_IDS  <- setdiff(TABLE_IDS, DYNAMIC_TABLE_IDS)

  lapply(TABLE_IDS, function(id) {
    vis_input <- paste0(id, "_col_vis")
    observeEvent(input[[vis_input]], {
      save_col_vis(id, input[[vis_input]])
    }, ignoreInit = TRUE)
  })
  
  # ── Column reorder modal ─────────────────────────────────────────────────
  # Triggered by the "⇅ Reorder Columns" DataTables button.
  # Shows a selectize drag_drop list: drag to reorder, deselect to hide.
  # Applies by re-rendering the table with reordered df columns (no JS needed).

  # Helper: get current column names for a table
  get_table_cols <- function(id) {
    tryCatch(isolate(switch(id,
      Variant_Type             = names(Variant_type_reac()),
      GeneList_Genotype_Table  = names(GeneList_Genotype_Table()),
      Matching_ID_Table        = names(Matching_ID_Table()),
      Joined_Table             = names(Joined_Table()),
      Joined_Table_matching    = names(Joined_Table_matching()),
      Joined_Gene_Table        = names(Joined_Gene_Table()),
      candidate_variants_table = names(candidate_variants()),
      Phenotypes_Table         = names(pheno_rv()),
      Cram_paths               = names(crams),
      character(0)
    )), error = function(e) character(0))
  }

  # Current order for a table (from col_state, else natural order)
  get_current_order <- function(id) {
    all_cols   <- get_table_cols(id)
    saved_ord  <- unlist(isolate(col_state[[id]])$col_order_names)
    if (!is.null(saved_ord) && length(saved_ord) > 0) {
      valid     <- intersect(saved_ord, all_cols)
      remaining <- setdiff(all_cols, valid)
      c(valid, remaining)
    } else {
      all_cols
    }
  }

  observeEvent(input$open_col_reorder, {
    id       <- input$open_col_reorder
    all_cols <- get_current_order(id)
    if (length(all_cols) == 0) return()

    saved   <- isolate(col_state[[id]])
    visible <- if (!is.null(saved$vis) && !is.null(saved$col_names)) {
      vis_map <- setNames(as.logical(unlist(saved$vis)), unlist(saved$col_names))
      all_cols[all_cols %in% names(vis_map)[vis_map]]
    } else {
      all_cols
    }

    showModal(modalDialog(
      title = "Manage Column Order & Visibility",
      size  = "m",
      if (id %in% DYNAMIC_TABLE_IDS) tags$div(
        style = "background:#fff3cd; border:1px solid #ffc107; border-radius:4px; padding:8px 12px; margin-bottom:10px; font-size:12px; color:#856404;",
        tags$strong("Session-only: "),
        "Columns here include patient-specific data. Changes apply this session only and are not saved."
      ),
      tags$p(style = "color:#555; font-size:13px;",
             "Drag tags to reorder. Click \u00d7 to hide. Use the input to re-add hidden columns."),
      selectizeInput(
        "col_reorder_input",
        label    = NULL,
        choices  = all_cols,
        selected = visible,
        multiple = TRUE,
        width    = "100%",
        options  = list(
          plugins     = list("drag_drop", "remove_button"),
          placeholder = "Start typing to add a hidden column back..."
        )
      ),
      footer = tagList(
        actionButton("apply_col_reorder", "Apply", class = "btn-primary"),
        actionButton("reset_col_reorder", "Reset to Default", class = "btn-default"),
        modalButton("Cancel")
      )
    ))
  })
  observeEvent(input$apply_col_reorder, {
    id       <- input$open_col_reorder
    new_ord  <- input$col_reorder_input
    all_cols <- get_table_cols(id)
    if (length(all_cols) == 0) { removeModal(); return() }

    # Single col_state write so table re-renders exactly once
    state                 <- isolate(col_state[[id]]) %||% list()
    state$col_order_names <- as.list(new_ord)
    state$col_names       <- as.list(all_cols)
    hidden_cols           <- setdiff(all_cols, new_ord)
    vis_vec               <- setNames(rep(TRUE, length(all_cols)), all_cols)
    vis_vec[hidden_cols]  <- FALSE
    state$vis             <- as.list(unname(vis_vec))
    col_state[[id]]       <- state
    is_dynamic <- id %in% DYNAMIC_TABLE_IDS
    if (!is_dynamic) col_state_dirty(TRUE)
    removeModal()
    if (is_dynamic) {
      showNotification(
        "Session-only layout applied. Patient-specific columns change with selection and are not saved.",
        type = "message", duration = 6
      )
    } else {
      showNotification(
        "Column layout saved. Changes take effect after refreshing (F5). Click 'Save Layout' to persist across sessions.",
        type = "message", duration = 6
      )
    }
  })
  observeEvent(input$reset_col_reorder, {
    id <- input$open_col_reorder
    state <- isolate(col_state[[id]]) %||% list()
    state$col_order_names <- NULL
    state$vis             <- NULL
    state$col_names       <- NULL
    col_state[[id]]       <- state
    col_state_dirty(TRUE)
    removeModal()
    showNotification("Column layout reset to default.", type = "message", duration = 3)
  })

  # ── Plots ─────────────────────────────────────────────────────────────────
  output$ConsequencePieChart <- renderPlot({
    req(input$main_tabs == "Genetic Variants")
    fd <- Variant_type_reac()
    if (nrow(fd) == 0 || !"Consequence" %in% names(fd)) return(NULL)
    counts <- fd %>%
      count(Consequence, name = "count") %>%
      arrange(desc(count))
    ggplot(counts, aes(x = "", y = count, fill = Consequence)) +
      geom_bar(stat = "identity", width = 1) + coord_polar("y", start = 0) +
      labs(title = "Variant Type Distribution", fill = "Consequence") +
      theme_minimal() +
      theme(axis.text = element_blank(), axis.ticks = element_blank(), panel.grid = element_blank())
  })

  output$PHRED_Histogram <- renderPlot({
    req(input$main_tabs == "Genetic Variants")
    fd <- Variant_type_reac()
    if (nrow(fd) == 0) return(NULL)
    fd <- fd %>%
      mutate(PHRED = suppressWarnings(as.numeric(PHRED))) %>%
      filter(!is.na(PHRED))
    if (nrow(fd) == 0) return(NULL)
    ggplot(fd, aes(x = PHRED)) +
      geom_histogram(bins = 30, fill = "steelblue", color = "black", alpha = 0.7) +
      theme_minimal() +
      labs(title = sprintf("PHRED Score Distribution (n = %s scored)", format(nrow(fd), big.mark = ",")),
           x = "CADD PHRED Score", y = "Count")
  })

  # ── GeneList_Genotype_Table ───────────────────────────────────────────────
  # Variant_type_DT_filtered: sidebar filters + DT column filters combined.
  # input$Variant_Type_rows_all = row indices DT considers visible after its
  # own column filtering (e.g. user typed "STAT" in GeneName filter).
  # Both GeneList_Genotype_Table and the download use this so they stay in sync.
  Variant_type_DT_filtered <- reactive({
    df   <- Variant_type_reac()
    rows <- input$Variant_Type_rows_all
    if (is.null(rows) || length(rows) == 0) return(df)
    valid <- rows[rows >= 1L & rows <= nrow(df)]
    if (length(valid) == 0) return(df)
    df[valid, , drop = FALSE]
  })

  GeneList_Genotype_Table <- reactive({
    # Use DT-filtered variants: respects both sidebar AND column filters
    # (e.g. typing 'STAT' in the GeneName column of the Variant_Type table)
    filtered_variants <- Variant_type_DT_filtered()
    if (nrow(filtered_variants) == 0) return(tibble())

    results <- all_genotypes() %>% inner_join(filtered_variants, by = "ID")
    if (nrow(results) == 0) return(tibble())

    # Drop columns that are entirely NA — keep everything else for ColVis
    results <- results %>%
      dplyr::select(where(function(x) any(!is.na(x))))
    coerce_numeric(results)
  })

  # ── Editable Phenotype Table ──────────────────────────────────────────────
  
  output$Phenotypes_Table <- renderDT({
    make_dt(
      pheno_rv(),
      "Phenotypes_Table",
      selection = "single",
      filter    = "top",
      editable  = list(target = "cell", disable = list(columns = 0))
    )
  }, server = TRUE)

  observeEvent(input$Phenotypes_Table_cell_edit, {
    info <- input$Phenotypes_Table_cell_edit
    df   <- pheno_rv()
    df[info$row, info$col] <- DT::coerceValue(info$value, df[info$row, info$col])
    pheno_rv(df)
  })

  observeEvent(input$pheno_add_row, {
    df      <- pheno_rv()
    new_row <- as_tibble(setNames(replicate(ncol(df), NA_character_, simplify = FALSE), names(df)))
    pheno_rv(bind_rows(df, new_row))
  })

  observeEvent(input$pheno_delete_row, {
    req(input$Phenotypes_Table_rows_selected)
    df <- pheno_rv()
    pheno_rv(df[-input$Phenotypes_Table_rows_selected, ])
  })

  observeEvent(input$pheno_save, {
    tryCatch({
      if (file.exists("Phenotypes.xlsx")) writexl::write_xlsx(pheno_rv(), "Phenotypes.xlsx")
      else write_csv(pheno_rv(), "Phenotypes.csv")
      showModal(modalDialog("Phenotype table saved!", easyClose = TRUE))
    }, error = function(e) {
      showModal(modalDialog(paste("Save failed:", e$message), easyClose = TRUE))
    })
  })

  output$downloadPhenoTable <- downloadHandler(
    filename = function() paste0("Phenotypes_", Sys.Date(), ".csv"),
    content  = function(file) write_csv(pheno_rv(), file)
  )

  # ── Other static outputs ──────────────────────────────────────────────────
  output$Cram_paths <- renderDT({
    make_dt(crams, "Cram_paths", filter = "top")
  })

  lolliplotServer("geneLollipop",
                  all_variants_reactive = variants,
                  variant_data_reactive = Variant_type_reac,
                  pheno                 = pheno_rv(),
                  list_of_files         = list_of_files)

  # ── Joined_Table ──────────────────────────────────────────────────────────
  Joined_Table <- reactive({
    req(input$Patient)
    genotype_tables <- map(input$Patient, ~ get(.x) %>% mutate_all(as.character))
    joined_tables   <- map(genotype_tables,
                           ~ inner_join(.x, Variant_type_reac(), by = "ID",
                                        suffix = c("_genotypes", "_variants")))
    joined_table    <- bind_rows(joined_tables) %>%
      filter(if_any(everything(), ~ str_detect(as.character(.), "Het|Hom.Alt")))

    # Return all columns (minus .y duplicates) — ColVis handles visibility
    result <- joined_table %>%
      dplyr::select(!matches("\\.y$")) %>%
      dplyr::select(where(function(x) any(!is.na(x))))
    coerce_numeric(result)
  })

  # ── Joined_Table_matching ─────────────────────────────────────────────────
  Joined_Table_matching <- reactive({
    req(input$Patient)

    pheno_ok <- is.data.frame(pheno_rv()) && nrow(pheno_rv()) > 0 &&
                all(c("Patient", "Term_1") %in% names(pheno_rv()))

    # For each patient keep only ID + zygosity columns (+ Term_1 from pheno)
    zygosity_tables <- map(input$Patient, ~ {
      patient <- .x
      geno    <- get(patient) %>% mutate_all(as.character)
      zyg_cols <- names(geno)[str_detect(names(geno), "\\.zygosity$")]
      if (length(zyg_cols) == 0) return(NULL)

      slice <- geno %>% dplyr::select(ID, all_of(zyg_cols))

      if (pheno_ok) {
        term     <- pheno_rv() %>% filter(Patient == patient) %>% pull(Term_1) %>% dplyr::first()
        term_col <- paste0(patient, ".Term_1")
        slice[[term_col]] <- if (length(term) == 0 || is.na(term)) NA_character_ else as.character(term)
      }
      slice
    })
    zygosity_tables <- Filter(Negate(is.null), zygosity_tables)
    if (length(zygosity_tables) == 0) return(tibble())

    all_zyg <- purrr::reduce(zygosity_tables, inner_join, by = "ID")

    result <- Variant_type_reac() %>%
      mutate_all(as.character) %>%
      inner_join(all_zyg, by = "ID")

    zygosity_columns <- names(result)[str_detect(names(result), "\\.zygosity$")]
    if (length(zygosity_columns) == 0) return(tibble())

    result <- result %>%
      filter(if_all(all_of(zygosity_columns), ~ str_detect(., "Het|Hom.Alt")))

    term1_columns <- names(result)[str_detect(names(result), "\\.Term_1$")]

    # Lead with key annotation cols, then zygosity and Term_1; ColVis handles the rest
    priority_cols    <- c("GeneName", "Consequence", "PHRED", "protein_change",
                          "HGVSc", "HGVSp", "Existing_variation",
                          "clinvar_CLINSIGN", "db_pop_freq_max")
    existing_priority <- intersect(priority_cols, names(result))
    other_cols        <- setdiff(names(result),
                                  c(existing_priority, zygosity_columns, term1_columns))

    result <- result %>%
      dplyr::select(all_of(c(existing_priority, zygosity_columns, term1_columns, other_cols))) %>%
      dplyr::select(where(function(x) any(!is.na(x))))
    coerce_numeric(result)
  })

  # ── Joined_Gene_Table ─────────────────────────────────────────────────────
  # Shared computation: build the big joined table once, used by both the
  # gene summary chart and the full Joined_Gene_Table DT
  gene_summary_raw <- reactive({
    req(input$Patient)
    genotype_forgene_tables <- map(input$Patient, ~ {
      tbl <- get(.x) %>% mutate(Patient = .x) %>% mutate_all(as.character)
      tbl
    })
    joined_gene_table <- map(genotype_forgene_tables,
                             ~ left_join(.x, Variant_type_reac(), by = "ID",
                                         suffix = c("_genotypes", "_variants")))
    big_joined <- bind_rows(joined_gene_table) %>%
      filter(if_any(everything(), ~ str_detect(as.character(.), "Het|Hom.Alt")))

    summary <- big_joined %>%
      group_by(GeneName) %>%
      summarise(Num_Patients = n_distinct(Patient), .groups = "drop") %>%
      arrange(desc(Num_Patients), GeneName)

    list(summary = summary, big_joined = big_joined)
  })

  Joined_Gene_Table <- reactive({
    d <- gene_summary_raw()
    d$summary %>%
      filter(Num_Patients > 1) %>%
      left_join(d$big_joined, by = "GeneName")
  })

  # ── Matching_ID_Table ─────────────────────────────────────────────────────
  Matching_ID_Table <- reactive({
    selected_row <- input$Variant_Type_rows_selected
    if (length(selected_row) == 0) return(tibble())

    selected_id <- Variant_type_reac()$ID[selected_row]
    geno        <- all_genotypes() %>% filter(ID %in% selected_id)

    pheno_ok <- is.data.frame(pheno_rv()) && nrow(pheno_rv()) > 0 &&
                all(c("Patient", "Term_1") %in% names(pheno_rv())) &&
                is.character(pheno_rv()$Patient)

    if (pheno_ok) {
      matching_results <- geno %>%
        mutate(Patient = as.character(Patient)) %>%
        left_join(
          pheno_rv() %>%
            dplyr::select(Patient, Term_1) %>%
            mutate(Patient = as.character(Patient)),
          by = "Patient"
        )
    } else {
      matching_results <- geno
      matching_results$Term_1 <- NA_character_
    }

    matching_results
  })

  # ── renderDT outputs ──────────────────────────────────────────────────────
  output$Matching_ID_Table <- renderDT({
    req(input$main_tabs == "Genetic Variants")
    df <- Matching_ID_Table()
    if (nrow(df) == 0) return(datatable(tibble(), options = list(dom = "t")))

    # Show only Patient, non-empty zygosity columns, and Term_1
    zyg_cols  <- names(df)[str_detect(names(df), "\\.zygosity$")]
    term_cols <- names(df)[str_detect(names(df), "Term_1")]
    has_value <- function(x) any(!is.na(x) & trimws(as.character(x)) != "" & as.character(x) != "NA")
    zyg_cols  <- zyg_cols[sapply(df[zyg_cols], has_value)]
    keep_cols <- intersect(c("Patient", zyg_cols, term_cols), names(df))
    df        <- df %>% dplyr::select(all_of(keep_cols))

    make_dt(df, "Matching_ID_Table", filter = "top")
  })

  output$GeneList_Genotype_Table <- renderDT({
    req(input$main_tabs == "Genetic Variants")
    df <- GeneList_Genotype_Table()
    make_dt(df, "GeneList_Genotype_Table", selection = "single", filter = "top")
  }, server = TRUE)

  output$Joined_Table <- renderDT({
    req(input$main_tabs == "Common Variants", input$Patient)
    df <- Joined_Table()
    make_dt(df, "Joined_Table", filter = "top")
  })

  output$Joined_Table_matching <- renderDT({
    req(input$main_tabs == "Common Variants", input$Patient)
    df <- Joined_Table_matching()
    if (nrow(df) == 0) return(datatable(tibble(), options = list(dom = "t")))
    make_dt(df, "Joined_Table_matching", selection = "single", filter = "top")
  })

  output$Joined_Gene_Table <- renderDT({
    req(input$main_tabs == "Common Genes by Patient Table", input$Patient)
    df <- Joined_Gene_Table()
    make_dt(df, "Joined_Gene_Table", filter = "top")
  })

  output$CommonGenesPlot <- renderPlot({
    req(input$main_tabs == "Common Genes by Patient Table", input$Patient)
    d <- gene_summary_raw()
    summary_df <- d$summary
    if (nrow(summary_df) == 0) return(NULL)

    n_patients <- length(input$Patient)
    top_n      <- min(input$top_genes_n %||% 20, nrow(summary_df))

    # Use arrange+head instead of slice_max for broader dplyr compatibility
    plot_df <- summary_df %>%
      arrange(desc(Num_Patients), GeneName) %>%
      head(top_n) %>%
      arrange(Num_Patients, GeneName) %>%          # ascending so top is at top
      mutate(GeneName = factor(GeneName, levels = GeneName))

    # If no genes shared by 2+ patients, show all with a note
    max_shared <- max(plot_df$Num_Patients, na.rm = TRUE)
    subtitle_txt <- if (max_shared > 1) {
      sprintf("%d patients selected | %d genes shared by 2+ patients",
              n_patients, sum(summary_df$Num_Patients > 1))
    } else {
      sprintf("%d patients selected | no genes shared by 2+ patients (showing all)",
              n_patients)
    }

    ggplot(plot_df, aes(x = Num_Patients, y = GeneName, fill = Num_Patients)) +
      geom_col(width = 0.7, colour = "white", linewidth = 0.3) +
      geom_text(aes(label = Num_Patients),
                hjust = -0.25, size = 3.5, colour = "grey30") +
      scale_fill_gradient(low = "#a8d5e2", high = "#1a6b8a",
                          limits = c(1, max(n_patients, 2)),
                          name   = "Patients") +
      scale_x_continuous(
        breaks = seq(1, n_patients),
        limits = c(0, n_patients + 0.8),
        expand = c(0, 0)
      ) +
      labs(
        title    = sprintf("Top %d genes by number of patients with a variant", top_n),
        subtitle = subtitle_txt,
        x        = "Number of patients with a variant in this gene",
        y        = NULL
      ) +
      theme_minimal(base_size = 13) +
      theme(
        panel.grid.major.y = element_blank(),
        panel.grid.minor   = element_blank(),
        axis.text.y        = element_text(size = 11, face = "bold"),
        plot.title         = element_text(size = 14, face = "bold"),
        plot.subtitle      = element_text(size = 11, colour = "grey50"),
        legend.position    = "none"
      )
  })

  # ── Candidate Variants ────────────────────────────────────────────────────
  CAND_BASE_COLS <- c("Patient", "Patient_Phenotype", "Family_Genotypes",
    "GeneName", "CHROM", "Pos", "Ref", "Alt",
    "Consequence", "protein_change", "PHRED", "am_class", 
    "db_pop_freq_max", "gnomAD_nhomalt_XX", "gnomAD_nhomalt_XY","Notes"
  )

  empty_candidates <- function(extra_cols = character()) {
    all_cols <- c(CAND_BASE_COLS, extra_cols)
    as_tibble(setNames(replicate(length(all_cols), character(0), simplify = FALSE), all_cols))
  }

  candidate_variants <- reactiveVal({
    if (file.exists("candidates.csv"))
      read_csv("candidates.csv", show_col_types = FALSE, col_types = cols(.default = "c"))
    else
      empty_candidates()
  })

  pull_field <- function(row, field) {
    if (field %in% names(row)) as.character(row[[field]][1]) else NA_character_
  }

  build_candidate_row <- function(variant_row, patient_id = NA_character_,
                                   patient_pheno = NA_character_,
                                   family_genotypes = NA_character_,
                                   extra_cols = character()) {
    # Build by name so column order in CAND_BASE_COLS never matters
    row <- list(
      Patient           = as.character(patient_id),
      Patient_Phenotype = as.character(patient_pheno),
      Family_Genotypes  = as.character(family_genotypes),
      GeneName          = pull_field(variant_row, "GeneName"),
      CHROM             = pull_field(variant_row, "CHROM"),
      Pos               = pull_field(variant_row, "Pos"),
      Ref               = pull_field(variant_row, "Ref"),
      Alt               = pull_field(variant_row, "Alt"),
      Consequence       = pull_field(variant_row, "Consequence"),
      protein_change    = pull_field(variant_row, "protein_change"),
      PHRED             = pull_field(variant_row, "PHRED"),
      am_class          = pull_field(variant_row, "am_class"),
      db_pop_freq_max   = pull_field(variant_row, "db_pop_freq_max"),
      gnomAD_nhomalt_XX = pull_field(variant_row, "gnomAD_nhomalt_XX"),
      gnomAD_nhomalt_XY = pull_field(variant_row, "gnomAD_nhomalt_XY"),
      Notes             = NA_character_
    )
    for (col in extra_cols) row[[col]] <- NA_character_
    as_tibble(row)
  }

  add_candidate_row <- function(new_row) {
    current  <- candidate_variants()
    all_cols <- union(names(current), names(new_row))
    for (col in setdiff(all_cols, names(current))) current[[col]] <- NA_character_
    for (col in setdiff(all_cols, names(new_row)))  new_row[[col]] <- NA_character_
    candidate_variants(bind_rows(current, new_row %>% dplyr::select(all_of(all_cols))))
  }

  get_fam_geno <- function(row) {
    zyg_cols <- names(row)[str_detect(names(row), "\\.zygosity$")]
    if (length(zyg_cols) == 0) return(NA_character_)
    keep     <- c("Het", "het",
                  "Hom Ref", "hom_ref", "hom ref", "Hom_Ref", "homref",
                  "Hom Alt", "hom_alt", "hom alt", "Hom_Alt", "homalt")
    vals     <- sapply(zyg_cols, function(c) as.character(row[[c]][1]))
    has_geno <- !is.na(vals) & trimws(vals) != "" & vals != "NA" & (vals %in% keep)
    if (!any(has_geno)) return(NA_character_)
    paste(zyg_cols[has_geno], vals[has_geno], sep = "=", collapse = "; ")
  }

  get_pheno_term <- function(row) {
    term_cols <- names(row)[str_detect(names(row), "Term_1")]
    if (length(term_cols) > 0) {
      vals <- unique(na.omit(unlist(row[term_cols])))
      if (length(vals) > 0) return(paste(vals, collapse = "; "))
    }
    patient_id <- pull_field(row, "Patient")
    if (!is.na(patient_id) && is.data.frame(pheno_rv()) && "Patient" %in% names(pheno_rv())) {
      term <- pheno_rv() %>% filter(Patient == patient_id) %>% pull(Term_1) %>% dplyr::first()
      if (!is.null(term) && !is.na(term)) return(as.character(term))
    }
    NA_character_
  }

  observeEvent(input$cand_from_variant_type, {
    cat(">>> cand_from_variant_type clicked, selected row:", input$Variant_Type_rows_selected, "\n")
    req(input$Variant_Type_rows_selected)
    variant_row <- Variant_type_reac()[input$Variant_Type_rows_selected, , drop = FALSE]
    sel_id      <- pull_field(variant_row, "ID")
    extra_cols  <- setdiff(names(candidate_variants()), CAND_BASE_COLS)

    # Look up this variant ID in the genotype table to get patient + zygosity + pheno
    geno_rows <- if (!is.na(sel_id) && nrow(GeneList_Genotype_Table()) > 0)
      GeneList_Genotype_Table() %>% filter(ID == sel_id)
    else
      tibble()

    if (nrow(geno_rows) > 0) {
      # One candidate row per patient carrying this variant
      for (i in seq_len(nrow(geno_rows))) {
        gr <- geno_rows[i, , drop = FALSE]
        add_candidate_row(build_candidate_row(
          gr,
          patient_id       = pull_field(gr, "Patient"),
          patient_pheno    = get_pheno_term(gr),
          family_genotypes = get_fam_geno(gr),
          extra_cols       = extra_cols
        ))
      }
      showNotification(
        sprintf("%d candidate row(s) added.", nrow(geno_rows)),
        type = "message", duration = 3
      )
    } else {
      # No genotype data for this variant -- add annotation-only row
      add_candidate_row(build_candidate_row(variant_row, extra_cols = extra_cols))
      showNotification(
        "Variant added (no genotype data found for this variant).",
        type = "warning", duration = 4
      )
    }
  })

  observeEvent(input$cand_from_genotype_table, {
    cat(">>> cand_from_genotype_table clicked, selected row:", input$GeneList_Genotype_Table_rows_selected, "\n")
    req(input$GeneList_Genotype_Table_rows_selected)
    row        <- GeneList_Genotype_Table()[input$GeneList_Genotype_Table_rows_selected, , drop = FALSE]
    extra_cols <- setdiff(names(candidate_variants()), CAND_BASE_COLS)
    add_candidate_row(build_candidate_row(row, pull_field(row, "Patient"),
                                          get_pheno_term(row), get_fam_geno(row), extra_cols))
    showNotification("Variant added to candidates.", type = "message", duration = 3)
  })

  observeEvent(input$cand_from_matching, {
    cat(">>> cand_from_matching clicked, selected row:", input$Matching_ID_Table_rows_selected, "\n")
    req(input$Matching_ID_Table_rows_selected)
    row        <- Matching_ID_Table()[input$Matching_ID_Table_rows_selected, , drop = FALSE]
    sel_id     <- pull_field(row, "ID")
    anno_row   <- if (!is.na(sel_id)) {
      a <- Variant_type_reac() %>% filter(ID == sel_id) %>% slice(1)
      if (nrow(a) > 0) a else row
    } else row
    extra_cols <- setdiff(names(candidate_variants()), CAND_BASE_COLS)
    add_candidate_row(build_candidate_row(anno_row, NA_character_,
                                          get_pheno_term(row), get_fam_geno(row), extra_cols))
    showNotification("Variant added to candidates.", type = "message", duration = 3)
  })

  observeEvent(input$cand_from_joined, {
    cat(">>> cand_from_joined clicked, selected row:", input$Joined_Table_matching_rows_selected, "\n")
    req(input$Joined_Table_matching_rows_selected)
    row        <- Joined_Table_matching()[input$Joined_Table_matching_rows_selected, , drop = FALSE]
    extra_cols <- setdiff(names(candidate_variants()), CAND_BASE_COLS)
    add_candidate_row(build_candidate_row(row, NA_character_,
                                          get_pheno_term(row), get_fam_geno(row), extra_cols))
    showNotification("Variant added to candidates.", type = "message", duration = 3)
  })

  observeEvent(input$cand_add_col, {
    col_name <- trimws(input$cand_new_col_name)
    if (col_name == "" || col_name %in% names(candidate_variants())) return()
    df <- candidate_variants()
    df[[col_name]] <- NA_character_
    candidate_variants(df)
    updateTextInput(session, "cand_new_col_name", value = "")
    showNotification(paste0('Column "', col_name, '" added.'), type = "message", duration = 3)
  })

  output$candidate_variants_table <- renderDT({
    df <- candidate_variants()
    if (nrow(df) == 0) return(datatable(empty_candidates(), options = list(dom = "t")))
    make_dt(
      df, "candidate_variants_table",
      selection = "single",
      filter    = "top",
      editable  = list(target = "cell", disable = list(columns = 0))
    )
  })

  observeEvent(input$candidate_variants_table_cell_edit, {
    info <- input$candidate_variants_table_cell_edit
    df   <- candidate_variants()
    df[info$row, info$col] <- DT::coerceValue(info$value, df[info$row, info$col])
    candidate_variants(df)
  })

  observeEvent(input$cand_delete_row, {
    req(input$candidate_variants_table_rows_selected)
    df <- candidate_variants()
    candidate_variants(df[-input$candidate_variants_table_rows_selected, ])
  })

  observeEvent(input$cand_save, {
    write_csv(candidate_variants(), "candidates.csv")
    showModal(modalDialog("Candidates saved to candidates.csv", easyClose = TRUE))
  })

  # ── Download handlers ─────────────────────────────────────────────────────
  output$downloadCandidateVariants <- downloadHandler(
    filename = function() paste0("candidate_variants_", Sys.Date(), ".csv"),
    content  = function(file) write.csv(candidate_variants(), file, row.names = FALSE)
  )

  output$downloadVariantType <- downloadHandler(
    filename = function() paste0("filtered_variant_types_", Sys.Date(), ".csv"),
    content  = function(file) {
      fd <- Variant_type_DT_filtered()  # includes DT column filters
      if (nrow(fd) == 0) write.csv(data.frame(Message = "No data selected"), file)
      else write.csv(fd, file, row.names = FALSE)
    }
  )

  output$downloadJoinedTable <- downloadHandler(
    filename = function() paste0("joined_table_", Sys.Date(), ".csv"),
    content  = function(file) write.csv(Joined_Table(), file)
  )

  output$downloadGeneTable <- downloadHandler(
    filename = function() paste0("joined_gene_table_", Sys.Date(), ".csv"),
    content  = function(file) write.csv(Joined_Gene_Table(), file)
  )

  output$downloadmatchedJoinedTable <- downloadHandler(
    filename = function() paste0("joined_matched_table_", Sys.Date(), ".csv"),
    content  = function(file) write.csv(Joined_Table_matching(), file)
  )

  output$downloadGeneListGenotypes <- downloadHandler(
    filename = function() paste0("Variants_with_Genotypes_", Sys.Date(), ".csv"),
    content  = function(file) write.csv(GeneList_Genotype_Table(), file, row.names = FALSE)
  )
}

# Run the Shiny app
shinyApp(ui, server)
