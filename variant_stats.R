#Basic stats and plots

# Load required libraries
library(ggplot2)
library(dplyr)
library(gridExtra)
library(RColorBrewer)

# Read the final non-intronic dataset
data <- non_intronic_variants  # assuming this is your filtered dataset

# Create output directory for plots
dir.create("variant_statistics", showWarnings = FALSE)

# ========== BASIC STATISTICS ==========

# Overall summary statistics
summary_stats <- data.frame(
  Metric = c("Total variants", "Unique genes", "Variants with CADD > 20", 
             "Variants with CADD > 30", "Median CADD score"),
  Value = c(nrow(data), 
            length(unique(data$SYMBOL[!is.na(data$SYMBOL)])),
            sum(data$CADD_phred > 20, na.rm = TRUE),
            sum(data$CADD_phred > 30, na.rm = TRUE),
            round(median(data$CADD_phred, na.rm = TRUE), 2))
)

# Save summary statistics
write.table(summary_stats, "variant_statistics/summary_stats.tsv", 
            sep = "\t", row.names = FALSE, quote = FALSE)

# ========== TOP 20 GENES WITH HIGH CADD VARIANTS ==========

high_cadd_genes <- data %>%
  filter(PHRED > 20, !is.na(SYMBOL)) %>%
  group_by(SYMBOL) %>%
  summarise(
    variant_count = n(),
    mean_cadd = round(mean(PHRED, na.rm = TRUE), 2),
    max_cadd = round(max(PHRED, na.rm = TRUE), 2)
  ) %>%
  arrange(desc(variant_count)) %>%
  head(20)

# Save top genes with high CADD
write.table(high_cadd_genes, "variant_statistics/top20_genes_high_cadd.tsv", 
            sep = "\t", row.names = FALSE, quote = FALSE)

# Plot top 20 genes with high CADD variants
p1 <- ggplot(high_cadd_genes, aes(x = reorder(SYMBOL, variant_count), y = variant_count)) +
  geom_bar(stat = "identity", fill = "steelblue", alpha = 0.7) +
  coord_flip() +
  labs(title = "Top 20 Genes with Most High CADD Variants (>20)",
       x = "Gene Symbol", y = "Number of Variants") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8))

ggsave("variant_statistics/top20_genes_high_cadd.png", p1, width = 10, height = 8, dpi = 300)

# ========== CONSEQUENCE TYPE ANALYSIS ==========

# Count variants by consequence type
consequence_counts <- data %>%
  filter(!is.na(Consequence_VEP)) %>%
  group_by(Consequence_VEP) %>%
  summarise(count = n()) %>%
  arrange(desc(count))

write.table(consequence_counts, "variant_statistics/consequence_type_counts.tsv", 
            sep = "\t", row.names = FALSE, quote = FALSE)

# Plot consequence types
p2 <- ggplot(consequence_counts %>% head(15), 
             aes(x = reorder(Consequence_VEP, count), y = count)) +
  geom_bar(stat = "identity", fill = "darkgreen", alpha = 0.7) +
  coord_flip() +
  labs(title = "Top 15 Variant Consequence Types",
       x = "Consequence Type", y = "Number of Variants") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8))

ggsave("variant_statistics/consequence_types.png", p2, width = 10, height = 8, dpi = 300)

# ========== TOP GENES BY SPECIFIC CONSEQUENCE TYPES ==========

# Function to get top genes for specific consequence type
get_top_genes_by_consequence <- function(consequence_type, top_n = 10) {
  data %>%
    filter(grepl(consequence_type, Consequence_VEP, ignore.case = TRUE), 
           !is.na(SYMBOL)) %>%
    group_by(SYMBOL) %>%
    summarise(
      variant_count = n(),
      mean_cadd = round(mean(PHRED, na.rm = TRUE), 2)
    ) %>%
    arrange(desc(variant_count)) %>%
    head(top_n)
}

# Top genes with missense variants
missense_genes <- get_top_genes_by_consequence("missense", 15)
write.table(missense_genes, "variant_statistics/top_genes_missense.tsv", 
            sep = "\t", row.names = FALSE, quote = FALSE)

