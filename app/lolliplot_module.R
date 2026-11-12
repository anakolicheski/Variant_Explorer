# lolliplot_module.R
library(shiny)
library(trackViewer)
library(GenomicRanges)
library(stringr)
library(DT)
library(dplyr)

# x %||% y: y when x is NULL. Built into R from 4.4; R 4.3 gets it from
# purrr/rlang when attached. Defined here so the module never depends on that.
if (!exists("%||%", mode = "function")) `%||%` <- function(x, y) if (is.null(x)) y else x

# ══ Protein domain lookup ══════════════════════════════════════════════════════
# Plain functions (no Shiny), so they can be tested on their own.
#
# Order of attempts for a gene:
#   1. In-memory cache  (this R process; includes genes that had NO domains,
#                        so a slow failed lookup isn't repeated on every redraw)
#   2. Disk cache       app_state/domain_cache.rds (successful lookups only)
#   3. UniProt REST     reviewed human entry: domains + full protein length
#   4. Ensembl REST     Pfam domains on the canonical translation
# Each web request times out after 10 s, so a lookup takes at most ~30 s.
# (BioMart was dropped as a fallback: since 2025 it often hangs for minutes.)
#
# Result: list(domains = data.frame(name, start, end), prot_length, source)
#   domains has 0 rows when none were found; prot_length may be NA.

DOMAIN_TIMEOUT_S <- 10
.domain_memo     <- new.env(parent = emptyenv())

domain_cache_file <- function() {
  file.path(Sys.getenv("APP_STATE_DIR", "app_state"), "domain_cache.rds")
}

empty_domains <- function() {
  data.frame(name = character(), start = integer(), end = integer(),
             stringsAsFactors = FALSE)
}

# GET a URL and parse JSON; NULL on any error, timeout or non-200 status
http_json <- function(url, accept_json = FALSE) {
  resp <- tryCatch(
    if (accept_json)
      httr::GET(url, httr::add_headers(Accept = "application/json"),
                httr::timeout(DOMAIN_TIMEOUT_S))
    else
      httr::GET(url, httr::timeout(DOMAIN_TIMEOUT_S)),
    error = function(e) NULL
  )
  if (is.null(resp) || httr::status_code(resp) != 200) return(NULL)
  tryCatch(httr::content(resp, "parsed", simplifyVector = FALSE),
           error = function(e) NULL)
}

# UniProt: reviewed (Swiss-Prot) human entry for the gene symbol
get_domains_uniprot <- function(gene_symbol) {
  url <- paste0(
    "https://rest.uniprot.org/uniprotkb/search?",
    "query=gene_exact:", utils::URLencode(gene_symbol, reserved = TRUE),
    "+AND+organism_id:9606+AND+reviewed:true",
    "&fields=accession,ft_domain,ft_region,length&format=json&size=1"
  )
  data <- http_json(url)
  if (is.null(data) || length(data$results) == 0) return(NULL)

  protein     <- data$results[[1]]
  prot_length <- suppressWarnings(as.integer(protein$sequence$length %||% NA))
  features    <- protein$features %||% list()

  to_df <- function(fs) {
    rows <- lapply(fs, function(f) {
      s <- f$location$start$value; e <- f$location$end$value
      if (is.null(s) || is.null(e)) return(NULL)
      data.frame(name  = as.character(f$description %||% f$type %||% ""),
                 start = as.integer(s), end = as.integer(e),
                 stringsAsFactors = FALSE)
    })
    rows <- Filter(Negate(is.null), rows)
    if (length(rows) == 0) empty_domains() else do.call(rbind, rows)
  }

  # Prefer annotated Domains; fall back to named Regions, skipping generic
  # "Disordered" / compositional-bias regions that would clutter the plot
  doms <- to_df(Filter(function(f) identical(f$type, "Domain"), features))
  if (nrow(doms) == 0) {
    regs <- Filter(function(f) identical(f$type, "Region") &&
                     !grepl("^Disordered$|compositional", f$description %||% "",
                            ignore.case = TRUE), features)
    doms <- to_df(regs)
  }
  list(domains = doms, prot_length = prot_length, source = "UniProt")
}

