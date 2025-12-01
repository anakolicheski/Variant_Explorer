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

# Load genotypes
list_of_files <- list.files(path = "New_genotypes/", pattern = "_geno\\.tsv$", full.names = TRUE)
Genotypes <- lapply(list_of_files, read_tsv)
list_of_files <-tools::file_path_sans_ext(basename(list_of_files))  ##changed to also run on Mac
list_of_files <- str_remove(list_of_files, "_geno$")
names(Genotypes) <- list_of_files
list2env(Genotypes, envir = .GlobalEnv)


# Define UI
ui <- fluidPage(
  theme = shinytheme("flatly"),
  titlePanel("Cooper Lab Genetic Variants"),
  sidebarLayout(
    sidebarPanel(
      # File input for gene list
      fileInput("geneListFile", "Upload Gene List", accept = c(".csv", ".tsv")),
      # Filter input fields
      checkboxGroupInput("Variant_Type", "Filter by Variant Type:",
                         c(
                           "Select All" = "all",
                           "Deselect all" = "none", #Added deselect all option
                           "synonymous variant" = "synonymous_variant",
                           "5' prime UTR variant" = "5_prime_UTR_variant",
                           "3' prime UTR variant" = "3_prime_UTR_variant",
                           "splice region variant" = "splice_region_variant",
                           "splice donor variant" = "splice_donor_variant",
                           "inframe insertion" = "inframe_insertion",
                           "inframe deletion" = "inframe_deletion",
                           "missense variant" = "missense_variant",
                           "stop gained" = "stop_gained",
                           "stop lost" = "stop_lost",
                           "stop retained_variant" = "stop_retained_variant",
                           "start lost" = "start_lost",
                           "frameshift variant" = "frameshift_variant"
                         ),
                         selected = "all" # Default selection
      ),
      
      #Select input for Phenotypes, server bit pulls Terms from Phenotype.xlsx table 
      selectInput("PhenotypeTerm", "Filter by Phenotype Term:",
                  choices = NULL, selected = NULL, multiple = TRUE),
      
      #Select input for Patient, server bit adds all current samples as options
      selectInput("Patient", "Filter by Patient family:",
                  names(Genotypes), multiple = TRUE
      ),
      
      #Slider input for CADD scores (PHRED)
      sliderInput("cadd_filter", "Filter by CADD PHRED Score:",
                  min = 0, max = 50, value = c(0, 50), step = 1),
      helpText("PHRED scores > 20 are generally considered deleterious for coding variants")
    ),
    #main body
    mainPanel(
      # Tabset panels - adds multiple tabs
      tabsetPanel(
        id = "main_tabs",
        selected = "Genetic Variants",
        
        tabPanel("Variant Types",
                 fluidRow(
                   column(4, plotOutput("ConsequencePieChart_VEP", height = "300px")),
                   column(4, plotOutput("ConsequencePieChart_CADD", height = "300px")),
                   column(4, plotOutput("PHRED_Histogram", height = "300px"))
                 ),
                 br(),
                 DT::DTOutput("Variant_Type"),
                 br(),
                 DT::DTOutput("Matching_ID_Table"),
                 h3("Variants + Genotypes"),
                 DTOutput("GeneList_Genotype_Table"),
                 br(),
                 downloadButton("downloadGeneListGenotypes", "Download Variants and Genotypes"),
                 downloadButton("downloadVariantType", "Download Variant Types")
        ),
        
        tabPanel("Phenotypes",
                 # Table output for Phenotypes.xlsx
                 DT::DTOutput("Phenotypes_Table"),
                 width = 8
        ),
        tabPanel("Joined Patients Table",
                 # Table output for joined table
                 tags$h4("Joined Table (Union of Variants Across Selected Patients)"),
                 DT::DTOutput("Joined_Table"),
                 tags$h4("Variants Shared by Selected Patients"),
                 DT::DTOutput("Joined_Table_matching"),
                 downloadButton("downloadJoinedTable", "Download Joined Table"),
                 downloadButton("downloadmatchedJoinedTable", "Download matched Joined Table"),
                 width = 8
        ),
        tabPanel("Common Genes by Patient Table",
                 # Table output for joined Gene table
                 DT::DTOutput("Joined_Gene_Table"),
                 downloadButton("downloadGeneTable", "Download Gene Table"),
                 width = 8
        ),
        
        # Add new tab for editable table
        tabPanel("Candidate Variants",
                 h3("Store Candidate Variants"),
                 DT::DTOutput("candidate_variants_table"),
                 br(),
                 actionButton("add_row", "Add Row"),
                 actionButton("delete_row", "Delete Selected Row"),
                 actionButton("save_csv", "Save Changes to CSV"),
                 verbatimTextOutput("selected_row"),  # To show selected row index (for debugging)
                 downloadButton("downloadCandidateVariants", "Download Candidate Variants"),
        ),
        
        #Lolliplot panel 
        tabPanel("Lollipop Plot", lolliplotUI("geneLollipop")
        ), 
        
        tabPanel("Alignment paths",
                 # Table output for cram_paths.xlsx
                 DT::DTOutput("Cram_paths"),
                 width = 8
        
     )
    )
   )
  )
 )

