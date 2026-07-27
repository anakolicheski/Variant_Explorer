# Getting Started with the Cooper Lab Genetic Variants Explorer

This guide walks you through setting up and running the app from scratch. No prior experience with R or programming is required.

---

## What You Will Need

- A computer running Windows, Mac, or Linux
- **R version 4.0 or higher**
- Your annotated variant files (TSV format) — see [Preparing Your Variant Files](#preparing-your-variant-files) below if you are starting from VCF files
- About 20–30 minutes for a first-time setup

---

## Step 1 — Download the App

1. Go to the releases page of this repository:
   `https://github.com/your-org/cooper-lab-variants/releases`
2. Under the latest release, click **Source code (zip)** to download the app
3. Once downloaded, **unzip** the file — on Windows right-click and choose "Extract All"; on Mac double-click the zip file
4. Move the unzipped folder somewhere easy to find, like your Desktop or Documents folder
5. Rename it something simple like `variants-app`

Your folder should look like this when you open it:

```
variants-app/
├── app/
├── test_data/
├── preprocessing/
└── README.md
```

---

## Step 2 — Install R and RStudio

You need two free programs: **R** (the programming language) and **RStudio** (a user-friendly interface for running R). Think of R as the engine and RStudio as the dashboard.

1. Download and install R from [cran.r-project.org](https://cran.r-project.org)
   - Windows: click "Download R for Windows" → "base" → "Download R x.x.x for Windows"
   - Mac: click "Download R for macOS" and choose the version for your chip (Apple Silicon or Intel)
2. Download and install RStudio from [posit.co/download/rstudio-desktop](https://posit.co/download/rstudio-desktop)
   - Choose the free "RStudio Desktop" version
3. Open **RStudio** (not R directly — always use RStudio)

---

## Step 3 — Install the Required R Packages

Packages are add-ons that give R extra functionality. You only need to do this once.

Most of the required packages come from CRAN, R's standard package repository. In RStudio, find the **Console** panel (bottom left, shows a `>` prompt) and paste in the following, then press Enter:

```r
install.packages(c(
  "shiny", "shinythemes", "bslib", "shinyWidgets", "tidyverse",
  "readxl", "writexl", "DT", "jsonlite", "httr", "purrr",
  "dplyr", "readr", "stringr"
))
```

Wait for that to finish (it may take a few minutes). A few remaining packages come from **Bioconductor**, a separate repository used for genomics-specific tools, and need to be installed a different way:

```r
if (!require("BiocManager")) install.packages("BiocManager")
BiocManager::install(c("biomaRt", "trackViewer", "GenomicRanges"))
```

If R asks you "Do you want to install from sources the package which needs compilation?" type `n` and press Enter.

---

## Step 4 — Set Up Your App Folder

Inside your `variants-app/app/` folder, create the following two folders manually (right-click → New Folder):

- `annotations`
- `New_genotypes`

Your `app/` folder should now look like this:

```
app/
├── annotations/          ← empty for now, will be filled by the app
├── New_genotypes/        ← empty for now, will be filled by the app
├── app.R
├── lolliplot_module.R
├── variant_upload_module.R
└── FRESH_DATABASE_SETUP_GUIDE.md
```

You can optionally also add:

- `Phenotypes.xlsx` — a spreadsheet with columns `Patient`, `Term_1`, `Term_2` etc. for storing patient phenotype information. If this file is absent the app will create an empty phenotype table automatically.
- `cram_paths.xlsx` — a spreadsheet with columns `Patient` and `CRAM_path` if you want to store alignment file paths. Optional.

---

## Step 5 — Try the App with the Test Data

Before loading your own data, we recommend trying the included test data to make sure everything is working.

Copy the test files into the right locations:

| Copy this file | To this location |
|---|---|
| `test_data/example_variants.tsv` | `app/annotations/annotations_fordb.tsv` |
| `test_data/example_genotypes_geno.tsv` | `app/New_genotypes/` |
| `test_data/Phenotypes.xlsx` | `app/` |
| `test_data/cram_paths.xlsx` | `app/` |

Then launch the app (see Step 6 below).

---

## Step 6 — Launch the App

1. In RStudio, go to **File → Open File**
2. Navigate to your `variants-app/app/` folder and open `app.R`
3. In the top right corner of the script editor, click the **Run App** button (green play button)
4. The app will open in a new window or in your browser

> **Tip:** If you see a "Run App" dropdown arrow, choose **Run External** to open the app in your browser, which gives more space to work with.

---

## Step 7 — Load Your Own Variant Data

Once the app is running, go to the **Variant Upload** tab.

**Step 7a — Upload your file**
- Click **Browse** and select your annotated TSV or CSV file
- Enter a name for the sample or family in the **Sample/Family Name** field (e.g. `Family_001`). This name will be used to label genotype columns, so keep it short and without spaces.

**Step 7b — Map your columns**
- The app will auto-detect common column names for chromosome, position, reference allele, and alternate allele
- Check that the dropdowns are correct and adjust if needed
- Select which columns are **annotation columns** (variant-level information like gene name, consequence, CADD score) and which are **genotype columns** (sample-specific information like zygosity or read depth)

**Step 7c — Process and refresh**
- Click **Process & Save Files**
- Go back to the main app and click **Refresh Data After Upload**
- Your variants will now appear in the Genetic Variants tab

Repeat this process for each sample or family you want to add.

---

## Preparing Your Variant Files

If you are starting from raw VCF files, you will need to annotate them before uploading. The recommended pipeline uses **Ensembl VEP** followed by **BCFtools** to convert to TSV.

### What is VEP?

Ensembl VEP (Variant Effect Predictor) takes a VCF file and adds biological annotations to each variant — things like which gene it affects, what the predicted consequence is (missense, frameshift, etc.), population allele frequencies from gnomAD, and pathogenicity scores like CADD.

### Option A — Run VEP online (easiest, no installation required)

For small VCF files (< a few thousand variants):

1. Go to [ensembl.org/Tools/VEP](https://www.ensembl.org/Tools/VEP)
2. Upload your VCF file
3. Under **Plugins**, enable: CADD, PolyPhen, SIFT
4. Under **Frequencies**, enable gnomAD exomes or genomes
5. Run the job and download the results as a VCF

### Option B — Run VEP on the command line (recommended for large files)

Install VEP following the [official instructions](https://www.ensembl.org/info/docs/tools/vep/script/vep_download.html), then run:

```bash
vep \
  --input_file your_variants.vcf \
  --output_file your_variants_annotated.vcf \
  --vcf \
  --cache \
  --assembly GRCh37 \
  --plugin CADD,whole_genome_SNVs.tsv.gz \
  --plugin PolyPhen \
  --af_gnomad \
  --hgvs \
  --symbol \
  --numbers \
  --fields "SYMBOL,Consequence,HGVSc,HGVSp,Amino_acids,Protein_position,CADD_PHRED,gnomAD_AF,PolyPhen,SIFT,Existing_variation,CLIN_SIG"
```

See the `preprocessing/` folder in this repository for the exact commands and plugin versions used to generate the test data files.

### Converting the annotated VCF to TSV

Once you have an annotated VCF, use BCFtools to extract the fields into a TSV:

```bash
bcftools +split-vep your_variants_annotated.vcf \
  -f '%CHROM\t%POS\t%REF\t%ALT\t%CSQ\n' \
  -d \
  -A tab \
  > your_variants.tsv
```

Add a header line matching your field names and the file is ready to upload into the app.

> **Note:** Intronic variants and duplicates can be filtered out before uploading to reduce file size. For large cohorts this makes a significant difference to app performance.

---

## Troubleshooting

**The app won't launch / I see an error about a missing package**
Run `install.packages("packagename")` in the RStudio console, replacing `packagename` with whatever is mentioned in the error.

**My variants aren't showing up after upload**
Make sure you clicked **Refresh Data After Upload** on the Variant Upload tab after processing.

**The Lollipop Plot tab is blank**
This tab requires an internet connection to fetch protein domain data from Ensembl. Check your connection and try selecting a gene from the dropdown.

**I accidentally uploaded the wrong file**
Delete the file from `app/annotations/annotations_fordb.tsv` and/or the relevant file in `app/New_genotypes/`, then restart the app and re-upload.

**Column names weren't detected correctly**
Use the dropdown menus in Step 2 of the upload tab to manually map your columns. The app accepts most common naming conventions but your file may use a different format.

---

## Getting Help

If you encounter an issue not covered here, please open an issue on the GitHub repository and include a description of the error and, if possible, the first few rows of your input file (with any sensitive information removed).
