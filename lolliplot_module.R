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
lolliplotServer <- function(id, variant_data_reactive, pheno, list_of_files) {
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
    
    # Fetch protein domains via biomaRt
    get_protein_domains <- function(gene_symbol) {
      ensembl <- useMart("ensembl", dataset = "hsapiens_gene_ensembl")
      domain_info <- tryCatch({
        getBM(
          attributes = c("external_gene_name", "uniprotswissprot", "pfam",
                         "pfam_start", "pfam_end", "description"),
          filters = "hgnc_symbol",
          values = gene_symbol,
          mart = ensembl
        )
      }, error = function(e) {
        warning("biomaRt query failed: ", conditionMessage(e))
        return(NULL)
      })
      
      if (is.null(domain_info) || nrow(domain_info) == 0) return(NULL)
      domain_info <- domain_info[!is.na(domain_info$pfam_start) & !is.na(domain_info$pfam_end), ]
      if (nrow(domain_info) == 0) return(NULL)
      
      domain_colors <- rep_len(c("#FF8833", "#51C6E6", "#DFA32D", "#AAAAAA"), nrow(domain_info))
      domain_gr <- GRanges(
        seqnames = Rle(paste0("chr", gene_symbol), nrow(domain_info)),
        ranges = IRanges(start = domain_info$pfam_start, end = domain_info$pfam_end),
        names = domain_info$pfam
      )
      mcols(domain_gr)$feature <- domain_info$description
      mcols(domain_gr)$fill <- domain_colors
      mcols(domain_gr)$height <- 0.08
      domain_gr
    }
    
    # Reactive filtered variants for selected gene
    variants_for_gene <- reactive({
      req(input$selected_gene)
      df <- variant_data_reactive()
      df <- df[df$GeneName == input$selected_gene, ]
      df$AA_pos <- suppressWarnings(as.numeric(str_extract(df$protein_change, "\\d+")))
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
      mcols(variant_gr)$color <- consequence_colors[as.character(df$Consequence_VEP)]
      mcols(variant_gr)$color[is.na(mcols(variant_gr)$color)] <- "black"
      
      
      # hover info: Patient + Term_1
      mcols(variant_gr)$label <- paste0(
        df$Consequence_VEP,
        "\nPatients: ", ifelse(is.na(df$Patients), "NA", df$Patients),
        "\nPhenotypes: ", ifelse(is.na(df$Phenotypes), "NA", df$Phenotypes)
      )
      lolliplot(variant_gr, domain_gr)
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
        Description = df$Consequence_VEP,
        Patients = ifelse(is.na(df$Patients), "", df$Patients),
        Phenotypes = ifelse(is.na(df$Phenotypes), "", df$Phenotypes),
        Color = consequence_colors[as.character(df$Consequence_VEP)]
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