# Top genes with stop_gained variants
stop_gain_genes <- get_top_genes_by_consequence("stop_gained", 15)
write.table(stop_gain_genes, "variant_statistics/top_genes_stop_gain.tsv", 
            sep = "\t", row.names = FALSE, quote = FALSE)

# Top genes with synonymous variants
synonymous_genes <- get_top_genes_by_consequence("synonymous", 15)
write.table(synonymous_genes, "variant_statistics/top_genes_synonymous.tsv", 
            sep = "\t", row.names = FALSE, quote = FALSE)

# ========== PLOTS FOR SPECIFIC CONSEQUENCE TYPES ==========

# Missense variants plot
p3 <- ggplot(missense_genes, aes(x = reorder(SYMBOL, variant_count), y = variant_count)) +
  geom_bar(stat = "identity", fill = "orange", alpha = 0.7) +
  coord_flip() +
  labs(title = "Top 15 Genes with Missense Variants",
       x = "Gene Symbol", y = "Number of Variants") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8))

ggsave("variant_statistics/top_genes_missense.png", p3, width = 10, height = 8, dpi = 300)

# Stop gain variants plot
p4 <- ggplot(stop_gain_genes, aes(x = reorder(SYMBOL, variant_count), y = variant_count)) +
  geom_bar(stat = "identity", fill = "red", alpha = 0.7) +
  coord_flip() +
  labs(title = "Top 15 Genes with Stop Gain Variants",
       x = "Gene Symbol", y = "Number of Variants") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8))

ggsave("variant_statistics/top_genes_stop_gain.png", p4, width = 10, height = 8, dpi = 300)

# ========== CADD SCORE DISTRIBUTION ==========

# CADD score distribution
p5 <- ggplot(data %>% filter(!is.na(PHRED)), aes(x = PHRED)) +
  geom_histogram(bins = 50, fill = "purple", alpha = 0.7) +
  geom_vline(xintercept = 20, color = "red", linetype = "dashed", size = 1) +
  geom_vline(xintercept = 30, color = "darkred", linetype = "dashed", size = 1) +
  labs(title = "CADD Score Distribution",
       subtitle = "Red lines: CADD=20 and CADD=30 thresholds",
       x = "CADD PHRED Score", y = "Number of Variants") +
  theme_minimal()

ggsave("variant_statistics/cadd_distribution.png", p5, width = 10, height = 6, dpi = 300)

# ========== CADD vs CONSEQUENCE TYPE ==========

# Box plot of CADD scores by consequence type (top 10 most frequent)
top_consequences <- consequence_counts$Consequence_VEP[1:10]
cadd_by_consequence <- data %>%
  filter(Consequence_VEP %in% top_consequences, !is.na(PHRED))

p6 <- ggplot(cadd_by_consequence, aes(x = reorder(Consequence_VEP, PHRED, median), 
                                      y = PHRED)) +
  geom_boxplot(fill = "lightblue", alpha = 0.7) +
  geom_hline(yintercept = 20, color = "red", linetype = "dashed") +
  coord_flip() +
  labs(title = "CADD Score Distribution by Consequence Type",
       subtitle = "Red line: CADD=20 threshold",
       x = "Consequence Type", y = "CADD PHRED Score") +
  theme_minimal() +
  theme(axis.text.y = element_text(size = 8))

ggsave("variant_statistics/cadd_by_consequence.png", p6, width = 12, height = 8, dpi = 300)

# ========== COMBINED SUMMARY PLOT ==========

# Create a combined summary plot
p_combined <- grid.arrange(p1, p2, p3, p4, ncol = 2)
ggsave("variant_statistics/combined_summary.png", p_combined, width = 16, height = 12, dpi = 300)

# ========== PRINT SUMMARY TO CONSOLE ==========

cat("=== VARIANT STATISTICS SUMMARY ===\n")
print(summary_stats)

cat("\n=== TOP 10 GENES WITH HIGH CADD VARIANTS ===\n")
print(high_cadd_genes %>% head(10))

cat("\n=== TOP 10 CONSEQUENCE TYPES ===\n")
print(consequence_counts %>% head(10))

cat("\nAll statistics and plots saved to 'variant_statistics/' directory\n")