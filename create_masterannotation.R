#This scriptis to update the master annotation by adding new genotypes. Fisrt, need to harmonize all columns so they match type (e.g. character, numeric etc)

library(readr)
library(dplyr)

# Directory with your original files
input_dir <- "Y:/Active/exome_database/Rshiny/New_annotations/"
file_list <- list.files(input_dir, pattern = "\\.tsv$", full.names = TRUE)

# Inspect each file’s column types
column_type_list <- lapply(file_list, function(f) {
  df <- suppressWarnings(read_tsv(f, n_max = 100, show_col_types = FALSE)) # read small portion
  sapply(df, class)
})

names(column_type_list) <- basename(file_list)



# Flatten into a long format for comparison
all_types <- do.call(rbind, lapply(names(column_type_list), function(fname) {
  types <- column_type_list[[fname]]
  data.frame(file = fname, column = names(types), type = unlist(types), stringsAsFactors = FALSE)
}))

# Decide the dominant type per column (most frequent type)
reference_types <- all_types %>%
  group_by(column) %>%
  count(type, sort = TRUE) %>%
  slice(1) %>%
  select(column, type) %>%
  deframe()

print(reference_types)


# Function to coerce column to desired type
coerce_column <- function(column, to_type) {
  suppressWarnings({
    if (to_type == "numeric") return(as.numeric(column))
    if (to_type == "character") return(as.character(column))
    if (to_type == "integer") return(as.integer(column))
    if (to_type == "logical") return(as.logical(column))
    return(column)  # fallback
  })
}

# Read, fix, and store cleaned files
cleaned_list <- lapply(file_list, function(f) {
  df <- suppressWarnings(read_tsv(f, show_col_types = FALSE))
  
  # Ensure all expected columns exist
  missing_cols <- setdiff(names(reference_types), colnames(df))
  for (mc in missing_cols) {
    df[[mc]] <- NA
  }
  
  # Coerce columns to reference types
  for (col in names(reference_types)) {
    df[[col]] <- coerce_column(df[[col]], reference_types[[col]])
  }
  
  df
})


# Combine all cleaned data frames
merged_annotations <- bind_rows(cleaned_list)

# Remove duplicates by ID
final_annotations <- merged_annotations %>%
  distinct(ID, .keep_all = TRUE)

# Save to disk
write_tsv(final_annotations, file.path(input_dir, "master_annotation.tsv"))

cat("✅ Master annotation file saved.\n")


#Separate intronic and other unwanted consequences - run those on different predictors and create a new category on database later on

intronic_variants <- final_annotations[grepl("intron_variant", final_annotations$Consequence_VEP_clean), ]
non_intronic_variants <- final_annotations[!grepl("intron_variant", final_annotations$Consequence_VEP_clean), ]

##Code above returns some variants that are classified as something else on CADD (refer to table saved on folder), so we need to separate intronic on CADD and intronic on VEP

intronic_in_vep <- grepl("intron_variant", final_annotations$Consequence_VEP)
intronic_in_cadd <- grepl("INTRONIC", final_annotations$Consequence_CADD)
intronic_variants <- final_annotations[intronic_in_vep & intronic_in_cadd, ]
non_intronic_variants <- final_annotations[!(intronic_in_vep & intronic_in_cadd), ]




