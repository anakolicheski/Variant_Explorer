# lolliplot_module.R
library(shiny)
library(biomaRt)
library(trackViewer)
library(GenomicRanges)
library(stringr)
library(DT)
library(dplyr)

# UI
lolliplotUI <- function(id) {
  ns <- NS(id)
  tagList(
    selectizeInput(
      ns("selected_gene"),
      "Select a Gene",
      choices = NULL,
      selected = NULL,
      multiple = FALSE,
      options = list(
        placeholder = "Select a gene from uploaded list",
        maxOptions = 500
      )
    ),
    plotOutput(ns("lollipopPlot"), hover = ns("plot_hover")),
    br(),
    h4("Variant & Domain Summary"),
    DT::dataTableOutput(ns("summaryTable"))
  )
}

# Server
# all_variants_reactive: unfiltered variant set — used to populate gene dropdown
# variant_data_reactive: filtered variant set  — used for plot data
lolliplotServer <- function(id, all_variants_reactive, variant_data_reactive, pheno, list_of_files) {
  moduleServer(id, function(input, output, session) {
    ns <- session$ns

    consequence_colors <- c(
      missense_variant      = "steelblue",
      nonsense_variant      = "red",
      splice_region_variant = "orange",
      frameshift_variant    = "purple",
      synonymous_variant    = "grey"
    )

    # ── Gene dropdown: full unfiltered gene list ───────────────────────────
    observeEvent(all_variants_reactive(), {
      genes <- sort(unique(all_variants_reactive()$GeneName))
      genes <- genes[!is.na(genes) & genes != ""]
      updateSelectizeInput(session, "selected_gene", choices = genes, server = TRUE)
    })

    # ── Ensembl domain fetch with mirror fallback, cached per gene ─────────
    domain_cache <- list()

    get_protein_domains <- function(gene_symbol) {
      if (!is.null(domain_cache[[gene_symbol]])) return(domain_cache[[gene_symbol]])

      mirrors <- c("www", "useast", "uswest", "asia")
      ensembl <- NULL
      for (mirror in mirrors) {
        ensembl <- tryCatch(
          useEnsembl("ensembl", dataset = "hsapiens_gene_ensembl", mirror = mirror),
          error = function(e) NULL
        )
        if (!is.null(ensembl)) break
      }
      if (is.null(ensembl)) {
        warning("All Ensembl mirrors unreachable.")
        return(NULL)
      }

      domain_info <- tryCatch({
        getBM(
          attributes = c("external_gene_name", "uniprotswissprot", "pfam",
                         "pfam_start", "pfam_end", "description"),
          filters = "hgnc_symbol",
          values  = gene_symbol,
          mart    = ensembl
        )
      }, error = function(e) {
        warning("biomaRt query failed: ", conditionMessage(e))
        NULL
      })

      if (is.null(domain_info) || nrow(domain_info) == 0) {
        domain_cache[[gene_symbol]] <<- NULL
        return(NULL)
      }
      domain_info <- domain_info[!is.na(domain_info$pfam_start) & !is.na(domain_info$pfam_end), ]
      if (nrow(domain_info) == 0) {
        domain_cache[[gene_symbol]] <<- NULL
        return(NULL)
      }

      domain_colors <- rep_len(c("#FF8833", "#51C6E6", "#DFA32D", "#AAAAAA"), nrow(domain_info))
      domain_gr <- GRanges(
        seqnames = Rle(paste0("chr", gene_symbol), nrow(domain_info)),
        ranges   = IRanges(start = domain_info$pfam_start, end = domain_info$pfam_end,
                           names = domain_info$pfam)
      )
      mcols(domain_gr)$feature <- domain_info$description
      mcols(domain_gr)$fill    <- domain_colors
      mcols(domain_gr)$height  <- 0.08

      domain_cache[[gene_symbol]] <<- domain_gr
      domain_gr
    }

    # ── Filtered variants for selected gene ────────────────────────────────
    variants_for_gene <- reactive({
      req(input$selected_gene)
      df <- variant_data_reactive()
      df <- df[!is.na(df$GeneName) & df$GeneName == input$selected_gene, ]

      # Resolve amino acid position
      if ("protein_change" %in% names(df)) {
        df$AA_pos <- suppressWarnings(as.numeric(str_extract(df$protein_change, "\\d+")))
      } else {
        df$AA_pos <- NA_real_
      }
      if ("protPos" %in% names(df)) {
        missing <- is.na(df$AA_pos)
        df$AA_pos[missing] <- suppressWarnings(as.numeric(df$protPos[missing]))
      }

      # Build display label
      if ("protein_change" %in% names(df) && "protPos" %in% names(df)) {
        needs_label <- grepl("^[A-Za-z*]+/[A-Za-z*]+$", df$protein_change, perl = TRUE) |
                       (!grepl("\\d", df$protein_change) & !is.na(df$protein_change))
        if (any(needs_label, na.rm = TRUE)) {
          df$protein_change[needs_label] <- sapply(which(needs_label), function(i) {
            aa  <- df$protein_change[i]
            pos <- df$AA_pos[i]
            if (is.na(aa) || is.na(pos)) return(aa)
            parts <- strsplit(aa, "/")[[1]]
            if (length(parts) == 2) paste0(parts[1], pos, parts[2]) else paste0(aa, pos)
          })
        }
      }

      df <- df[!is.na(df$AA_pos), ]

      # Gather patient genotypes
      patient_info <- tibble()
      if (length(list_of_files) > 0) {
        for (patient_file in list_of_files) {
          geno <- tryCatch(
            get(patient_file) %>% mutate_all(as.character),
            error = function(e) NULL
          )
          if (is.null(geno)) next
          matches <- geno %>% filter(ID %in% df$ID) %>% mutate(Patient = patient_file)
          patient_info <- bind_rows(patient_info, matches)
        }
      }

      # Merge phenotype
      pheno_ok <- !is.null(pheno) && is.data.frame(pheno) && nrow(pheno) > 0 &&
                  all(c("Patient", "Term_1") %in% names(pheno)) &&
                  is.character(pheno$Patient)
      if (pheno_ok && nrow(patient_info) > 0) {
        patient_info <- left_join(
          patient_info %>% dplyr::mutate(Patient = as.character(Patient)),
          pheno %>% dplyr::select(Patient, Term_1) %>% dplyr::mutate(Patient = as.character(Patient)),
          by = "Patient", relationship = "many-to-many"
        )
      } else if (nrow(patient_info) > 0) {
        patient_info$Term_1 <- NA_character_
      }

      if (nrow(patient_info) > 0) {
        info_summary <- patient_info %>%
          group_by(ID) %>%
          summarize(
            Patients   = paste(unique(Patient), collapse = ", "),
            Phenotypes = paste(unique(Term_1),  collapse = ", "),
            .groups = "drop"
          )
        df <- left_join(df, info_summary, by = "ID")
      } else {
        df$Patients   <- NA
        df$Phenotypes <- NA
      }

      df
    })

    # ── Domain fetch reactive (cached, called once per gene) ───────────────
    domains_for_gene <- reactive({
      req(input$selected_gene)
      get_protein_domains(input$selected_gene)
    })

    # ── Lollipop plot ──────────────────────────────────────────────────────
    output$lollipopPlot <- renderPlot({
      df        <- variants_for_gene()
      gene      <- input$selected_gene
      domain_gr <- domains_for_gene()

      if (nrow(df) == 0) {
        plot.new(); title("No variants found for selected gene."); return()
      }
      if (is.null(domain_gr)) {
        plot.new(); title("No domain data available (Ensembl unreachable or no Pfam domains for this gene)."); return()
      }

      variant_gr <- GRanges(
        seqnames = paste0("chr", gene),
        ranges   = IRanges(start = df$AA_pos, width = 1,
                           names = paste0("p.", df$protein_change))
      )
      mcols(variant_gr)$score <- 1
      mcols(variant_gr)$color <- consequence_colors[as.character(df$Consequence)]
      mcols(variant_gr)$color[is.na(mcols(variant_gr)$color)] <- "black"
      mcols(variant_gr)$label.parameter.rot <- 45
      mcols(variant_gr)$label.parameter.gp  <- gpar(fontsize = 12)
      mcols(variant_gr)$tooltip <- paste0(
        df$Consequence,
        "\nPatients: ",   ifelse(is.na(df$Patients),   "NA", df$Patients),
        "\nPhenotypes: ", ifelse(is.na(df$Phenotypes), "NA", df$Phenotypes)
      )

      lolliplot(variant_gr, domain_gr)
    })

    # ── Summary table (reuses cached domain fetch) ─────────────────────────
    output$summaryTable <- DT::renderDataTable({
      df        <- variants_for_gene()
      domain_gr <- domains_for_gene()
      req(nrow(df) > 0)

      aa_label <- if ("protein_change" %in% names(df)) df$protein_change else as.character(df$AA_pos)
      variant_tbl <- data.frame(
        Type        = "Variant",
        Position    = as.character(df$AA_pos),
        Change      = ifelse(is.na(aa_label), "", aa_label),
        Description = df$Consequence,
        Patients    = ifelse(is.na(df$Patients),   "", df$Patients),
        Phenotypes  = ifelse(is.na(df$Phenotypes), "", df$Phenotypes),
        Color       = consequence_colors[as.character(df$Consequence)]
      )
      variant_tbl$Color[is.na(variant_tbl$Color)] <- "black"

      if (!is.null(domain_gr)) {
        domain_tbl <- data.frame(
          Type        = "Domain",
          Position    = paste0(start(domain_gr), "-", end(domain_gr)),
          Change      = "",
          Description = mcols(domain_gr)$feature,
          Patients    = "",
          Phenotypes  = "",
          Color       = mcols(domain_gr)$fill
        )
        combined_tbl <- bind_rows(variant_tbl, domain_tbl)
      } else {
        combined_tbl <- variant_tbl
      }

      DT::datatable(combined_tbl, rownames = FALSE, options = list(pageLength = 5))
    })
  })
}
