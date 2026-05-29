# Fresh Database Setup Guide

## Starting from Scratch (No Existing Data)

If you want to start a completely new variant database without any pre-existing annotation, genotype and phenotype files, follow this guide.

## Prerequisites

1. R (version 4.0 or higher)
2. Required R packages:
   ```r
   install.packages(c("shiny", "shinythemes", "tidyverse", "readxl", 
                     "DT", "jsonlite", "httr", "purrr", "dplyr", 
                     "biomaRt", "trackViewer", "GenomicRanges", 
                     "writexl", "stringr", "readr", "bslib", "shinyWidgets"))
   ```

## Step 1: Initial Setup

### Option A: Automated Setup (Recommended)

Run the setup script to create all necessary files and directories:

```r
source("setup_fresh_database.R")
```

This will:
- Create `annotations/` directory
- Create `New_genotypes/` directory
- Create empty template files (Phenotypes.xlsx, cram_paths.xlsx, candidates.csv)
- Verify all required module files exist

### Option B: Manual Setup

1. **Create directories:**
   ```r
   dir.create("annotations", recursive = TRUE)
   dir.create("New_genotypes", recursive = TRUE)
   ```

2. **Create Phenotypes.xlsx:**
   ```r
   library(writexl)
   pheno <- tibble(
     Patient = character(),
     Term_1 = character(),
     Term_2 = character(),
     Term_3 = character(),
     Term_4 = character(),
     Term_5 = character()
   )
   write_xlsx(pheno, "Phenotypes.xlsx")
   ```
**Note! If you create the xlsx Phenotype files using excel, make sure there are no spaces or invisible characters on column names such as Term_1 ,Term_2, etc.**

3. **Create cram_paths.xlsx:**
   ```r
   crams <- tibble(
     Patient = character(),
     CRAM_path = character(),
     BAM_path = character(),
     Reference = character()
   )
   write_xlsx(crams, "cram_paths.xlsx")
   ```

4. **Create candidates.csv:**
   ```r
   candidates <- tibble(
     GeneName = character(),
     CHROM = character(),
     Pos = numeric(),
     Ref = character(),
     Alt = character(),
     Consequence = character(),
     Notes = character()
   )
   write_csv(candidates, "candidates.csv")
   ```

**Note! When creating the xlsx Phenotype files, make sure there are no spaces or invisible characters on column names such as Term_1 ,Term_2, etc.**

## Step 2: File Structure

After setup, your directory should look like this:

```
your_project/
├── annotations/              # Empty - will store master variant file
├── New_genotypes/            # Empty - will store genotype files
├── Phenotypes.xlsx          # Empty template
├── cram_paths.xlsx          # Empty template
├── candidates.csv           # Empty template
├── variant_upload_module.R  # Upload module
├── lolliplot_module.R       # Lollipop plot module
└── app_v....R            # Main Shiny app
```

## Step 3: Launch the App

```r
library(shiny)
runApp("app_v....R")
```

The app will start with:
- **0 variants** loaded
- **0 samples** loaded
- Empty phenotype table
- Empty alignment paths table

This is expected! You'll populate it through uploads.

## Step 4: Upload Your First Sample

1. **Navigate to "Variant Upload" tab**

2. **Upload variant file:**
   - Click "Upload annotated variant TSV/CSV"
   - Select your annotated variant file
   - Enter sample name (e.g., "Family_001")

3. **Follow the workflow:**
   - **Step 2:** Map columns (CHR, POS, REF, ALT) - auto-detection will suggest columns
   - **Step 3:** Review the generated variant IDs
   - **Step 4:** Select annotation and genotype columns
   - **Step 5:** Click "Process & Save Files"

4. **Refresh the data:**
   - Click "Refresh Data After Upload" button
   - You should see a confirmation with variant/sample count

5. **View your data:**
   - Navigate to "Genetic Variants" tab
   - Your variants should now appear!

## Expected First Upload Results

After uploading your first sample:

```
annotations/
└── annotations_fordb.tsv     # Created with all variants from Sample 1

New_genotypes/
└── Family_001_geno.tsv       # Created with genotypes for Family_001
```

**Main app will show:**
- Variants in "Genetic Variants" tab
- Sample "Family_001" in patient selector
- Variants can be filtered and analyzed