# Ensembl: Pfam domains on the canonical translation.
# NB: the domain database is selected with type=Pfam; 'feature' only accepts
# fixed values (protein_feature is the default), so feature=Pfam is rejected.
get_domains_ensembl <- function(gene_symbol) {
  base <- "https://rest.ensembl.org"
  gene <- http_json(paste0(base, "/lookup/symbol/homo_sapiens/",
                           utils::URLencode(gene_symbol, reserved = TRUE),
                           "?expand=1"), accept_json = TRUE)
  transcripts <- gene$Transcript %||% list()
  if (length(transcripts) == 0) return(NULL)

  is_canon <- vapply(transcripts, function(t) isTRUE(t$is_canonical == 1), logical(1))
  tr       <- transcripts[[if (any(is_canon)) which(is_canon)[1] else 1L]]
  tl_id    <- tr$Translation$id
  if (is.null(tl_id)) return(NULL)
  prot_length <- suppressWarnings(as.integer(tr$Translation$length %||% NA))

  pfam <- http_json(paste0(base, "/overlap/translation/", tl_id, "?type=Pfam"),
                    accept_json = TRUE)
  if (is.null(pfam)) return(NULL)
  doms <- if (length(pfam) == 0) empty_domains() else do.call(rbind, lapply(pfam, function(d)
    data.frame(name  = as.character(d$description %||% d$id %||% ""),
               start = as.integer(d$start), end = as.integer(d$end),
               stringsAsFactors = FALSE)))
  list(domains = doms, prot_length = prot_length, source = "Ensembl (Pfam)")
}

# Older app versions cached GRanges objects; convert those on read
cache_entry_to_result <- function(x) {
  if (is.list(x) && !is.null(x$domains)) return(x)
  if (methods::is(x, "GRanges")) {
    sl <- suppressWarnings(as.integer(GenomeInfoDb::seqlengths(x)[1]))
    return(list(
      domains = data.frame(name = as.character(mcols(x)$feature %||% names(x) %||% ""),
                           start = start(x), end = end(x), stringsAsFactors = FALSE),
      prot_length = sl,
      source      = attr(x, "domain_source") %||% "cache"))
  }
  NULL
}

get_protein_domains <- function(gene_symbol) {
  # 1. memory
  if (exists(gene_symbol, envir = .domain_memo, inherits = FALSE))
    return(get(gene_symbol, envir = .domain_memo))

  # 2. disk
  cache_file <- domain_cache_file()
  cache <- if (file.exists(cache_file) && isTRUE(file.size(cache_file) > 0))
    tryCatch(readRDS(cache_file), error = function(e) list()) else list()
  if (!is.list(cache)) cache <- list()
  hit <- cache_entry_to_result(cache[[gene_symbol]])
  if (!is.null(hit)) {
    assign(gene_symbol, hit, envir = .domain_memo)
    return(hit)
  }

  # 3-4. web: first source that has domains; else keep the best answer we got
  res  <- NULL
  best <- NULL
  for (fetch in list(get_domains_uniprot, get_domains_ensembl)) {
    r <- tryCatch(fetch(gene_symbol), error = function(e) NULL)
    if (is.null(r)) next
    if (is.null(best) || (is.na(best$prot_length) && !is.na(r$prot_length))) best <- r
    if (nrow(r$domains) > 0) {
      if (is.na(r$prot_length) && !is.null(best)) r$prot_length <- best$prot_length
      res <- r
      break
    }
  }

  if (!is.null(res)) {
    # Save successes to disk so the gene is instant next session
    cache[[gene_symbol]] <- res
    tryCatch(saveRDS(cache, cache_file), error = function(e) NULL)
  } else {
    # Nothing found (or offline): remember for this session only, so the next
    # session tries again
    if (is.null(best)) {
      # Every request failed (offline, or the services are down)
      res <- list(domains = empty_domains(), prot_length = NA_integer_,
                  source = "not available")
    } else {
      # The gene was found, but no domains are annotated
      res <- best
      res$source <- "none found"
    }
  }
  assign(gene_symbol, res, envir = .domain_memo)
  res
}

# GRanges for trackViewer. With no domains, a plain grey bar for the protein
# is drawn, so the variants are still shown.
domains_to_features <- function(dom_res, seq_name, prot_len) {
  d <- dom_res$domains
  if (is.null(d) || nrow(d) == 0) {
    gr <- GRanges(seq_name, IRanges(1L, as.integer(prot_len)))
    names(gr) <- " "
    mcols(gr)$fill   <- "#DDDDDD"
    mcols(gr)$height <- 0.04
    return(gr)
  }
  d  <- d[!is.na(d$start) & !is.na(d$end), , drop = FALSE]
  gr <- GRanges(seq_name, IRanges(d$start, d$end))
  names(gr) <- d$name
  mcols(gr)$fill   <- rep_len(c("#FF8833", "#51C6E6", "#DFA32D", "#AAAAAA"), nrow(d))
  mcols(gr)$height <- 0.08
  gr
}

# Colours for VEP consequence terms; anything else is drawn black
CONSEQUENCE_COLORS <- c(
  stop_gained             = "red",
  frameshift_variant      = "purple",
  splice_acceptor_variant = "darkorange",
  splice_donor_variant    = "darkorange",
  start_lost              = "darkred",
  stop_lost               = "brown",
  missense_variant        = "steelblue",
  inframe_insertion       = "seagreen",
  inframe_deletion        = "seagreen",
  protein_altering_variant = "cadetblue",
  splice_region_variant   = "orange",
  synonymous_variant      = "grey"
)

