library(shiny)
library(dplyr)
library(readr)
library(stringr)
library(purrr)

############################################
## Helper functions
############################################

# Column detection
required_cols <- list(
  chr = c("CHR", "CHROM", "Chrom", "Chr", "Seqnames", "#CHROM"),
  pos = c("POS", "Position", "Pos", "Start", "start", "bp"),
  ref = c("REF", "Ref", "Reference"),
  alt = c("ALT", "Alt", "Alternate")
)

find_col <- function(df, candidates) {
  cn <- toupper(stringr::str_trim(names(df)))
  candidates <- toupper(candidates)
  match_idx <- match(candidates, cn)
  match_idx <- match_idx[!is.na(match_idx)]
  if (length(match_idx) == 0) return(NULL)
  names(df)[match_idx[1]]
}

# Remove duplicate columns that readr creates when the same column name appears
# multiple times in the input file (e.g. gnomADg_AF..58, gnomADg_AF..59).
# Keeps the first occurrence of each base name; strips the trailing ...N suffix.
dedup_columns <- function(df) {
  nms <- names(df)
  # Strip readr's duplicate suffix: "colname...58" -> "colname"
  base_nms <- sub("\\.\\.\\.\\d+$", "", nms)
  # Also handle the double-dot variant: "colname..58" -> "colname"
  base_nms <- sub("\\.\\.\\d+$", "", base_nms)
  # Keep only the first occurrence of each base name
  keep <- !duplicated(base_nms)
  df   <- df[, keep, drop = FALSE]
  names(df) <- base_nms[keep]
  df
}

# Consequence severity ranking
consequence_severity <- c(
  "transcript_ablation" = 1, "splice_acceptor_variant" = 2, "splice_donor_variant" = 3,
  "stop_gained" = 4, "frameshift_variant" = 5, "stop_lost" = 6, "start_lost" = 7,
  "transcript_amplification" = 8, "inframe_insertion" = 9, "inframe_deletion" = 10,
  "missense_variant" = 11, "protein_altering_variant" = 12, "splice_region_variant" = 13,
  "incomplete_terminal_codon_variant" = 14, "start_retained_variant" = 15, "stop_retained_variant" = 16,
  "synonymous_variant" = 17, "coding_sequence_variant" = 18, "mature_miRNA_variant" = 19,
  "5_prime_UTR_variant" = 20, "3_prime_UTR_variant" = 21, "non_coding_transcript_exon_variant" = 22,
  "intron_variant" = 23, "NMD_transcript_variant" = 24, "non_coding_transcript_variant" = 25,
  "upstream_gene_variant" = 26, "downstream_gene_variant" = 27, "TFBS_ablation" = 28,
  "TFBS_amplification" = 29, "TF_binding_site_variant" = 30, "regulatory_region_ablation" = 31,
  "regulatory_region_amplification" = 32, "feature_elongation" = 33, "regulatory_region_variant" = 34,
  "feature_truncation" = 35, "intergenic_variant" = 36
)

get_most_severe_consequence <- function(consequence_string) {
  if (is.null(consequence_string) || is.na(consequence_string) || consequence_string == "") return(NA_character_)
  consequence_string <- as.character(consequence_string)
  consequences <- unlist(str_split(consequence_string, "[&,;|]"))
  consequences <- str_trim(consequences)
  scores <- consequence_severity[consequences]
  scores <- scores[!is.na(scores)]
  if (length(scores) == 0) return(consequences[1])
  most_severe_idx <- which.min(scores)
  consequences[most_severe_idx]
}

clean_consequence_column <- function(column) {
  if (is.null(column) || length(column) == 0) return(character(0))
  column <- as.character(column)
  result <- character(length(column))
  for (i in seq_along(column)) {
    result[i] <- get_most_severe_consequence(column[i])
  }
  result
}