## Step 5: Upload Additional Samples

For each additional sample:

1. Go to "Variant Upload" tab
2. Upload new variant file with different sample name
3. Follow same workflow
4. Click "Refresh Data After Upload"

**What happens:**
- New variants are **appended** to `annotations/annotations_fordb.tsv`
- Duplicate variants are merged (keeping most severe consequence)
- New genotype file created: `New_genotypes/{SampleName}_geno.tsv`
- Patient selector updates with new sample

## Populating Phenotype Data

After uploading samples, you can add phenotype information:

1. Open `Phenotypes.xlsx` in Excel or R
2. Add rows for each patient:
   ```
   Patient    | Term_1              | Term_2            | Term_3
   -----------|---------------------|-------------------|--------
   Family_001 | Immunodeficiency    | Recurrent infections | 
   Family_002 | Autoinflammation    | Periodic fever    |
   ```
3. Save the file
4. Restart the app or refresh
5. Phenotypes will appear in the "Phenotypes" tab

## Populating Alignment Paths

If you have CRAM/BAM files:

1. Open `cram_paths.xlsx`
2. Add file paths:
   ```
   Patient    | CRAM_path                          | Reference
   -----------|------------------------------------|-------------
   Family_001 | /path/to/family001.cram           | GRCh38
   Family_002 | /path/to/family002.cram           | GRCh38
   ```
3. Save and restart app
4. Paths will appear in "Alignment paths" tab

## Troubleshooting

### Error: "File does not exist"
- **Solution:** This is normal for a fresh database! The app is designed to start with no data.

### No variants showing after upload
- **Solution:** Click "Refresh Data After Upload" button in the Variant Upload tab

### Patient selector is empty
- **Solution:** Upload at least one sample, then click "Refresh Data After Upload"

### Upload fails
- **Check:** 
  - File has CHR, POS, REF, ALT columns (or similar)
  - File is tab-delimited (.tsv) or comma-delimited (.csv)
  - Sample name is provided

## Key Differences from Pre-Loaded Database

| Feature | Fresh Database | Pre-Loaded Database |
|---------|----------------|---------------------|
| Initial variants | 0 | From existing annotations_fordb_4.tsv |
| Initial samples | 0 | From existing New_genotypes/*.tsv files |
| Annotation file | Created on first upload | Already exists |
| Genotype files | Created per upload | Already exist |
| Phenotype data | Empty template | Pre-populated |
| Setup required | Yes (directories + templates) | No |

## Workflow Summary

```
Fresh Setup → Launch App (0 variants) → Upload Sample 1 → Refresh Data → 
View Variants → Upload Sample 2 → Refresh Data → More variants! → 
Add Phenotypes → Analyze!
```

## File Growth Over Time

As you add samples, your database grows:

**After Sample 1:**
```
annotations/annotations_fordb.tsv:  15,000 variants
New_genotypes/Family_001_geno.tsv:  15,000 variants
```

**After Sample 2:**
```
annotations/annotations_fordb.tsv:  28,500 variants (some overlap removed)
New_genotypes/Family_001_geno.tsv:  15,000 variants
New_genotypes/Family_002_geno.tsv:  14,800 variants
```

**After Sample 3:**
```
annotations/annotations_fordb.tsv:  41,200 variants
New_genotypes/Family_001_geno.tsv:  15,000 variants
New_genotypes/Family_002_geno.tsv:  14,800 variants
New_genotypes/Family_003_geno.tsv:  13,900 variants
```

The annotation file grows as unique variants are added, while each sample maintains its own genotype file.

## Best Practices

1. **Consistent naming:** Use clear sample names (Family_001, Patient_ABC, etc.)
2. **Backup regularly:** Keep copies of annotations/ and New_genotypes/ directories
3. **Document uploads:** Keep a log of which samples were uploaded when
4. **Update phenotypes:** Add phenotype data as you learn more about patients
5. **Clean data:** Use consistent consequence annotations in your input files

## Next Steps

Once you have data uploaded:
- Explore the "Genetic Variants" tab for filtering and analysis
- Use "Joined Patients Table" to compare variants across families
- Use "Common Genes by Patient" to find shared genes
- Create lollipop plots for genes of interest
- Store interesting variants in "Candidate Variants"

Your database will grow with each upload and become a valuable resource for variant analysis!
