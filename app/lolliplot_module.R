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
lolliplotServer <- function(id, variant_data_reactive = NULL, pheno, list_of_files,
                            all_variants_reactive = NULL) {
  # backwards-compatibility alias
  if (is.null(variant_data_reactive) && !is.null(all_variants_reactive))
    variant_data_reactive <- all_variants_reactive
  moduleServer(id, function(input, output, session) {
    ns <- session$ns
    
    # Define consequence color mapping globally inside module
    consequence_colors <- c(
      missense_variant = "steelblue",
      nonsense_variant = "red",
      splice_region_variant = "orange",
      frameshift_variant = "purple",
      synonymous_variant = "grey"
    )
    
    # Update gene choices based on variant data
    observeEvent(variant_data_reactive(), {
      genes <- sort(unique(variant_data_reactive()$GeneName))
      updateSelectizeInput(session, "selected_gene", choices = genes, server = TRUE)
    })
    
    # ── Protein domain fetching ────────────────────────────────────────────────
    # Order of attempts:
    #   1. Local RDS cache (instant — populated from prior successful lookups)
    #   2. UniProt REST API (EMBL-EBI infrastructure, independent of Ensembl)
    #   3. Ensembl REST API
    #   4. BioMart (last resort — has been broadly unreliable since mid-2025)
    # Successful results are cached locally so each gene is only fetched once.

    DOMAIN_CACHE_FILE <- "domain_cache.rds"

    load_domain_cache <- function() {
      if (!file.exists(DOMAIN_CACHE_FILE)) return(list())
      tryCatch(readRDS(DOMAIN_CACHE_FILE), error = function(e) list())
    }

    save_to_cache <- function(gene_symbol, gr) {
      cache <- load_domain_cache()
      cache[[gene_symbol]] <- gr
      tryCatch(saveRDS(cache, DOMAIN_CACHE_FILE), error = function(e) NULL)
    }

    # ── UniProt REST API ──────────────────────────────────────────────────────
    # Returns a data.frame with pfam/pfam_start/pfam_end/description columns.
    # Uses Swiss-Prot reviewed entries only for quality/stability.
    get_domains_uniprot <- function(gene_symbol) {
      search_url <- paste0(
        "https://rest.uniprot.org/uniprotkb/search?",
        "query=gene_exact:", utils::URLencode(gene_symbol, reserved = TRUE),
        "+AND+organism_id:9606+AND+reviewed:true",
        "&fields=accession,ft_domain,ft_region,length&format=json&size=1"
      )
      resp <- tryCatch(httr::GET(search_url, httr::timeout(10)), error = function(e) NULL)
      if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)

      data    <- httr::content(resp, "parsed")
      results <- data$results %||% list()
      if (length(results) == 0) return(NULL)

      protein     <- results[[1]]
      prot_length <- as.integer(protein$sequence$length %||% NA)
      features    <- protein$features %||% list()
      domain_f    <- Filter(function(f) f$type %in% c("Domain", "Region"), features)
      if (length(domain_f) == 0) return(NULL)

      rows <- lapply(domain_f, function(f) {
        start <- f$location$start$value
        end   <- f$location$end$value
        if (is.null(start) || is.null(end)) return(NULL)
        data.frame(pfam        = as.character(f$description %||% ""),
                   pfam_start  = as.integer(start),
                   pfam_end    = as.integer(end),
                   description = as.character(f$description %||% ""),
                   prot_length = prot_length,
                   stringsAsFactors = FALSE)
      })
      df <- do.call(rbind, Filter(Negate(is.null), rows))
      if (is.null(df) || nrow(df) == 0) return(NULL)
      df[!is.na(df$pfam_start) & !is.na(df$pfam_end), ]
    }

    # ── Ensembl REST API ──────────────────────────────────────────────────────
    get_domains_rest <- function(gene_symbol) {
      base    <- "https://rest.ensembl.org"
      headers <- httr::add_headers(Accept = "application/json")

      resp1 <- tryCatch(
        httr::GET(paste0(base, "/lookup/symbol/homo_sapiens/",
                         utils::URLencode(gene_symbol, reserved = TRUE),
                         "?expand=1"),
                  headers, httr::timeout(10)),
        error = function(e) NULL
      )
      if (is.null(resp1) || httr::status_code(resp1) != 200) return(NULL)

      gene_data   <- httr::content(resp1, "parsed")
      transcripts <- gene_data$Transcript %||% list()
      if (length(transcripts) == 0) return(NULL)

      is_canon <- vapply(transcripts, function(t)
        isTRUE(t$is_canonical == 1), logical(1))
      idx            <- if (any(is_canon)) which(is_canon)[1] else 1L
      translation_id <- transcripts[[idx]]$Translation$id
      if (is.null(translation_id)) return(NULL)

      resp2 <- tryCatch(
        httr::GET(paste0(base, "/overlap/translation/", translation_id, "?feature=Pfam"),
                  headers, httr::timeout(10)),
        error = function(e) NULL
      )
      if (is.null(resp2) || httr::status_code(resp2) != 200) return(NULL)

      pfam_list <- httr::content(resp2, "parsed")
      if (length(pfam_list) == 0) return(NULL)

      prot_length <- as.integer(transcripts[[idx]]$Translation$length %||% NA)
      do.call(rbind, lapply(pfam_list, function(d) data.frame(
        pfam        = as.character(d$id        %||% ""),
        pfam_start  = as.integer(d$start),
        pfam_end    = as.integer(d$end),
        description = as.character(d$description %||% d$id %||% ""),
        prot_length = prot_length,
        stringsAsFactors = FALSE
      )))
    }

    # ── BioMart (last resort) ─────────────────────────────────────────────────
    get_domains_biomart <- function(gene_symbol) {
      hosts <- list(
        list(fn = "useEnsembl", args = list(biomart = "ensembl",
               dataset = "hsapiens_gene_ensembl")),
        list(fn = "useEnsembl", args = list(biomart = "ensembl",
               dataset = "hsapiens_gene_ensembl", mirror = "useast")),
        list(fn = "useEnsembl", args = list(biomart = "ensembl",
               dataset = "hsapiens_gene_ensembl", mirror = "asia"))
      )
      old_to <- getOption("timeout")
      on.exit(options(timeout = old_to), add = TRUE)
      options(timeout = 8)
      mart <- NULL
      for (h in hosts) {
        mart <- tryCatch(do.call(h$fn, h$args),
                         error = function(e) NULL, warning = function(w) NULL)
        if (!is.null(mart)) break
      }
      if (is.null(mart)) return(NULL)
      tryCatch(
        getBM(attributes = c("external_gene_name", "pfam",
                             "pfam_start", "pfam_end", "description"),
              filters = "hgnc_symbol", values = gene_symbol, mart = mart),
        error = function(e) NULL
      )
    }

    # ── Shared GRanges builder ────────────────────────────────────────────────
    domains_to_granges <- function(domain_info, gene_symbol) {
      if (is.null(domain_info) || nrow(domain_info) == 0) return(NULL)
      domain_info <- domain_info[!is.na(domain_info$pfam_start) &
                                   !is.na(domain_info$pfam_end), ]
      if (nrow(domain_info) == 0) return(NULL)
      colors <- rep_len(c("#FF8833", "#51C6E6", "#DFA32D", "#AAAAAA"),
                        nrow(domain_info))
      seq_name <- paste0("chr", gene_symbol)
      gr <- GRanges(
        seqnames = Rle(seq_name, nrow(domain_info)),
        ranges   = IRanges(start = domain_info$pfam_start,
                           end   = domain_info$pfam_end),
        names    = domain_info$pfam
      )
      # Store the full canonical protein length in seqlengths so trackViewer
      # draws the x-axis from 1 to the true end of the protein, not just the
      # range of the domains (which would clip variants outside domain regions).
      if ("prot_length" %in% names(domain_info)) {
        prot_len <- max(domain_info$prot_length, na.rm = TRUE)
        if (is.finite(prot_len) && prot_len > 0)
          seqlengths(gr) <- setNames(as.integer(prot_len), seq_name)
      }
      mcols(gr)$feature <- domain_info$description
      mcols(gr)$fill    <- colors
      mcols(gr)$height  <- 0.08
      gr
    }

    # ── Main entry point ──────────────────────────────────────────────────────
    get_protein_domains <- function(gene_symbol) {
      # 1. Local cache
      cache <- load_domain_cache()
      if (!is.null(cache[[gene_symbol]])) {
        message("Domain cache hit: ", gene_symbol)
        return(cache[[gene_symbol]])
      }

      # 2-4. Remote sources — track which one succeeded
      domain_info <- NULL
      domain_source <- "Unknown"
      fetchers <- list(
        list(fn = get_domains_uniprot,  label = "UniProt"),
        list(fn = get_domains_rest,     label = "Ensembl REST"),
        list(fn = get_domains_biomart,  label = "Ensembl BioMart")
      )
      for (f in fetchers) {
        domain_info <- tryCatch(f$fn(gene_symbol), error = function(e) NULL)
        if (!is.null(domain_info) && nrow(domain_info) > 0) {
          domain_source <- f$label
          break
        }
      }

      gr <- domains_to_granges(domain_info, gene_symbol)
      if (!is.null(gr)) {
        attr(gr, "domain_source") <- domain_source
        save_to_cache(gene_symbol, gr)
      }
      gr
    }


    # Reactive filtered variants for selected gene
    variants_for_gene <- reactive({
      req(input$selected_gene)
      df <- variant_data_reactive()
      df <- df[df$GeneName == input$selected_gene, ]

      # ── Resolve amino acid position ──────────────────────────────────────────
      # Strategy 1: digits embedded in protein_change (e.g. "I428P", "p.Ile428Pro")
      if ("protein_change" %in% names(df)) {
        df$AA_pos <- suppressWarnings(as.numeric(str_extract(df$protein_change, "\\d+")))
      } else {
        df$AA_pos <- NA_real_
      }
      # Strategy 2: separate protPos column (upload module renames Protein_position)
      for (pos_col in c("protPos", "Protein_position", "prot_pos", "CDS_position")) {
        if (pos_col %in% names(df)) {
          missing <- is.na(df$AA_pos)
          df$AA_pos[missing] <- suppressWarnings(as.numeric(df[[pos_col]][missing]))
          if (any(!is.na(df$AA_pos))) break
        }
      }
      # Strategy 3: reconstruct display label when protein_change is "S/P" style
      if ("protein_change" %in% names(df)) {
        needs_label <- !is.na(df$AA_pos) &
                       grepl("^[A-Za-z*]+/[A-Za-z*]+$", df$protein_change, perl = TRUE)
        if (any(needs_label)) {
          df$protein_change[needs_label] <- sapply(which(needs_label), function(i) {
            parts <- strsplit(df$protein_change[i], "/")[[1]]
            if (length(parts) == 2) paste0(parts[1], df$AA_pos[i], parts[2])
            else df$protein_change[i]
          })
        }
      }
      df <- df[!is.na(df$AA_pos), ]
      
      # Initialize a tibble to store patient info
      patient_info <- tibble()
      
      for (patient_file in list_of_files) {
        geno <- get(patient_file) %>% mutate_all(as.character)
        matches <- geno %>% filter(ID %in% df$ID) %>%
          mutate(Patient = patient_file)
        patient_info <- bind_rows(patient_info, matches)
      }
      
      # Merge with phenotype table
      if (exists("pheno") && nrow(patient_info) > 0) {
        patient_info <- left_join(patient_info, pheno %>% dplyr::select(Patient, Term_1),
                                  by = "Patient", relationship = "many-to-many")
      }
      
      # Add Patient and Term_1 info to variants df
      if (nrow(patient_info) > 0) {
        info_summary <- patient_info %>%
          group_by(ID) %>%
          summarize(
            Patients = paste(unique(Patient), collapse = ", "),
            Phenotypes = paste(unique(Term_1), collapse = ", "),
            .groups = "drop"
          )
        df <- left_join(df, info_summary, by = "ID")
      } else {
        df$Patients <- NA
        df$Phenotypes <- NA
      }
      
      df
    })
    # Lollipop plot
    output$lollipopPlot <- renderPlot({
      df <- variants_for_gene()
      gene <- input$selected_gene
      if (nrow(df) == 0) {
        plot.new(); title("No variants found for selected gene."); return()
      }
      
      domain_gr <- get_protein_domains(gene)
      if (is.null(domain_gr)) {
        plot.new(); title("No domain data available from Ensembl."); return()
      }
      
      # Build GRanges object for variants
      variant_gr <- GRanges(
        seqnames = paste0("chr", gene),
        ranges = IRanges(start = df$AA_pos, width = 1),
        names = paste0("var", seq_along(df$AA_pos))
      )
      mcols(variant_gr)$score <- 1
      mcols(variant_gr)$color <- consequence_colors[as.character(df$Consequence)]
      mcols(variant_gr)$color[is.na(mcols(variant_gr)$color)] <- "black"
      
      
      # hover info: Patient + Term_1
      mcols(variant_gr)$label <- paste0(
        df$Consequence,
        "\nPatients: ", ifelse(is.na(df$Patients), "NA", df$Patients),
        "\nPhenotypes: ", ifelse(is.na(df$Phenotypes), "NA", df$Phenotypes)
      )
      # Set the x-axis range to cover the full canonical protein length.
      # Without this, trackViewer clips to min(domains)/max(domains), hiding
      # variants that fall outside the domain-annotated region.
      seq_name <- paste0("chr", gene)
      prot_len <- if (!is.null(seqlengths(domain_gr)) &&
                       !is.na(seqlengths(domain_gr)[seq_name]) &&
                       seqlengths(domain_gr)[seq_name] > 0) {
        seqlengths(domain_gr)[seq_name]
      } else {
        max(c(max(df$AA_pos, na.rm = TRUE), max(end(domain_gr))))
      }

      plot_range    <- GRanges(seq_name, IRanges(1L, as.integer(prot_len)))
      domain_source <- attr(domain_gr, "domain_source") %||% "Unknown"
      plot_title    <- paste0(gene, "  |  Protein domains: ", domain_source,
                              "  |  n = ", nrow(df), " variant",
                              if (nrow(df) == 1) "" else "s")
      lolliplot(variant_gr, domain_gr, ranges = plot_range)
      title(main = plot_title, cex.main = 0.95, font.main = 1, col.main = "#444444")
    })
    
    # Summary table
    output$summaryTable <- DT::renderDataTable({
      df <- variants_for_gene()
      gene <- input$selected_gene
      req(nrow(df) > 0)
      
      # Variant summary
      variant_tbl <- data.frame(
        Type = "Variant",
        Position = as.character(df$AA_pos),
        Description = df$Consequence,
        Patients = ifelse(is.na(df$Patients), "", df$Patients),
        Phenotypes = ifelse(is.na(df$Phenotypes), "", df$Phenotypes),
        Color = consequence_colors[as.character(df$Consequence)]
      )
      variant_tbl$Color[is.na(variant_tbl$Color)] <- "black"
      
      # Domain summary
      domain_gr <- get_protein_domains(gene)
      if (!is.null(domain_gr)) {
        domain_tbl <- data.frame(
          Type = "Domain",
          Position = paste0(start(domain_gr), "-", end(domain_gr)),
          Description = mcols(domain_gr)$feature,
          Color = mcols(domain_gr)$fill
        )
        combined_tbl <- bind_rows(variant_tbl, domain_tbl)
      } else {
        combined_tbl <- variant_tbl
      }
      
      DT::datatable(combined_tbl, rownames = FALSE, options = list(pageLength = 5))
    })
  })
}
