# Genetic Variant Explorer

A Shiny web application for interactive browsing, filtering, and curation of annotated genetic variant data across multi-sample/family cohorts.

---

## Features

- **Variant browsing** — filter by consequence type, CADD PHRED score, and gene list; live pie chart and PHRED histogram update with filters
- **Multi-sample analysis** — find variants shared across selected patients/families; gene-level table identifies genes with variants in more than one patient
- **Phenotype integration** — filter patients by HPO/phenotype terms; phenotype table is editable in-app
- **Lollipop plots** — gene-level variant visualisation mapped to protein domains fetched live from Ensembl/BioMart
- **Candidate variant curation** — capture variants from any table into a persistent review list with editable notes and custom columns
- **Variant upload** — upload annotated TSV/CSV files, map columns interactively, and append to the shared database without restarting the app
- **Persistent column layouts** — drag to reorder, show/hide columns, and save preferences across sessions

---

## Requirements

R (≥ 4.1) with the following packages:

```r
install.packages(c(
  "shiny", "shinythemes", "tidyverse", "readxl", "writexl",
  "DT", "jsonlite", "httr", "purrr", "dplyr", "readr", "stringr"
))

# Bioconductor packages
if (!require("BiocManager")) install.packages("BiocManager")
BiocManager::install(c("biomaRt", "trackViewer", "GenomicRanges"))
```

---

## Installation

```bash
git clone "link --- still a place holder here"
cd whateverfolder
```

Or download zip file from latest release. See FRESH_DATABASE_SETUP_GUIDE.md under the app subfolder for more guidance.

---

## Directory Structure

```
cooper-lab-variants/
├── app/
│   ├── app.R                        # Main application (versions may vary with release)
│   ├── lolliplot_module.R           # Lollipop plot module
│   ├── variant_upload_module.R      # Variant upload & processing module
│   └── FRESH_DATABASE_SETUP_GUIDE.md
│
└── test_data/
    ├── README.md                    # How to use the test files and data preprocessing
    ├── annotations/
    |   |── annotations_fordb.tsv    # Annotated variants from Harvard PGP public WGS data (pgp.med.harvard.edu); see preprocessing/ for pipeline scripts (without genotype information)
    ├── New_genotypes/           # Example of what your input genotype files for the same variants in annotated variants will look like
    |   |── hu1C1368_geno.tsv
    |       .....
    ├── example_tsvs                 # Example of annotated TSV files. Your own files to be uploaded should look a bit like these. You can also test upload these files
    |   |── hu1C1368.tsv
    |       .....
    ├── Phenotypes.xlsx              # Example phenotype table
    ├── cram_paths.xlsx              # Example CRAM path table
    └── example_gene_list.csv        # Example gene list for filtering (IUIS-IEI list)
```

The following directories and files are created automatically at runtime and are **not** tracked by git:

```
app/annotations/        # Annotation database (generated on first upload)
app/New_genotypes/      # Per-sample genotype files (generated on upload)
app/candidates.csv      # Saved candidate variants
app/col_state.json      # Saved column layout preferences
```

---

## Quick Start

### 1. Fresh setup (no existing data)

```r
setwd("app/")   ## Navigate to the folder where you saved the app files
shiny::runApp()
```

Navigate to the **Variant Upload** tab and follow the steps to upload your first annotated variant file. Click **Refresh Data After Upload** when done. See `FRESH_DATABASE_SETUP_GUIDE.md` (available in the Tutorial tab) for a full walkthrough.

### 2. Using the test data

Copy the test files into the expected locations before launching:

cp test_data/example_annotation/annotations_fordb.tsv  to    app/annotations/annotations_fordb.tsv
cp test_data/example_genotypes/ to app/New_genotypes/
cp test_data/Phenotypes.xlsx    to         app/
cp test_data/cram_paths.xlsx    to         app/
```

Then launch:

```r
setwd("app/")
shiny::runApp()
```

See `test_data/README.md` for a description of each file and what it demonstrates.

---

## Input File Format

The upload module accepts TSV or CSV files with the following required columns (common naming variants are auto-detected):

| Field | Accepted column names |
|---|---|
| Chromosome | `CHROM`, `CHR`, `Chr`, `Seqnames`, `#CHROM` |
| Position | `POS`, `Pos`, `Position`, `Start` |
| Reference allele | `REF`, `Ref`, `Reference` |
| Alternate allele | `ALT`, `Alt`, `Alternate` |

All other columns can be mapped interactively as annotation columns (variant-level) or genotype columns (sample-level). Genotype columns are namespaced per sample as `SampleName.columnname`.

Common VEP/Ensembl output field names (e.g. `SYMBOL`, `Consequence`, `CADD_PHRED`, `CLNSIG`, `Amino_acids`, `Protein_position`) are mapped automatically and are recommended for full app functionality.

---

## Data Persistence

| File | Contents | Updated by |
|---|---|---|
| `annotations/annotations_fordb.tsv` | Shared variant annotation database | Variant Upload module |
| `New_genotypes/<sample>_geno.tsv` | Per-sample genotype calls | Variant Upload module |
| `Phenotypes.xlsx` | Patient phenotype terms | Phenotypes tab → Save Changes |
| `candidates.csv` | Curated candidate variants | Candidate Variants tab → Save Changes |
| `col_state.json` | Column layout preferences | Save Layout button |

---

## Notes

- The Lollipop Plot tab requires an active internet connection to fetch protein domain data from Ensembl. Domains are cached per session; genes with no Pfam records will display a fallback message.
- File paths are relative to the working directory where the app is launched. Always `setwd()` to the `app/` folder before running.
- The app is designed for local or institutional server deployment.

---