# Define server
server <- function(input, output, session) {
  
  # Read data from files
  variants <- read_tsv("annotations_fordb_4.tsv")
  pheno <- read_excel("Phenotypes.xlsx")
  crams <- read_excel("cram_paths.xlsx")
  
  # Reactive value for the uploaded gene list
  uploaded_genes <- reactiveVal(NULL)
  
  # Pre-combine all genotype files into one table once
  all_genotypes <- bind_rows(
    lapply(names(Genotypes), function(patient_file) {
      df <- Genotypes[[patient_file]] %>% mutate_all(as.character)
      df$Patient <- patient_file
      df
    })
  )
  
  observeEvent(input$geneListFile, {
    req(input$geneListFile)
    
    # Read the uploaded file
    gene_data <- read.csv(input$geneListFile$datapath)
    
    # Assuming the gene list file has a column named "Gene"
    if ("Gene" %in% colnames(gene_data)) {
      uploaded_genes(gene_data$Gene)
    } else {
      showModal(modalDialog(
        title = "Error",
        "The uploaded file does not contain a column named 'Gene'.",
        easyClose = TRUE
      ))
      uploaded_genes(NULL)
    }
  })
  
  color_zygosity_columns <- function(dt, df) {
    genotype_cols <- names(df)[str_detect(names(df), "\\.zygosity$")]
    if (length(genotype_cols) == 0) return(dt)
    
    for (col in genotype_cols) {
      dt <- dt %>% formatStyle(
        columns = col,
        target = 'cell',
        backgroundColor = styleEqual(
          c("Het", "Hom Ref", "Hom Alt"),
          c("yellow", "lightgreen", "tomato")
        )
      )
    }
    dt
  }
  
  ## function for variant type filter (check box)
  observeEvent(input$Variant_Type, {
    selected <- input$Variant_Type
    
    all_variants <- c(
      "synonymous_variant",
      "5_prime_UTR_variant",
      "3_prime_UTR_variant",
      "splice_region_variant",
      "splice_donor_variant",
      "inframe_insertion",
      "inframe_deletion",
      "missense_variant",
      "stop_gained",
      "stop_lost",
      "stop_retained_variant",
      "start_lost",
      "frameshift_variant"
    )
    
    # Handle Select All
    if ("all" %in% selected) {
      updateCheckboxGroupInput(session, "Variant_Type",
                               selected = all_variants)
    }
    # Handle Deselect All
    else if ("none" %in% selected) {
      updateCheckboxGroupInput(session, "Variant_Type",
                               selected = character(0))
    }
  })
  
  ##Select patients automatically based on a phenotype - doesn't work if the parents are the ones with the phenotype so far
  # Generate list of unique phenotype terms across all 5 columns
  observe({
    all_terms <- unique(unlist(pheno[, c("Term_1", "Term_2", "Term_3", "Term_4", "Term_5")]))
    all_terms <- sort(na.omit(all_terms))
    updateSelectInput(session, "PhenotypeTerm", choices = all_terms)
  })
  
  observeEvent(input$PhenotypeTerm, {
    req(input$PhenotypeTerm)
    
    matching_patients <- pheno %>%
      filter(if_any(starts_with("Term"), ~ . %in% input$PhenotypeTerm)) %>%
      pull(Patient) %>%
      unique()
    
    updateSelectInput(session, "Patient", selected = matching_patients)
  })
  
  
  # Define reactive expression to filter data based on an uploaded gene list file e.g. IUIS-IEI gene list
  Variant_type_reac <- reactive({
    filtered_data <- variants
    
    if (!("all" %in% input$Variant_Type)) {
      filtered_data <- filtered_data %>%
        filter(Consequence_VEP %in% input$Variant_Type)
    }
    
    # Filter by uploaded genes if available
    if (!is.null(uploaded_genes())) {
      filtered_data <- filtered_data %>%
        filter(GeneName %in% uploaded_genes())
    }
    
    # Filter by CADD score
    if (!is.null(input$cadd_filter)) {
      filtered_data <- filtered_data %>%
        mutate(PHRED = as.numeric(PHRED)) %>%
        filter(!is.na(PHRED), PHRED >= input$cadd_filter[1], PHRED <= input$cadd_filter[2])
    }
    
    filtered_data %>%
      dplyr::select(CHROM, Pos, Ref, Alt, GeneName, Consequence_CADD, Consequence_VEP, 
                    protein_change,PHRED,db_pop_freq_max,db_pop_freq_max_AF,
                    gnomADw_AF,gnomADe_AF,gnomADe_Hom,Existing_variation,Codons,
                    cDNApos,CDSpos,protPos,SIFTcat,PolyPhenCat,clinvar_CLINSIGN,clinvar_PHENOTYPE,HGVSc,HGVSp,best_rank, ID)
  })
  
  output$Variant_Type <- renderDT({
    datatable(Variant_type_reac(), selection = 'single', filter = 'top')
  })
  
  # Pie charts of Consequences annotated by VEP
  output$ConsequencePieChart_VEP <- renderPlot({
    req(Variant_type_reac())  # Ensure filtered data is available
    
    # Get the filtered table from DT based on selected rows
    filtered_data <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
    
    # Check if Consequence_VEP column exists
    if (!"Consequence_VEP" %in% colnames(filtered_data)) {
      return(NULL)
    }
    
    # Count occurrences of each consequence type
    consequence_counts <- filtered_data %>%
      count(Consequence_VEP, name = "count") %>%
      arrange(desc(count))
    
    # Create pie chart for Consequence_VEP
    ggplot(consequence_counts, aes(x = "", y = count, fill = Consequence_VEP)) +
      geom_bar(stat = "identity", width = 1) +
      coord_polar("y", start = 0) + 
      labs(title = "Variant Type Distribution (VEP)", fill = "Consequence_VEP") +
      theme_minimal() +
      theme(axis.text = element_blank(),
            axis.ticks = element_blank(),
            panel.grid = element_blank())
  })
  
  #same but for Consequence annotated by CADD
  output$ConsequencePieChart_CADD <- renderPlot({
    req(input$Variant_Type_rows_all)  # Ensure rows exist
    
    # Get the filtered table from DT based on selected rows
    filtered_data <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
    
    # Check if Consequence_CADD column exists
    if (!"Consequence_CADD" %in% colnames(filtered_data)) {
      return(NULL)
    }
    
    # Count occurrences of each consequence type in Consequence_CADD
    consequence_counts_CADD <- filtered_data %>%
      count(Consequence_CADD, name = "count") %>%
      arrange(desc(count))
    
    # Create pie chart for Consequence_CADD
    ggplot(consequence_counts_CADD, aes(x = "", y = count, fill = Consequence_CADD)) +
      geom_bar(stat = "identity", width = 1) +
      coord_polar("y", start = 0) + 
      labs(title = "Consequence_CADD Distribution", fill = "Consequence_CADD") +
      theme_minimal() +
      theme(axis.text = element_blank(),
            axis.ticks = element_blank(),
            panel.grid = element_blank())
  })
  
  #histogram of CADD PHRED scores
  output$PHRED_Histogram <- renderPlot({
    req(input$Variant_Type_rows_all)  # Ensure rows exist
    
    # Get the filtered table from DT based on selected rows
    filtered_data <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
    
    # Create histogram for PHRED scores
    ggplot(filtered_data, aes(x = PHRED)) +
      geom_histogram(bins = 30, fill = "steelblue", color = "black", alpha = 0.7) +
      theme_minimal() +
      labs(title = "Distribution of PHRED Scores", x = "PHRED Score", y = "Count")
  })
  ### Variant + Genotype reactive 
  
  GeneList_Genotype_Table <- reactive({
    displayed_rows <- input$Variant_Type_rows_all
    if (is.null(displayed_rows) || length(displayed_rows) == 0) return(tibble())
    
    filtered_variants <- Variant_type_reac()[displayed_rows, , drop = FALSE]
    
    # Join all genotypes at once to filtered variants
    results <- all_genotypes %>%
      inner_join(filtered_variants, by = "ID")
    
    genotype_cols <- names(results)[str_detect(names(results), "\\.zygosity$")]
    
    results <- results %>% 
      dplyr::select(Patient, GeneName,all_of(genotype_cols), Consequence_VEP, Consequence_CADD, PHRED,protein_change,db_pop_freq_max,db_pop_freq_max_AF,
                    gnomADw_AF,gnomADe_AF,gnomADe_Hom,Existing_variation,Codons,
                    cDNApos,CDSpos,protPos,SIFTcat,PolyPhenCat,clinvar_CLINSIGN,clinvar_PHENOTYPE,HGVSc,HGVSp) %>%
      #DROP NA columns 
      
      select(where(~ any(!is.na(.))))
    
    return(results)
    
  })
  
  # Output the Phenotypes.xlsx table
  output$Phenotypes_Table <- renderDT({
    datatable(pheno, filter = 'top')
  })
  
  #Output the cram_paths.xlsx table 
  
  output$Cram_paths <- renderDT({
    datatable(crams, filter = 'top')
  })
  
  ##Output lolipop plot
  # In server:
  lolliplotServer("geneLollipop", 
                  variant_data_reactive = Variant_type_reac, 
                  pheno = pheno, 
                  list_of_files = list_of_files)
  
  
  #Joins annotation with selected patient genotypes
  
  Joined_Table <- reactive({
    req(input$Patient)  # Ensure patients are selected before proceeding
    
    # Get genotype tables for the selected patients
    genotype_tables <- map(input$Patient, ~get(.x))
    
    # Ensure columns are of consistent types
    genotype_tables <- map(genotype_tables, ~mutate_all(., as.character))
    
    # Join genotype tables for all selected patients
    joined_tables <- map(genotype_tables, ~full_join(., variants, by = "ID", suffix = c("_genotypes", "_variants")))
    
    # Combine joined tables into one
    joined_table <- bind_rows(joined_tables)
    
    # Filter out rows where "Het" or "Hom Alt" are not present in any column
    joined_table <- joined_table %>%
      filter_all(any_vars(str_detect(., "Het|Hom Alt"))) %>%
      dplyr::select(GeneName, Consequence_VEP, Consequence_CADD, PHRED, contains("zygosity")) %>%
      dplyr::select(!matches("\\.y$"))
    
    return(joined_table)
  })
  
  #Joins exact matching variants between samples
  Joined_Table_matching <- reactive({
    req(input$Patient)  # Ensure patients are selected before proceeding
    
    # Get genotype tables for the selected patients
    genotype_tables <- map(input$Patient, ~get(.x))
    
    # Ensure columns are of consistent types
    genotype_tables <- map(genotype_tables, ~mutate_all(., as.character))
    
    # Join genotype tables for all selected patients
    joined_tables_1 <- map(genotype_tables, ~full_join(., variants, by = "ID", suffix = c("_genotypes", "_variants")))
    # Combine joined tables into one
    Joined_Table_matching <- purrr::reduce(joined_tables_1, full_join, by = "ID")
    
    # Filter out rows where "Het" or "Hom Alt" are not present in any column
    Joined_Table_matching <- Joined_Table_matching %>%
      filter_all(any_vars(str_detect(., "Het|Hom Alt")))
    
    # Filter out rows where certain zygosity columns are blank
    zygosity_columns <- Joined_Table_matching %>%
      dplyr::select(contains("zygosity")) %>%
      colnames()
    
    Joined_Table_matching <- Joined_Table_matching %>%
      filter(rowSums(dplyr::select(., all_of(zygosity_columns)) == 0) == 0) %>%
      dplyr::select(GeneName, Consequence_VEP, Consequence_CADD, contains("zygosity")) %>%
      dplyr::select(!matches("\\.y$"))
    
    return(Joined_Table_matching)
  })
  
  
  #Lists genes with variants in more than one of the selected patients
  Joined_Gene_Table <- reactive({
    req(input$Patient) # Ensure patients are selected before proceeding
    
    # Get genotype tables for the selected patients and add Patient column
    genotype_forgene_tables <- map(input$Patient, ~{
      genotype_table <- get(.x)
      genotype_table <- mutate(genotype_table, Patient = .x)
      mutate_all(genotype_table, as.character)
    })
    
    # Join genotype tables with variants by ID
    joined_gene_table <- map(genotype_forgene_tables, ~left_join(., variants, by = "ID", suffix = c("_genotypes", "_variants")))
    
    # Combine all joined tables into one big table
    big_joined_table <- bind_rows(joined_gene_table)
    
    # Filter out rows where "Het" or "Hom Alt" are not present in any column
    big_joined_table <- big_joined_table %>%
      filter_all(any_vars(str_detect(., "Het|Hom Alt")))
    
    # Summarize the genes that have variants in more than one patient
    summarized_genes <- big_joined_table %>%
      group_by(GeneName) %>%
      summarise(Num_Patients = n_distinct(Patient), .groups = 'drop') %>%
      filter(Num_Patients > 1) %>%
      left_join(big_joined_table, by = "GeneName")
    
    return(summarized_genes)
  })
  
  # Output joined Gene table
  output$Joined_Gene_Table <- renderDT({
    req(input$Patient) # Ensure a patient is selected before rendering table
    datatable(Joined_Gene_Table(), filter = 'top')
  })
  
  # Output joined table
  output$Joined_Table <- renderDT({
    req(input$Patient) # Ensure a patient is selected before rendering table
    df <- Joined_Table()
    dt <- datatable(df, filter = 'top', options = list(scrollX = TRUE))
    color_zygosity_columns(dt, df)
  })
  
  
  #Output joined matched table
  output$Joined_Table_matching <- renderDT({
    req(input$Patient) # Ensure a patient is selected before rendering tabl
    df <- Joined_Table_matching()
    dt <- datatable(df, filter = 'top', options = list(scrollX = TRUE))
    color_zygosity_columns(dt, df)
  })
  
  #Outut Variant + Genotype 
  
  output$GeneList_Genotype_Table <- renderDT({
    df <- GeneList_Genotype_Table()
    if (nrow(df) == 0) return(datatable(tibble(), options = list(dom = 't')))
    dt <- datatable(df, filter = "top", options = list(scrollX = TRUE))
    color_zygosity_columns(dt, df)
  })
  
  # Reactive expression to find rows with matching IDs among patient genotypes
  #clicking on a row from Variant Type table, will tell you which patients have the selected variant 
  
  # Pre-combine all genotype tables once at app startup
  all_genotypes <- bind_rows(
    lapply(names(Genotypes), function(patient_file) {
      df <- Genotypes[[patient_file]] %>% mutate_all(as.character)
      df$Patient <- patient_file
      df
    })
  )
  
  # Reactive for Matching ID Table
  Matching_ID_Table <- reactive({
    selected_row <- input$Variant_Type_rows_selected
    if (length(selected_row) == 0) return(tibble())  # nothing selected
    
    selected_id <- Variant_type_reac()[selected_row, "ID"]
    
    # Filter pre-combined table for matching IDs
    matching_results <- all_genotypes %>%
      filter(ID %in% selected_id) %>%
      left_join(pheno %>% dplyr::select(Patient, Term_1), by = "Patient")
    
    # Reorder columns: zygosity first, then useful info
    genotype_cols <- names(matching_results)[str_detect(names(matching_results), "\\.zygosity$")]
    
    matching_results <- matching_results %>%
      dplyr::select(Patient, Term_1, all_of(genotype_cols),
                    CHROM, POS, REF, ALT, everything()) %>%
      select_if(~ any(!is.na(.)))  # remove all-NA columns
    
    matching_results
  })
  
  # Output table with matching IDs
  output$Matching_ID_Table <- renderDT({
    df <- Matching_ID_Table()
    if (nrow(df) == 0) return(datatable(tibble(), options = list(dom = 't')))
    dt <- datatable(df, filter = 'top', options = list(scrollX = TRUE))
    color_zygosity_columns(dt, df)
  })
  
  # Download handler for the updated candidate variants table
  output$downloadCandidateVariants <- downloadHandler(
    filename = function() {
      paste("updated_candidate_variants_", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      write.csv(candidate_variants_data(), file, row.names = FALSE)
    }
  )
  
  # Load candidate variants from candidates.csv
  candidate_variants <- reactiveVal(read_csv("candidates.csv"))
  
  # Render the candidate variants table
  output$candidate_variants_table <- renderDT({
    datatable(candidate_variants(), editable = TRUE, selection = "single")
  })
  
  # Add row to candidate variants table
  observeEvent(input$add_row, {
    current_data <- candidate_variants()
    new_row <- as_tibble(matrix(NA, nrow = 1, ncol = ncol(current_data)))
    colnames(new_row) <- colnames(current_data)
    candidate_variants(bind_rows(current_data, new_row))
  })
  
  # Delete selected row
  observeEvent(input$delete_row, {
    req(input$candidate_variants_table_rows_selected)
    current_data <- candidate_variants()
    updated_data <- current_data[-input$candidate_variants_table_rows_selected, ]
    candidate_variants(updated_data)
  })
  
  # Save changes to CSV
  observeEvent(input$save_csv, {
    write_csv(candidate_variants(), "candidates.csv")
    showModal(modalDialog("Changes saved successfully!", easyClose = TRUE))
  })
  
  # Download handler for Variant Types
  
  output$downloadVariantType <- downloadHandler(
    filename = function() {
      paste("filtered_variant_types_", Sys.Date(), ".csv", sep = "")
    },
    content = function(file) {
      # Get the filtered table from DT based on selected rows
      filtered_data <- Variant_type_reac()[input$Variant_Type_rows_all, , drop = FALSE]
      
      # If no data is selected or the table is empty, return a message
      if (nrow(filtered_data) == 0) {
        write.csv(data.frame(Message = "No data selected"), file)
      } else {
        # Save the filtered data as a CSV file
        write.csv(filtered_data, file, row.names = FALSE)
      }
    }
  )
  
  # Download handler for Joined Table
  output$downloadJoinedTable <- downloadHandler(
    filename = function() { paste("joined_table-", Sys.Date(), ".csv", sep = "") },
    content = function(file) {
      write.csv(Joined_Table(), file)
    }
  )
  
  # Download handler for Joined Gene Table
  output$Joined_Gene_Table <- renderDT({
    req(input$Patient)
    df <- Joined_Gene_Table()
    dt <- datatable(df, filter = 'top', options = list(scrollX = TRUE))
    color_zygosity_columns(dt, df)
  })
  
  # Download handler for Joined Matched Table
  output$downloadGeneTable <- downloadHandler(
    filename = function() { paste("joined_matched_table-", Sys.Date(), ".csv", sep = "") },
    content = function(file) {
      write.csv(Joined_Table_matching(), file)
    }
  )
  output$downloadGeneListGenotypes <- downloadHandler(
    filename = function() {
      paste0("Variants_with_Genotypes_", Sys.Date(), ".csv")
    },
    content = function(file) {
      write.csv(GeneList_Genotype_Table(), file, row.names = FALSE)
    }
  )
}

# Run the Shiny app
shinyApp(ui, server)