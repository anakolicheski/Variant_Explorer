# Setup Guide: First Launch and Loading Your Own Data

This guide takes you from nothing installed to the Variant Explorer running with your own data. No programming experience is needed, and you do **not** need to install R.

**What you'll do**

1. [Check what you need](#1-what-you-need)
2. [Install Docker Desktop](#2-install-docker-desktop)
3. [Download the app](#3-download-the-app)
4. [Start the app with the demo data](#4-start-the-app-with-the-demo-data)
5. [Stop the app](#5-stop-the-app)
6. [Replace the demo data with your own](#6-replace-the-demo-data-with-your-own)
7. [Where your data and saved work live](#7-where-your-data-and-saved-work-live)
8. [Updating to a new version](#8-updating-to-a-new-version)
9. [Troubleshooting](#9-troubleshooting)

Appendix: [Running in RStudio instead of Docker](#appendix-running-in-rstudio-instead-of-docker)

---

## 1. What you need

- A computer running **Windows 10 or 11** or a recent **macOS**
- **8 GB of RAM** or more
- About **10 GB of free disk space**
- An **internet connection** for the first start (the app downloads its components once)
- **Administrator rights** to install Docker Desktop (ask your IT support if you don't have them)

### What is Docker, and why do I need it?

The app is written in R and uses many R packages. Instead of asking you to install R and all of those packages, the app runs inside a **container**: a small, self-contained environment that already has everything set up. **Docker Desktop** is the program that runs containers. You install it once, and the start script does the rest.

---

## 2. Install Docker Desktop

### Windows

1. Go to <https://www.docker.com/products/docker-desktop/> and click **Download for Windows**.
2. Run the installer and keep the default options, including **Use WSL 2**.
3. Restart your computer if asked.
4. Open **Docker Desktop** from the Start menu. Accept the terms. You can skip signing in.
5. Wait until Docker Desktop says it is **running** (the whale icon in the taskbar stops animating).

> If Docker Desktop asks you to install or update **WSL**, follow its instructions and restart. This is a normal one-time step.

### Mac

1. Check your chip: **Apple menu → About This Mac**. It says either **Apple M1/M2/M3/M4** (Apple Silicon) or **Intel**.
2. Go to <https://www.docker.com/products/docker-desktop/> and download the version for your chip.
3. Open the downloaded `.dmg` file and drag **Docker** into **Applications**.
4. Open **Docker** from Applications. Accept the terms. You can skip signing in.
5. **Apple Silicon (M1–M4) only:** open Docker Desktop **Settings → General** and turn on **"Use Rosetta for x86_64/amd64 emulation on Apple Silicon"**, then click **Apply & restart**.

> **Why the Rosetta step?** The app's base system is built for Intel/AMD processors. Rosetta lets Apple Silicon Macs run it quickly. Without it, the first start is much slower and may fail.

---

## 3. Download the app

1. On this repository's GitHub page, click the green **Code** button, then **Download ZIP**.
2. Find the ZIP file (usually in **Downloads**) and **extract it**:
   - **Windows:** right-click the ZIP → **Extract All…** → **Extract**
   - **Mac:** double-click the ZIP
3. Move the extracted folder somewhere permanent, e.g. **Documents**.

> ⚠️ **Extract the ZIP first.** On Windows you can open a ZIP and see its files without extracting them, but the app will not start from inside a ZIP.

> **OneDrive / iCloud folders:** these work, but make sure the files are actually on your computer. In OneDrive, right-click the folder and choose **Always keep on this device**.

Inside the extracted folder, open the **`app`** folder. That's where you'll work from now on.

---

## 4. Start the app with the demo data

Make sure **Docker Desktop is open and running** first.

### Windows

Double-click **`start.bat`** in the `app` folder.

> If Windows shows **"Windows protected your PC"**, click **More info → Run anyway**. Windows shows this for any script downloaded from the internet.

### Mac

1. Open **Terminal** (Applications → Utilities → Terminal).
2. Type `cd ` (with a space after it), drag the `app` folder into the Terminal window, and press **Enter**.
3. The first time only, make the scripts runnable:
   ```bash
   chmod +x start.sh
   ```
4. Start the app:
   ```bash
   ./start.sh
   ```

### What happens next

- **The first start takes about 10–20 minutes** (longer on Apple Silicon Macs) while Docker downloads and builds everything. You'll see a lot of text scrolling by; that's normal.
- When it's ready, your browser opens **<http://localhost:3838>** with the demo data loaded.
- **Later starts take only seconds.**

The window that ran the script shows **"App is running at http://localhost:3838"** and the data folder in use. Keep it open while you use the app.

Now explore! The app's **How to Use** tab explains every tab.

---

## 5. Stop the app

- **Windows:** click the window that ran `start.bat` and **press any key**.
- **Mac:** in Terminal, **press Enter** (or Ctrl+C).

If you closed that window without stopping, the app keeps running in the background. Running the start script again replaces it.

---

## 6. Replace the demo data with your own

### Step 1: Stop the app

See [section 5](#5-stop-the-app).

### Step 2: Delete the demo files

In the `app` folder, delete:

| Folder | Delete |
|---|---|
| `annotations` | `annotations_fordb.tsv` |
| `New_genotypes` | every file ending in `_geno.tsv` |
| `app_state` | `Phenotypes.xlsx`, `cram_paths.xlsx` and `candidates.csv`, if present |
| `app` itself | `Phenotypes.xlsx` and `cram_paths.xlsx`, if present |

Keep the folders themselves; only delete the files inside them.

> **Why delete them before uploading?** New uploads are **added** to the existing annotation file. If the demo file is still there, the demo variants get mixed in with yours.
>
> **Why also delete them from the `app` folder?** A phenotype file found there is copied into `app_state` at the next start. Leaving it means the demo phenotypes come back.

### Step 3: Start the app again

The app opens with empty tables. That's expected.

### Step 4: Upload your samples

Go to the **Variant Upload** tab and upload **one sample or family at a time**:

1. **Choose your file** and type a **Sample/Family Name** (e.g. `Family_001`). This name identifies the sample everywhere in the app.
2. Check that **CHR, POS, REF and ALT** were detected correctly. Fix them from the dropdowns if not.
3. Under **Annotation Columns**, tick the variant information to keep (gene, consequence, scores, frequencies). Everything is ticked by default.
4. Under **Genotype Columns**, tick the columns that belong to *this sample*, e.g. zygosity, GT, read depth.
5. Click **Process & Save Files**.
6. Repeat for each sample.
7. When you're done, click **Refresh Data After Upload**.

#### What your variant file needs

A tab-separated (`.tsv`/`.txt`) or comma-separated (`.csv`) file with a header row and one variant per row, such as VEP output in tab format.

| Needed for | Column (any of these names) |
|---|---|
| **Required** | chromosome (`CHROM`, `CHR`, `#CHROM`), position (`POS`), reference allele (`REF`), alternate allele (`ALT`) |
| Gene name | `SYMBOL` or `Gene` |
| Consequence filter and charts | `Consequence` |
| CADD filter | `CADD_PHRED`, `PHRED` or `CADD Score` |
| gnomAD filter | e.g. `gnomADe_AF`, `gnomADg_AF`, `MAX_AF`, or another column ending in `_AF` |
| Lollipop plot | `Amino_acids` and `Protein_position` |
| Colored genotypes | a `Zygosity` column (`Het`, `Hom Alt`, `Hom Ref`) |

If a variant lists several consequences (e.g. `missense_variant&splice_region_variant`), the app keeps the most severe one.

### Step 5: Add phenotypes (optional but recommended)

Phenotypes let you filter samples by clinical features.

**Option A: in the app.** On the **Phenotypes** tab, click **Add Row**, double-click the cells to fill them in, then click **Save Changes**.

**Option B: from Excel.** Create `Phenotypes.xlsx` with these columns and put it in the `app_state` folder, then restart the app:

| Patient | Term_1 | Term_2 | Term_3 | Term_4 | Term_5 |
|---|---|---|---|---|---|
| Family_001 | Recurrent infections | Eczema | | | |

`Patient` must match the **Sample/Family Name** used at upload exactly, including capitals.

### Step 6: Add alignment file locations (optional)

To list where each sample's CRAM file is stored, create `cram_paths.xlsx` with columns `Patient` and `CRAM_path`, put it in `app_state`, and restart the app.

### Gene lists

To focus on a gene panel, make a CSV file with a column named `Gene` (one gene symbol per row) and load it with **Upload Gene List** in the sidebar. Nothing needs to be saved in a folder.

---

## 7. Where your data and saved work live

Everything stays in the `app` folder on your computer:

| Folder | Contents |
|---|---|
| `annotations/` | `annotations_fordb.tsv`: all variants and their annotations |
| `New_genotypes/` | one `<Sample>_geno.tsv` per sample |
| `app_state/` | saved candidate list, column layouts, phenotype table, protein domain cache |

**Back up these three folders** to keep your work.

> 🔒 **Never upload these folders to GitHub or any public site.** They contain your patients' data. If you use Git, make sure `annotations/`, `New_genotypes/` and `app_state/` are never committed.

---

## 8. Updating to a new version

1. **Stop the app.**
2. **Download the new version** as a ZIP and extract it (see [section 3](#3-download-the-app)).
3. **Copy your data** from the old `app` folder into the new one, replacing the demo files: the `annotations`, `New_genotypes` and `app_state` folders.
4. **Start the app** from the new folder. The first start after an update rebuilds the app, which takes a few minutes.

The version number is shown next to the app title.

---

## 9. Troubleshooting

| Problem | What to do |
|---|---|
| **"Docker is not running"** | Open Docker Desktop and wait until it says it's running, then start again. |
| **The window closes immediately, or says `Dockerfile` / `renv.lock` was not found** | Run the start script from inside the `app` folder, and check that the ZIP was extracted (section 3). |
| **"Windows protected your PC"** | Click **More info → Run anyway**. |
| **Mac: "permission denied" when running `./start.sh`** | Run `chmod +x start.sh` once, then `./start.sh` again. |
| **Stuck on "Waiting for app to start…"** | After 5 minutes the script stops and prints the app's log. Copy those lines when asking for help. |
| **The build fails** (e.g. "Still failed to install") | Usually an internet or firewall problem. Check your connection and try again. If it keeps failing, save the full output and ask for help: `docker compose build --progress=plain > build.log 2>&1` |
| **Still seeing demo data** after loading your own | Make sure you deleted all demo files, including any `Phenotypes.xlsx` in the `app` folder (section 6, step 2). Then stop and start the app. |
| **Tables are empty** | Check the file names: `annotations/annotations_fordb.tsv` and `New_genotypes/<Sample>_geno.tsv`. Also check the sidebar filters aren't excluding everything. |
| **A new sample doesn't appear** | Click **Refresh Data After Upload**, or stop and start the app. |
| **The first start on a Mac is very slow** | Normal on Apple Silicon. Make sure the Rosetta setting is on (section 2). Later starts are fast. |
| **Port 3838 is already in use** | Another program is using that port. Close it, or restart your computer and try again. |

---

## Appendix: Running in RStudio instead of Docker

Docker is the recommended way to run the app. If you already work in R, you can also run it directly:

1. Install **R 4.3** and **RStudio**.
2. Open RStudio, set the working directory to the `app` folder (**Session → Set Working Directory → Choose Directory…**).
3. Install the exact package versions the app uses (once; this can take a while):
   ```r
   install.packages("renv")
   renv::restore()
   ```
4. Start the app:
   ```r
   shiny::runApp("app_v1.0.5.R")
   ```

The app reads and writes the same `annotations/`, `New_genotypes/` and `app_state/` folders as the Docker version.
