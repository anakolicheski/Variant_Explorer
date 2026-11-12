# Cooper Lab Variant Explorer

An interactive app for exploring whole-exome sequencing variants across patients and families, built for rare disease research. Filter variants by consequence, CADD score and population frequency, compare samples and phenotypes, build a shortlist of candidate variants, and view variants on protein domain maps.

It runs on your own computer: your variant data stays on your machine.

## Features

- **Variant browsing and filtering**: consequence type, CADD PHRED score, gnomAD allele frequency, gene lists, and per-column filters
- **Genotypes across samples**, with color-coded zygosity
- **Phenotype table** linked to samples, with filtering by phenotype term
- **Common variants and genes** shared across selected samples or families
- **Candidate variant list** with your own notes columns, saved between sessions
- **Lollipop plots** of variants along the protein with annotated domains
- **Upload tab** for adding new annotated samples (e.g. VEP output)

## Quick start

You need [Docker Desktop](https://www.docker.com/products/docker-desktop/). You do **not** need to install R.

1. Install and open Docker Desktop.
2. Download this repository (**Code → Download ZIP**) and extract it.
3. Open the `app` folder and start the app:
   - **Windows:** double-click `start.bat`
   - **Mac / Linux:** in Terminal, run `./start.sh`
4. Your browser opens at <http://localhost:3838> with demo data loaded.

The first start takes a while (about 10–20 minutes) while the app is built. Later starts take seconds.

**New to this?** Follow the step-by-step **[Setup Guide](SETUP_GUIDE.md)**. It covers installing Docker, the first launch, and replacing the demo data with your own.

## Demo data

The app ships with demo data from the [Harvard Personal Genome Project](https://pgp.med.harvard.edu/), so you can try every feature straight away. The [Setup Guide](SETUP_GUIDE.md#6-replace-the-demo-data-with-your-own) explains how to remove it and load your own samples.

## Using the app

Each tab is explained in the app's **How to Use** tab.

## Data privacy

- Variant, genotype and phenotype files are read from folders on your computer and are never uploaded anywhere.
- The only outside connection: the Lollipop Plot looks up protein domains online using the **gene symbol** only.
- Your data folders (`annotations/`, `New_genotypes/`, `app_state/`) must never be committed to GitHub. `app_state/` is already in `.gitignore`.

## Repository layout

```
app/
├── start.bat, start.sh       start the app (Windows / Mac & Linux)
├── Dockerfile                how the app is built
├── docker-compose.yml        how the app is run
├── renv.lock                 exact R package versions
├── app_v1.0.5.R              the app
├── *_module.R                upload and lollipop plot modules
├── APP_GUIDE.md              in-app "How to Use" text
├── annotations/              variant annotations (demo data)
├── New_genotypes/            genotypes per sample (demo data)
└── app_state/                created on first start: saved work
```