# ══ UI ═════════════════════════════════════════════════════════════════════════
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
    div(style = "margin-top: 6px;",
      downloadButton(ns("download_png"), "Download PNG", class = "btn-sm"),
      downloadButton(ns("download_pdf"), "Download PDF", class = "btn-sm"),
      tags$span("PNG: 300 dpi image. PDF: sharp at any size (best for figures).",
                style = "color:#888; font-size:12px; margin-left:8px;")
    ),
    br(),
    h4("Variant & Domain Summary"),
    DT::dataTableOutput(ns("summaryTable"))
  )
}

# ══ Server ═════════════════════════════════════════════════════════════════════
# pheno and list_of_files may be passed as plain values or as functions /
# reactives returning them; functions are re-read each time, so phenotype
# edits and newly uploaded samples are picked up.
lolliplotServer <- function(id, variant_data_reactive = NULL, pheno, list_of_files,
                            all_variants_reactive = NULL) {
  # backwards-compatibility alias
  if (is.null(variant_data_reactive) && !is.null(all_variants_reactive))
    variant_data_reactive <- all_variants_reactive
  current <- function(x) if (is.function(x)) x() else x

  moduleServer(id, function(input, output, session) {

    # Update gene choices, keeping the selected gene if it is still available
    # (without 'selected', every data refresh cleared the choice)
    observeEvent(variant_data_reactive(), {
      genes <- sort(unique(na.omit(variant_data_reactive()$GeneName)))
      sel   <- isolate(input$selected_gene)
      updateSelectizeInput(session, "selected_gene", choices = genes,
                           selected = if (isTRUE(sel %in% genes)) sel else character(0),
                           server = TRUE)
    })

    # One domain lookup per gene, shared by the plot and the table
    domains_for_gene <- reactive({
      req(input$selected_gene)
      gene <- input$selected_gene
      if (exists(gene, envir = .domain_memo, inherits = FALSE))
        return(get_protein_domains(gene))
      withProgress(message = paste("Looking up protein domains for", gene, "…"),
                   value = 0.3, get_protein_domains(gene))
    })

    # Variants in the selected gene, with carrier samples and phenotypes
    variants_for_gene <- reactive({
      req(input$selected_gene)
      df <- variant_data_reactive()
      df <- df[which(df$GeneName == input$selected_gene), , drop = FALSE]

      # ── Resolve amino acid position ──────────────────────────────────────────
      # Strategy 1: digits embedded in protein_change (e.g. "I428P", "p.Ile428Pro")
      if ("protein_change" %in% names(df)) {
        df$AA_pos <- suppressWarnings(as.numeric(str_extract(df$protein_change, "\\d+")))
      } else {
        df$AA_pos <- rep(NA_real_, nrow(df))
      }
      # Strategy 2: separate position column (upload module renames Protein_position)
      for (pos_col in c("protPos", "Protein_position", "prot_pos")) {
        if (pos_col %in% names(df)) {
          missing <- is.na(df$AA_pos)
          # "123-125" style ranges: use the first number
          df$AA_pos[missing] <- suppressWarnings(
            as.numeric(str_extract(as.character(df[[pos_col]][missing]), "\\d+")))
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
      df <- df[!is.na(df$AA_pos), , drop = FALSE]
      if (nrow(df) == 0) return(df)

      # Carrier samples
      patient_info <- tibble()
      for (patient_file in current(list_of_files)) {
        if (!exists(patient_file, envir = .GlobalEnv)) next
        geno <- get(patient_file, envir = .GlobalEnv) %>% mutate_all(as.character)
        matches <- geno %>% filter(ID %in% df$ID) %>% mutate(Patient = patient_file)
        patient_info <- bind_rows(patient_info, matches)
      }

      # Phenotypes
      ph <- current(pheno)
      if (nrow(patient_info) > 0 && is.data.frame(ph) &&
          all(c("Patient", "Term_1") %in% names(ph))) {
        patient_info <- left_join(
          patient_info,
          ph %>% dplyr::select(Patient, Term_1) %>% mutate(Patient = as.character(Patient)),
          by = "Patient", relationship = "many-to-many")
      } else if (nrow(patient_info) > 0) {
        patient_info$Term_1 <- NA_character_
      }

      if (nrow(patient_info) > 0) {
        info_summary <- patient_info %>%
          group_by(ID) %>%
          summarize(
            Patients   = paste(unique(Patient), collapse = ", "),
            Phenotypes = paste(unique(na.omit(Term_1)), collapse = ", "),
            .groups = "drop"
          )
        df <- left_join(df, info_summary, by = "ID")
      } else {
        df$Patients   <- NA_character_
        df$Phenotypes <- NA_character_
      }
      df
    })

    # ── Lollipop plot ─────────────────────────────────────────────────────────
    # Draws on whatever graphics device is open: the screen (renderPlot) or a
    # PNG/PDF file (download buttons), so downloads match the screen exactly.
    draw_lollipop <- function() {
      df   <- variants_for_gene()
      gene <- input$selected_gene
      if (nrow(df) == 0) {
        plot.new()
        title("No variants with a protein position in this gene (after the sidebar filters).")
        return(invisible())
      }

      dom      <- domains_for_gene()
      seq_name <- paste0("chr", gene)
      prot_len <- dom$prot_length
      max_seen <- max(c(df$AA_pos, dom$domains$end), na.rm = TRUE)
      if (is.na(prot_len) || prot_len < max_seen) prot_len <- max_seen + 10

      features <- domains_to_features(dom, seq_name, prot_len)
      seqlengths(features) <- setNames(as.integer(prot_len), seq_name)

      variant_gr <- GRanges(seq_name, IRanges(start = df$AA_pos, width = 1),
                            names = paste0("var", seq_along(df$AA_pos)))
      mcols(variant_gr)$score <- 1
      cols <- unname(CONSEQUENCE_COLORS[as.character(df$Consequence)])
      cols[is.na(cols)] <- "black"
      mcols(variant_gr)$color <- cols

      plot_range <- GRanges(seq_name, IRanges(1L, as.integer(prot_len)))
      dom_label  <- if (nrow(dom$domains) > 0) dom$source else
                    if (dom$source == "not available") "lookup failed (offline?)" else "none found"
      plot_title <- paste0(gene, "  |  Protein domains: ", dom_label,
                           "  |  n = ", nrow(df), " variant", if (nrow(df) == 1) "" else "s")
      lolliplot(variant_gr, features, ranges = plot_range)
      title(main = plot_title, cex.main = 0.95, font.main = 1, col.main = "#444444")
      invisible()
    }

    output$lollipopPlot <- renderPlot(draw_lollipop())

    # ── Downloads ─────────────────────────────────────────────────────────────
    plot_filename <- function(ext) {
      gene <- gsub("[^A-Za-z0-9._-]", "_", input$selected_gene %||% "gene")
      paste0("lollipop_", gene, "_", Sys.Date(), ".", ext)
    }
    PLOT_W_IN <- 11; PLOT_H_IN <- 5     # inches

    output$download_png <- downloadHandler(
      filename = function() plot_filename("png"),
      content  = function(file) {
        req(input$selected_gene)
        if (capabilities("cairo"))
          png(file, width = PLOT_W_IN, height = PLOT_H_IN, units = "in", res = 300, type = "cairo")
        else
          png(file, width = PLOT_W_IN, height = PLOT_H_IN, units = "in", res = 300)
        on.exit(dev.off(), add = TRUE)
        draw_lollipop()
      }
    )

    output$download_pdf <- downloadHandler(
      filename = function() plot_filename("pdf"),
      content  = function(file) {
        req(input$selected_gene)
        # cairo_pdf embeds fonts and handles symbols (e.g. the * in stop codons)
        if (capabilities("cairo"))
          cairo_pdf(file, width = PLOT_W_IN, height = PLOT_H_IN)
        else
          pdf(file, width = PLOT_W_IN, height = PLOT_H_IN)
        on.exit(dev.off(), add = TRUE)
        draw_lollipop()
      }
    )

    # ── Summary table ─────────────────────────────────────────────────────────
    output$summaryTable <- DT::renderDataTable({
      df <- variants_for_gene()
      req(nrow(df) > 0)

      variant_tbl <- data.frame(
        Type        = "Variant",
        Position    = as.character(df$AA_pos),
        Description = df$Consequence,
        Patients    = ifelse(is.na(df$Patients), "", df$Patients),
        Phenotypes  = ifelse(is.na(df$Phenotypes), "", df$Phenotypes),
        Color       = unname(CONSEQUENCE_COLORS[as.character(df$Consequence)]),
        stringsAsFactors = FALSE
      )
      variant_tbl$Color[is.na(variant_tbl$Color)] <- "black"

      d <- domains_for_gene()$domains
      combined_tbl <- if (nrow(d) > 0) {
        bind_rows(variant_tbl, data.frame(
          Type        = "Domain",
          Position    = paste0(d$start, "-", d$end),
          Description = d$name,
          Color       = rep_len(c("#FF8833", "#51C6E6", "#DFA32D", "#AAAAAA"), nrow(d)),
          stringsAsFactors = FALSE))
      } else variant_tbl

      DT::datatable(combined_tbl, rownames = FALSE, options = list(pageLength = 5))
    })
  })
}
