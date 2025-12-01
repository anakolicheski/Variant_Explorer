library(dplyr)
library(readr)

parse_and_filter_variants <- function(input_path, output_prefix) {
  # Read file
  variants <- read.delim(input_path)
  
  # Convert AF column to numeric and summarize
  variants$db_pop_freq_max_AF <- as.numeric(variants$db_pop_freq_max_AF)
  freq_summary_pre <- summary(variants$db_pop_freq_max_AF)
  
  # Filter on AF < 0.01 or NA
  variants_f <- subset(variants, db_pop_freq_max_AF < 0.01 | is.na(db_pop_freq_max_AF))
  freq_summary_post <- summary(variants_f$db_pop_freq_max_AF)
  
  # Convert CADD to numeric and summarize
  variants_f$CADD_phred <- as.numeric(variants_f$CADD_phred)
  cadd_summary <- summary(variants_f$CADD_phred)
  
  # Create ID and reorder columns
  variants_f$ID <- paste0(variants_f$CHROM, variants_f$POS, variants_f$REF, variants_f$ALT)
  variants_f <- variants_f %>% select(ID, everything())
  
  # Create output for CADD
  variants_forCADD <- variants_f %>% select(CHROM, POS, ID, REF, ALT)
  write_tsv(variants_forCADD, file = paste0(output_prefix, "_forCADD.tsv"))
  
  # Save filtered table
  write_tsv(variants_f, file = paste0(output_prefix, "_filtered.tsv"))
  
  # Write summaries to a text file
  summary_file <- paste0(output_prefix, "_summaries.txt")
  sink(summary_file)
  cat("=== Frequency Summary (Before Filtering) ===\n")
  print(freq_summary_pre)
  cat("\n=== Frequency Summary (After Filtering) ===\n")
  print(freq_summary_post)
  cat("\n=== CADD_phred Summary (After Filtering) ===\n")
  print(cadd_summary)
  sink()  # close the connection to the file
  
  # Return useful objects
  return(list(
    freq_summary_pre_filter = freq_summary_pre,
    freq_summary_post_filter = freq_summary_post,
    cadd_summary_post_filter = cadd_summary,
    filtered_variants = variants_f
  ))
}

####Example usage

result <- parse_and_filter_variants(
  input_path = "Y:/Active/exomes/Results/MCUI234/final_variants.filtered.tsv",
  output_prefix = "MCUI2234"
)