ensure_numeric <- function(df, numeric_cols) {
  for (col in numeric_cols) {
    if (col %in% names(df)) {
      df[[col]] <- suppressWarnings(as.numeric(as.character(df[[col]])))
    }
  }
  df
}

remove_duplicates_by_severity <- function(df, consequence_col = "Consequence_VEP") {
  if (!consequence_col %in% names(df)) {
    return(df[!duplicated(df$ID), ])
  }
  df <- as.data.frame(df)
  df$severity_rank <- consequence_severity[df[[consequence_col]]]
  df$severity_rank[is.na(df$severity_rank)] <- 999
  df <- df[order(df$ID, df$severity_rank), ]
  df <- df[!duplicated(df$ID), ]
  df$severity_rank <- NULL
  as_tibble(df)
}

infer_zygosity <- function(gt_value) {
  if (is.null(gt_value) || is.na(gt_value) || gt_value == "" || gt_value == "." || gt_value == "./.") {
    return(NA_character_)
  }
  gt_value <- as.character(gt_value)
  gt_value <- trimws(gt_value)
  if (gt_value == "." || gt_value == "./.") return(NA_character_)
  gt_value <- gsub("\\|", "/", gt_value)
  
  if (grepl("^0/0$|^0\\|0$", gt_value)) return("Hom Ref")
  else if (grepl("^0/1$|^1/0$|^0\\|1$|^1\\|0$", gt_value)) return("Het")
  else if (grepl("^1/1$|^1\\|1$", gt_value)) return("Hom Alt")
  else if (grepl("^0/2$|^2/0$|^0/3$|^3/0$", gt_value)) return("Het")
  else if (grepl("^2/2$|^3/3$", gt_value)) return("Hom Alt")
  else if (grepl("^1/2$|^2/1$|^1/3$|^3/1$|^2/3$|^3/2$", gt_value)) return("Het")
  else if (gt_value == "0") return("Hom Ref")
  else if (gt_value == "1") return("Het")
  else if (gt_value == "2") return("Hom Alt")
  
  return(NA_character_)
}

############################################
## UI
############################################
variantUploadModuleUI <- function(id) {
  ns <- NS(id)
  
  tagList(
    h3("Variant Upload & Processing"),
    
    wellPanel(
      h4("Step 1: Upload File"),
      fileInput(ns("variant_file"), "Upload annotated variant TSV/CSV", 
                accept = c(".tsv", ".csv", ".txt")),
      textInput(ns("sample_name"), "Sample/Family Name:", placeholder = "e.g., Family_001")
    ),
    
    wellPanel(
      h4("Step 2: Map Columns & Select Data"),
      h5("Required Columns"),
      fluidRow(
        column(3, selectInput(ns("chr_col"), "CHR:", choices = NULL)),
        column(3, selectInput(ns("pos_col"), "POS:", choices = NULL)),
        column(3, selectInput(ns("ref_col"), "REF:", choices = NULL)),
        column(3, selectInput(ns("alt_col"), "ALT:", choices = NULL))
      ),
      hr(),
      h5("Additional Columns"),
      fluidRow(
        column(6, 
               checkboxGroupInput(ns("anno_cols"), "Annotation Columns:", choices = NULL),
               helpText("Variant-level info: genes, consequences, scores, etc.")
        ),
        column(6,
               checkboxGroupInput(ns("geno_cols"), "Genotype Columns:", choices = NULL),
               helpText("Sample-specific: Zygosity, Depth, GT, etc."),
               helpText("Will be renamed to: SampleName.columnname")
        )
      ),
      actionButton(ns("process"), "Process & Save Files", class = "btn-primary btn-lg")
    ),
    
    uiOutput(ns("completion_ui")),
    
    hr(),
    verbatimTextOutput(ns("status")),
    h4("Preview"),
    tableOutput(ns("preview"))
  )
}

