# Variant Explorer — Docker Setup Guide

The app runs inside a Docker container, so you do not need to install R or any
R packages. The only requirement is **Docker Desktop**.

---

## 1. Install Docker Desktop

| Platform | Link |
|---|---|
| Windows | https://www.docker.com/products/docker-desktop |
| macOS   | https://www.docker.com/products/docker-desktop |
| Linux   | https://docs.docker.com/engine/install/ |

After installing, open Docker Desktop and make sure it shows **"Engine running"**
in the bottom-left corner before continuing.

> **Windows note:** During installation Docker may ask you to enable WSL 2.
> Accept this — it is required and safe.

---

## 2. Get the app files

If you received a zip file, unzip it to a folder on your computer, e.g.:

```
C:\Users\yourname\Variant_Explorer\
```

Or clone from GitHub:

```bash
git clone https://github.com/anakolicheski/Variant_Explorer
cd Variant_Explorer
```

Your folder should contain at minimum:

```
Dockerfile
docker-compose.yml
app_v**.R
variant_upload_module.R
lolliplot_module.R
renv.lock
start.bat          ← Windows
start.sh           ← Mac / Linux
```

---

## 3. Add your database files

Place your data files inside the app folder before starting:

```
annotations/
    annotations_fordb.tsv    ← your VEP-annotated variant database

New_genotypes/
    SAMPLE001_geno.tsv       ← one file per sample ## For a first setup, you can use the Variant Upload tab to generate these files 
    SAMPLE002_geno.tsv
    ...

Phenotypes.xlsx              ← optional
cram_paths.xlsx              ← optional
```

> **Important:** Your data never leaves your computer. The annotations and
> genotype files are read directly from your local folders

---

## 4. First-time build

This step downloads and installs all R packages inside the container.
**It only happens once** and takes 10–30 minutes depending on your internet speed.
Subsequent starts take under 30 seconds.

Open a terminal in the app folder and run:

```bash
docker compose build
```

You will see a lot of package installation output — this is normal.
Wait until you see `=> exporting to image` at the end.

---

## 5. Start the app

### Windows
Double-click **`start.bat`**

### Mac / Linux
```bash
chmod +x start.sh   # first time only
./start.sh
```

### Or manually from any terminal
```bash
docker compose up
```

The app opens automatically in your browser at **http://localhost:3838**

---

## 6. Stop the app

### Windows
Close the `start.bat` window, or run:
```cmd
docker compose down
```

### Mac / Linux
Press `Ctrl+C` in the terminal, or run:
```bash
docker compose down
```

---

## Everyday use

After the first build, starting the app is just:

1. Open Docker Desktop (if not already running)
2. Double-click `start.bat` (Windows) or run `./start.sh` (Mac/Linux)
3. Browser opens automatically

---

## Updating the app

When a new version of the app is released:

1. Replace the `.R` files in your folder with the new versions
2. If `renv.lock` changed, rebuild the image:
   ```bash
   docker compose build
   ```
3. Start normally

Your database files and column layouts are untouched by updates.

---

## Troubleshooting

**"Docker is not running" error**
Open Docker Desktop and wait for the engine to start (green indicator).

**Browser shows "This site can't be reached"**
The app is still starting. Wait 30 seconds and refresh.

**App starts but shows no variants**
Check that `annotations/annotations_fordb.tsv` exists in the app folder.

**Port 3838 already in use**
Edit `docker-compose.yml` and change `"3838:3838"` to e.g. `"3839:3838"`,
then access the app at `http://localhost:3839`.

**Out of memory errors with large datasets**
Uncomment the `mem_limit: 8g` line in `docker-compose.yml` and adjust to
match your available RAM.

**"Permission denied" on start.sh (Mac/Linux)**
```bash
chmod +x start.sh
```

**Full reset (if something is broken)**
```bash
docker compose down
docker rmi cooper-lab-variant-db:1.0.1
docker compose build
```
This removes and rebuilds the image from scratch. Your data is unaffected.

---

## What is Docker?

Docker packages the app and all its dependencies into a self-contained unit
called a *container*. Think of it like a mini computer inside your computer
that has exactly the right version of R and every package pre-installed.
Your data files live outside the container on your normal file system, so
they are always accessible and are not affected by starting or stopping the app.
