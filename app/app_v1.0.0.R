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
  # Clean duplicate columns (e.g. gnomADg_AF...58) created by readr when the
  # source file has repeated column names — keeps first occurrence, strips ...N
  dedup_columns <- function(df) {
    nms      <- names(df)
    base_nms <- sub("\\.\\.\\.\\d+$", "", nms)
    base_nms <- sub("\\.\\.\\d+$",      "", base_nms)
    keep     <- !duplicated(base_nms)
    df       <- df[, keep, drop = FALSE]
    names(df) <- base_nms[keep]
    df
  }

  initial_variants <- {
    anno_file <- "annotations/annotations_fordb.tsv"
    if (file.exists(anno_file)) {
      df <- read_tsv(anno_file, show_col_types = FALSE, col_types = cols(.default = "c"))
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

  # ── Column state: two layers ──────────────────────────────────────────────
  # col_state        – in-memory, updated live as user drags/hides (session only)
  # col_state_saved  – written to disk only when user clicks "Save Layout"
  #                    and loaded back on next app start
  col_state_file <- "col_state.json"

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
        helpText("PHRED scores > 20 are generally considered deleterious")
      )

    } else if (tab %in% c("Common Variants", "Common Genes by Patient Table")) {
      tagList(
        selectInput("PhenotypeTerm", "Filter by Phenotype Term:",
                    choices = NULL, selected = NULL, multiple = TRUE),
        selectInput("Patient", "Filter by Sample/Family:",
                    choices  = if (length(names(Genotypes)) > 0) names(Genotypes) else character(0),
                    multiple = TRUE)
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
                             show_col_types = FALSE, col_types = cols(.default = "c"))
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
  color_zygosity_columns <- function(dt, df) {
    genotype_cols <- names(df)[str_detect(names(df), "\\.zygosity$")]
    if (length(genotype_cols) == 0) return(dt)
    
    for (col in genotype_cols) {
      dt <- dt %>% formatStyle(
        columns = col, target = "cell",
        backgroundColor = styleEqual(
          c("Het", "het",
            "Hom Ref", "hom_ref", "hom ref", "Hom_Ref", "homref",
            "Hom Alt", "hom_alt", "hom alt", "Hom_Alt", "homalt"),
          c("yellow",     "yellow",
            "lightgreen", "lightgreen", "lightgreen", "lightgreen", "lightgreen",
            "tomato",     "tomato",     "tomato",     "tomato",     "tomato")
        )
      )
    }
    dt
  }
  
  
  #──── Table buttons - hide and unhide columns, reorder and save to JSON  ─────────────────────────────
  dt_options <- function(id, extra_opts = list()) {
    base <- list(
      dom        = 'Blfrtip',
      buttons    = list(list(extend = 'colvis', text = 'Columns')),
      scrollX    = TRUE,
      pageLength = 25,
      lengthMenu = list(c(10,25,50,100), c('10','25','50','100')),
      colReorder = TRUE,
      
      initComplete = JS(sprintf("
        function(settings) {
          var api = new $.fn.dataTable.Api(settings);

          // Debounce helper - only fires after dragging stops
          function debounce(fn, delay) {
            var timer;
            return function() {
              clearTimeout(timer);
              timer = setTimeout(fn, delay);
            };
          }

          // Save column order only after drag has settled (400ms)
          var sendOrder = debounce(function() {
            Shiny.setInputValue('%s_col_order', api.colReorder.order().toArray(), {priority: 'event'});
          }, 400);
          api.on('column-reorder', sendOrder);

          // Visibility is a single click - no debounce needed
          api.on('column-visibility', function() {
            var vis = [];
            api.columns().every(function() {
              vis.push(this.visible());
            });
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

    # datatable() treats FALSE as "no editable" but a list enables cell editing
    dt_args <- list(
      df,
      extensions = c("Buttons", "ColReorder"),
      selection  = selection,
      filter     = filter,
      options    = dt_options(id)
    )
    if (!isFALSE(editable)) dt_args$editable <- editable
    dt <- do.call(datatable, dt_args)
    
    state <- isolate(col_state[[id]])
    
    if (!is.null(state)) {
      
      # Apply order
      if (!is.null(state$order) && length(state$order) == ncol(df)) {
        dt$x$options$colReorder <- list(order = state$order)
      }
      
      # Apply visibility
      if (!is.null(state$vis) && length(state$vis) == ncol(df)) {
        dt$x$options$columnDefs <- lapply(seq_along(state$vis), function(i) {
          list(targets = i - 1, visible = state$vis[[i]])
        })
      }
    }
    
    color_zygosity_columns(dt, df)
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
                      choices = all_terms, selected = selected_phenotype_terms())
  })

  observe({
    req(input$main_tabs %in% c("Common Variants", "Common Genes by Patient Table"))
    updateSelectInput(session, "Patient",
                      choices  = if (length(names(Genotypes)) > 0) names(Genotypes) else character(0),
                      selected = selected_patients())
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
  Variant_type_reac <- reactive({
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

    if (!is.null(input$cadd_filter) && "PHRED" %in% names(filtered_data))
      filtered_data <- filtered_data %>%
        mutate(PHRED = as.numeric(PHRED)) %>%
        filter(!is.na(PHRED), PHRED >= input$cadd_filter[1], PHRED <= input$cadd_filter[2])

    # Always return all columns — ColVis lets users hide/show as needed
    cat(sprintf("Output rows: %d, columns: %d\n", nrow(filtered_data), ncol(filtered_data)))
    filtered_data
  })

  # ── Variant_Type DT – render ONCE, update data via proxy ─────────────────
  # The table widget is created once with the initial data. When filters change,
  # only the row data is swapped (replaceData) — column order and visibility are
  # preserved in the DOM without re-rendering.

  variant_type_proxy <- dataTableProxy("Variant_Type")

  # Track whether the table has been initialised this session
  variant_type_initialised <- reactiveVal(FALSE)

  output$Variant_Type <- renderDT({
    df <- Variant_type_reac()
    variant_type_initialised(TRUE)

    if (nrow(df) == 0) {
      return(datatable(tibble(), options = list(dom = "t")))
    }

    make_dt(df, "Variant_Type", selection = "single", filter = "top")
  }, server = TRUE)

  # After first render, subsequent filter changes just swap the data
  observeEvent(Variant_type_reac(), {
    if (!variant_type_initialised()) return()
    df <- Variant_type_reac()
    replaceData(variant_type_proxy, df, resetPaging = FALSE, clearSelection = "none")
  }, ignoreInit = TRUE)

  # ── Column state save helpers ─────────────────────────────────────────────────────
  # Write current col_state to disk (called only on explicit user request)
  save_col_state_to_disk <- function() {
    tryCatch(
      jsonlite::write_json(isolate(reactiveValuesToList(col_state)),
                           col_state_file, auto_unbox = TRUE),
      error = function(e) warning("col_state save failed: ", e$message)
    )
  }
  # Update in-memory state only (no disk write); mark dirty
  save_col_order <- function(id, order) {
    state       <- isolate(col_state[[id]]) %||% list()
    state$order <- order
    col_state[[id]] <- state
    col_state_dirty(TRUE)
  }
  save_col_vis <- function(id, vis) {
    state     <- isolate(col_state[[id]]) %||% list()
    state$vis <- vis
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
    showNotification("Column layout saved — will be restored on next app load.",
                     type = "message", duration = 4)
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

  lapply(TABLE_IDS, function(id) {
    order_input <- paste0(id, "_col_order")
    vis_input   <- paste0(id, "_col_vis")
    observeEvent(input[[order_input]], {
      save_col_order(id, input[[order_input]])
    }, ignoreInit = TRUE)
    observeEvent(input[[vis_input]], {
      save_col_vis(id, input[[vis_input]])
    }, ignoreInit = TRUE)
  })
  
  # ── Plots ─────────────────────────────────────────────────────────────────
  output$ConsequencePieChart <- renderPlot({
    req(Variant_type_reac())
    fd <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
    if (!"Consequence" %in% names(fd)) return(NULL)
    counts <- fd %>% count(Consequence, name = "count") %>% arrange(desc(count))
    ggplot(counts, aes(x = "", y = count, fill = Consequence)) +
      geom_bar(stat = "identity", width = 1) + coord_polar("y", start = 0) +
      labs(title = "Variant Type Distribution", fill = "Consequence") +
      theme_minimal() +
      theme(axis.text = element_blank(), axis.ticks = element_blank(), panel.grid = element_blank())
  })

  output$PHRED_Histogram <- renderPlot({
    req(input$Variant_Type_rows_all)
    fd <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
    ggplot(fd, aes(x = as.numeric(PHRED))) +
      geom_histogram(bins = 30, fill = "steelblue", color = "black", alpha = 0.7) +
      theme_minimal() +
      labs(title = "Distribution of PHRED Scores", x = "PHRED Score", y = "Count")
  })

  # ── GeneList_Genotype_Table ───────────────────────────────────────────────
  GeneList_Genotype_Table <- reactive({
    # Join directly against Variant_type_reac() so this table reacts to ALL
    # sidebar filters (gene list, consequence checkboxes, CADD slider)
    filtered_variants <- Variant_type_reac()
    if (nrow(filtered_variants) == 0) return(tibble())

    results <- all_genotypes() %>% inner_join(filtered_variants, by = "ID")
    if (nrow(results) == 0) return(tibble())

    # Drop columns that are entirely NA — keep everything else for ColVis
    results %>%
      dplyr::select(where(function(x) any(!is.na(x))))
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
                           ~ full_join(.x, variants(), by = "ID",
                                       suffix = c("_genotypes", "_variants")))
    joined_table    <- bind_rows(joined_tables) %>%
      filter(if_any(everything(), ~ str_detect(as.character(.), "Het|Hom.Alt")))

    # Return all columns (minus .y duplicates) — ColVis handles visibility
    joined_table %>%
      dplyr::select(!matches("\\.y$")) %>%
      dplyr::select(where(function(x) any(!is.na(x))))
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

    all_zyg <- purrr::reduce(zygosity_tables, full_join, by = "ID")

    result <- variants() %>%
      mutate_all(as.character) %>%
      inner_join(all_zyg, by = "ID")

    zygosity_columns <- names(result)[str_detect(names(result), "\\.zygosity$")]
    if (length(zygosity_columns) == 0) return(tibble())

    result <- result %>%
      filter(if_any(all_of(zygosity_columns), ~ str_detect(., "Het|Hom.Alt")))

    term1_columns <- names(result)[str_detect(names(result), "\\.Term_1$")]

    # Lead with key annotation cols, then zygosity and Term_1; ColVis handles the rest
    priority_cols    <- c("GeneName", "Consequence", "PHRED", "protein_change",
                          "HGVSc", "HGVSp", "Existing_variation",
                          "clinvar_CLINSIGN", "db_pop_freq_max")
    existing_priority <- intersect(priority_cols, names(result))
    other_cols        <- setdiff(names(result),
                                  c(existing_priority, zygosity_columns, term1_columns))

    result %>%
      dplyr::select(all_of(c(existing_priority, zygosity_columns, term1_columns, other_cols))) %>%
      dplyr::select(where(function(x) any(!is.na(x))))
  })

  # ── Joined_Gene_Table ─────────────────────────────────────────────────────
  Joined_Gene_Table <- reactive({
    req(input$Patient)
    genotype_forgene_tables <- map(input$Patient, ~ {
      tbl <- get(.x) %>% mutate(Patient = .x) %>% mutate_all(as.character)
      tbl
    })
    joined_gene_table <- map(genotype_forgene_tables,
                             ~ left_join(.x, variants(), by = "ID",
                                         suffix = c("_genotypes", "_variants")))
    big_joined <- bind_rows(joined_gene_table) %>%
      filter(if_any(everything(), ~ str_detect(as.character(.), "Het|Hom.Alt")))

    big_joined %>%
      group_by(GeneName) %>%
      summarise(Num_Patients = n_distinct(Patient), .groups = "drop") %>%
      filter(Num_Patients > 1) %>%
      left_join(big_joined, by = "GeneName")
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
    df <- GeneList_Genotype_Table()
    if (nrow(df) == 0) return(datatable(tibble(), options = list(dom = "t")))
    make_dt(df, "GeneList_Genotype_Table", selection = "single", filter = "top")
  }, server = TRUE)

  genotype_table_proxy <- dataTableProxy("GeneList_Genotype_Table")
  genotype_table_initialised <- reactiveVal(FALSE)

  # Mark initialised after first render
  observe({
    df <- GeneList_Genotype_Table()
    if (!genotype_table_initialised() && nrow(df) > 0) {
      genotype_table_initialised(TRUE)
    }
  })

  observeEvent(GeneList_Genotype_Table(), {
    if (!genotype_table_initialised()) return()
    df <- GeneList_Genotype_Table()
    if (nrow(df) == 0) return()
    replaceData(genotype_table_proxy, df, resetPaging = FALSE, clearSelection = "none")
  }, ignoreInit = TRUE)

  output$Joined_Table <- renderDT({
    req(input$Patient)
    df <- Joined_Table()
    make_dt(df, "Joined_Table", filter = "top")
  })

  output$Joined_Table_matching <- renderDT({
    req(input$Patient)
    df <- Joined_Table_matching()
    if (nrow(df) == 0) return(datatable(tibble(), options = list(dom = "t")))
    make_dt(df, "Joined_Table_matching", selection = "single", filter = "top")
  })

  output$Joined_Gene_Table <- renderDT({
    req(input$Patient)
    df <- Joined_Gene_Table()
    make_dt(df, "Joined_Gene_Table", filter = "top")
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
      fd <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
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