############################################
## Server
############################################
variantUploadServer <- function(id, anno_dir = "annotations", geno_dir = "New_genotypes") {
  
  cat("\n========================================\n")
  cat("VARIANT UPLOAD SERVER FUNCTION CALLED\n")
  cat(sprintf("Module ID: %s\n", id))
  cat("========================================\n\n")
  
  moduleServer(id, function(input, output, session) {
    
    cat("\n!!! INSIDE MODULE SERVER CALLBACK !!!\n\n")
    
    # Create directories
    if (!dir.exists(anno_dir)) dir.create(anno_dir, recursive = TRUE)
    if (!dir.exists(geno_dir)) dir.create(geno_dir, recursive = TRUE)
    
    # Reactive values
    rv <- reactiveValues(
      raw_data = NULL,
      processed = FALSE
    )
    
    # Output flags for conditional panels (kept for compatibility but not used)
    output$file_loaded <- reactive({ !is.null(rv$raw_data) })
    output$processing_complete <- reactive({ rv$processed })
    outputOptions(output, "file_loaded", suspendWhenHidden = FALSE)
    outputOptions(output, "processing_complete", suspendWhenHidden = FALSE)
    
    # Completion UI
    output$completion_ui <- renderUI({
      if (!rv$processed) return(NULL)
      
      wellPanel(
        h4("✓ Processing Complete!"),
        verbatimTextOutput(session$ns("summary")),
        actionButton(session$ns("reset"), "Upload Another Sample", class = "btn-info")
      )
    })
    
    # Load file
    observeEvent(input$variant_file, {
      cat("\n!!!! FILE INPUT CHANGED !!!!\n")
      cat(sprintf("input$variant_file is null: %s\n", is.null(input$variant_file)))
      
      req(input$variant_file)
      
      cat("req() passed\n")
      
      cat("\n=== Loading file ===\n")
      
      tryCatch({
        first_line <- readLines(input$variant_file$datapath, n = 1)
        delim <- if (str_detect(first_line, "\t")) "\t" else ","
        
        df <- read_delim(input$variant_file$datapath, delim = delim, quote = "\"",
                        col_names = TRUE, trim_ws = TRUE, show_col_types = FALSE,
                        escape_double = FALSE, escape_backslash = FALSE)
        
        names(df) <- names(df) %>% str_trim() %>% str_replace_all('["\'\']', '')
        unnamed <- names(df) == "" | grepl("^\\.\\.\\.\\d", names(df))
        df <- df[, !unnamed, drop = FALSE]
        
        # Deduplicate columns with readr's ...N suffix (e.g. gnomADg_AF...58)
        df <- dedup_columns(df)
        
        rv$raw_data <- df
        cat(sprintf("Loaded: %d rows, %d cols\n", nrow(df), ncol(df)))
        
        output$status <- renderText({ sprintf("✓ File loaded: %d rows, %d columns", nrow(df), ncol(df)) })
        
      }, error = function(e) {
        output$status <- renderText({ paste("Error:", e$message) })
      })
    })
    
    # Update inputs when file loads
    observe({
      cat("\n=== observe() for updating inputs triggered ===\n")
      cat(sprintf("rv$raw_data is null: %s\n", is.null(rv$raw_data)))
      
      req(rv$raw_data)
      
      cat("req() passed, have raw_data\n")
      
      df <- rv$raw_data
      cols <- names(df)
      
      cat(sprintf("Dataframe: %d rows, %d cols\n", nrow(df), ncol(df)))
      cat(sprintf("Column names: %s\n", paste(head(cols, 10), collapse = ", ")))
      
      chr_col <- find_col(df, required_cols$chr)
      pos_col <- find_col(df, required_cols$pos)
      ref_col <- find_col(df, required_cols$ref)
      alt_col <- find_col(df, required_cols$alt)
      
      cat(sprintf("Auto-detected: CHR=%s, POS=%s, REF=%s, ALT=%s\n", 
                 chr_col, pos_col, ref_col, alt_col))
      
      cat("Calling updateSelectInput...\n")
      updateSelectInput(session, "chr_col", choices = cols, selected = chr_col)
      updateSelectInput(session, "pos_col", choices = cols, selected = pos_col)
      updateSelectInput(session, "ref_col", choices = cols, selected = ref_col)
      updateSelectInput(session, "alt_col", choices = cols, selected = alt_col)
      
      core_cols <- c(chr_col, pos_col, ref_col, alt_col, "ID")
      remaining <- setdiff(cols, core_cols)
      
      cat(sprintf("Remaining columns (%d): %s\n", length(remaining), paste(head(remaining, 10), collapse = ", ")))
      
      cat("Calling updateCheckboxGroupInput...\n")
      updateCheckboxGroupInput(session, "anno_cols", choices = remaining, selected = remaining)
      updateCheckboxGroupInput(session, "geno_cols", choices = remaining, selected = NULL)
      
      cat("=== observe() complete ===\n\n")
    })
    
    # Preview
    output$preview <- renderTable({
      req(rv$raw_data)
      head(rv$raw_data, 5)
    })
    
    # Process button
    observeEvent(input$process, {
      req(rv$raw_data, input$sample_name)
      
      sample_name <- trimws(input$sample_name)
      if (sample_name == "") {
        showModal(modalDialog("Please enter a sample name", easyClose = TRUE))
        return()
      }
      
      cat("\n=== Processing ===\n")
      
      tryCatch({
        df <- rv$raw_data
        
        # Clean zygosity if exists
        for (col in names(df)) {
          if (tolower(col) == "zygosity") {
            df[[col]] <- sapply(df[[col]], function(val) {
              if (is.null(val) || is.na(val) || val == "" || val == "." || val == "NA") return(NA_character_)
              val <- gsub("\\s*\\([^)]+\\)", "", as.character(val))
              val <- trimws(val)
              val_lower <- tolower(val)
              if (val_lower == "het") return("Het")
              if (val_lower %in% c("hom ref", "homref", "hom_ref")) return("Hom Ref")
              if (val_lower %in% c("hom alt", "homalt", "hom_alt")) return("Hom Alt")
              return(val)
            }, USE.NAMES = FALSE)
          }
        }
        
        # Infer zygosity from GT if needed
        has_zyg <- any(tolower(names(df)) == "zygosity")
        if (has_zyg) {
          zyg_col <- names(df)[tolower(names(df)) == "zygosity"][1]
          na_pct <- sum(is.na(df[[zyg_col]])) / nrow(df)
          
          if (na_pct > 0.8) {
            gt_candidates <- c("GT", "Gt", "gt", "Genotype", "genotype")
            for (gt in gt_candidates) {
              if (gt %in% names(df)) {
                cat(sprintf("Inferring zygosity from %s\n", gt))
                df[[zyg_col]] <- sapply(df[[gt]], infer_zygosity, USE.NAMES = FALSE)
                break
              }
            }
          }
        }
        
        # Filter NA zygosity
        geno_cols <- input$geno_cols
        if (length(geno_cols) > 0 && has_zyg) {
          zyg_col <- names(df)[tolower(names(df)) == "zygosity"][1]
          if (zyg_col %in% names(df)) {
            before <- nrow(df)
            df <- df[!is.na(df[[zyg_col]]) & df[[zyg_col]] != "", ]
            cat(sprintf("Filtered %d NA genotypes\n", before - nrow(df)))
          }
        }
        
        # Build annotation
        anno <- df %>%
          dplyr::transmute(
            CHROM = as.character(!!sym(input$chr_col)),
            Pos = as.numeric(as.character(!!sym(input$pos_col))),
            Ref = as.character(!!sym(input$ref_col)),
            Alt = as.character(!!sym(input$alt_col)),
            ID = paste(!!sym(input$chr_col), !!sym(input$pos_col), 
                      !!sym(input$ref_col), !!sym(input$alt_col), sep = "_")
          )
        
        anno_cols_sel <- setdiff(input$anno_cols, c(input$chr_col, input$pos_col, input$ref_col, input$alt_col, "ID"))
        if (length(anno_cols_sel) > 0) {
          extra <- df %>% dplyr::select(all_of(anno_cols_sel)) %>% mutate(across(everything(), as.character))
          anno <- bind_cols(anno, extra)
        }
        
        # Remove case-insensitive duplicates
        lower_names <- tolower(names(anno))
        case_dups <- duplicated(lower_names)
        if (any(case_dups)) {
          cat(sprintf("Removing %d duplicate columns\n", sum(case_dups)))
          anno <- anno[, !case_dups]
        }
        
        # Column mapping - map common variations to expected names
        col_map <- c(
          # Core columns
          "CHR" = "CHROM", 
          "POS" = "Pos", 
          "SYMBOL" = "GeneName",
          "Gene" = "GeneName",
          
          # Consequence columns
          "Consequence" = "Consequence_VEP",
          
          # Frequency columns
          "gnomAD AF" = "gnomADe_AF",
          "gnomAD_AF" = "gnomADe_AF",
          "AF" = "gnomADe_AF",
          
          # Score columns
          "PHRED" = "PHRED",
          "CADD Score" = "PHRED",
          "CADD_PHRED" = "PHRED",
          
          # Clinical columns
          "ClinVar" = "clinvar_CLINSIGN",
          "CLNSIG" = "clinvar_CLINSIGN",
          
          # Protein change columns
          "Amino Acids" = "protein_change",
          "Amino_acids" = "protein_change",
          "AA" = "protein_change",
          
          # Position columns
          "Protein Position" = "protPos",
          "Protein_position" = "protPos",
          "cDNA Position" = "cDNApos",
          "cDNA_position" = "cDNApos",
          "CDS Position" = "CDSpos",
          "CDS_position" = "CDSpos",
          
          # Prediction columns
          "PolyPhen" = "PolyPhenCat",
          "SIFT" = "SIFTcat",
          
          # Other annotations
          "Existing variation" = "Existing_variation",
          "Existing_variation" = "Existing_variation",
          "HGVSg" = "HGVSc"
        )
        
        for (old in names(col_map)) {
          if (old %in% names(anno)) {
            names(anno)[names(anno) == old] <- col_map[old]
          }
        }
        
        # Ensure CHROM
        if ("CHR" %in% names(anno) && !"CHROM" %in% names(anno)) {
          names(anno)[names(anno) == "CHR"] <- "CHROM"
        }
        
        # Create protein_change if we have the components but not the full field
        # Lolliplot needs protein_change with the position number in it (like "Q621R" or just "621")
        # Your format: Amino Acids = "Q/R", Protein Position = "621"
        if (!"protein_change" %in% names(anno)) {
          # If we have protPos (mapped from "Protein Position"), use it
          if ("protPos" %in% names(anno)) {
            # If we also have the amino acid change, combine them: "Q/R" + "621" = "Q621R"
            if ("Amino_acids" %in% names(anno)) {
              # Split "Q/R" into "Q" and "R", then create "Q621R" format
              anno$protein_change <- sapply(seq_len(nrow(anno)), function(i) {
                aa <- anno$Amino_acids[i]
                pos <- anno$protPos[i]
                if (is.na(aa) || is.na(pos) || aa == "." || pos == ".") return(NA_character_)
                # Split "Q/R" on "/"
                parts <- strsplit(as.character(aa), "/")[[1]]
                if (length(parts) == 2) {
                  paste0(parts[1], pos, parts[2])  # "Q621R"
                } else {
                  as.character(pos)  # Just use position if format is unexpected
                }
              })
              cat("Created protein_change from Amino_acids + protPos (format: Q621R)\n")
            } else {
              # Just use position number - lolliplot can extract it
              anno$protein_change <- as.character(anno$protPos)
              cat("Created protein_change from protPos only\n")
            }
          }
        }
        
        # Clean numeric
        num_cols <- c("Pos", "PHRED", "gnomADe_AF")
        anno <- ensure_numeric(anno, num_cols)
        
        # Clean consequences
        if ("Consequence_VEP" %in% names(anno)) {
          anno$Consequence_VEP <- clean_consequence_column(anno$Consequence_VEP)
        }
        
        # Remove duplicates
        orig_rows <- nrow(anno)
        anno <- remove_duplicates_by_severity(anno)
        dup_removed <- orig_rows - nrow(anno)
        
        anno <- anno %>% mutate(across(everything(), as.character))
        
        # Build genotype
        geno <- NULL
        if (length(geno_cols) > 0) {
          geno <- df %>% dplyr::select(ID = !!sym(input$chr_col), all_of(geno_cols))
          geno$ID <- paste(df[[input$chr_col]], df[[input$pos_col]], 
                          df[[input$ref_col]], df[[input$alt_col]], sep = "_")
          
          for (col in names(geno)) {
            if (col != "ID") {
              geno[[col]] <- sapply(geno[[col]], function(v) {
                if (is.null(v) || is.na(v) || v == ".") NA_character_ else as.character(v)
              }, USE.NAMES = FALSE)
              names(geno)[names(geno) == col] <- paste0(sample_name, ".", tolower(col))
            }
          }
          
          geno <- geno[!duplicated(geno$ID), ]
          geno <- geno %>% mutate(across(everything(), as.character))
        }
        
        # Save files
        anno_file <- file.path(anno_dir, "annotations_fordb.tsv")
        geno_file <- file.path(geno_dir, paste0(sample_name, "_geno.tsv"))
        
        if (file.exists(anno_file)) {
          existing <- read_tsv(anno_file, show_col_types = FALSE, col_types = cols(.default = "c"))
          # Clean up any ...N duplicate columns that accumulated in the saved file
          existing <- dedup_columns(existing)
          all_cols <- union(names(existing), names(anno))
          for (col in setdiff(all_cols, names(existing))) existing[[col]] <- NA_character_
          for (col in setdiff(all_cols, names(anno))) anno[[col]] <- NA_character_
          combined <- bind_rows(existing, anno)
          combined <- remove_duplicates_by_severity(combined)
          combined <- combined %>% mutate(across(everything(), as.character))
          write_tsv(combined, anno_file)
          anno_msg <- sprintf("Appended: %d new", nrow(combined) - nrow(existing))
        } else {
          write_tsv(anno, anno_file)
          anno_msg <- sprintf("Created: %d variants", nrow(anno))
        }
        
        geno_msg <- "No genotype columns"
        if (!is.null(geno)) {
          write_tsv(geno, geno_file)
          geno_msg <- sprintf("Saved: %d variants", nrow(geno))
        }
        
        rv$processed <- TRUE
        
        output$summary <- renderText({
          paste(
            sprintf("Sample: %s", sample_name),
            sprintf("Original: %d rows", orig_rows),
            sprintf("Duplicates removed: %d", dup_removed),
            sprintf("\nAnnotation: %s", anno_msg),
            sprintf("Genotype: %s", geno_msg),
            sprintf("\nFiles:\n  %s\n  %s", anno_file, geno_file),
            sep = "\n"
          )
        })
        
        cat("=== Complete ===\n")
        
      }, error = function(e) {
        output$status <- renderText({ paste("Error:", e$message) })
        cat(sprintf("Error: %s\n", e$message))
      })
    })
    
    # Reset
    observeEvent(input$reset, {
      rv$raw_data <- NULL
      rv$processed <- FALSE
      updateTextInput(session, "sample_name", value = "")
    })
    
    return(reactive({ list(completed = rv$processed) }))
  })
}
