# How to Use the Variant Explorer

Quick reference for each tab. For installation and loading your own data, see the setup guide on GitHub.

**General tips**

- **Hover** over a truncated cell to see its full value.
- **Filter boxes** above each column search that column. Numeric columns show a range filter.
- **⇅ Reorder Columns** button above each table: drag column names to reorder them, click × to hide one, and type a name to bring it back.
- **Double-click** a cell in an editable table (Phenotypes, Candidate Variants) to edit it. Press Enter to confirm.
- Zygosity colors: <span style="background:yellow">&nbsp;Het&nbsp;</span> <span style="background:tomato">&nbsp;Hom Alt&nbsp;</span> <span style="background:lightgreen">&nbsp;Hom Ref&nbsp;</span>
- Edits are kept only after you click **Save Changes**.

---

## Sidebar filters

The sidebar changes with the tab. Genetic Variants, Common Variants and Common Genes each remember their own filter settings.

- **Upload Gene List**: a CSV file with a column named `Gene`. Only variants in those genes are shown.
- **Filter by Variant Type**: tick the consequence types to include.
- **CADD PHRED Score**: keep variants within the score range. Scores above 20 are generally considered deleterious.
- **gnomAD Population Frequency**: choose the frequency column, then set the maximum allele frequency. Variants absent from gnomAD are kept unless you tick **Show ONLY novel variants**.
- **Filter by Phenotype Term** / **Filter by Sample/Family** (Common Variants, Common Genes): choosing a phenotype term selects every sample with that term. You can also pick samples directly.

## Genetic Variants

All variants in the database after the sidebar filters.

- The **pie chart** shows the most common consequence types. The **histogram** shows CADD PHRED scores.
- **Click a row** in the variant table to list every sample that carries that variant, with its main phenotype, in the table below it.
- **Variants + Genotypes** shows the filtered variants with each sample's genotype. It also follows any column filters typed in the variant table.
- **Save Layout for Next Session** keeps your column order and hidden columns for next time. **Reset All Layouts** restores the defaults.
- Use the download buttons to export the current tables as CSV.

## Phenotypes

One row per sample: `Patient` (must match the sample name used at upload) and up to five phenotype terms (`Term_1` to `Term_5`).

- **Add Row** to add a sample, double-click cells to fill it in, then **Save Changes**.
- Select a row and click **Delete Selected Row** to remove it.

## Common Variants

Compare the samples selected in the sidebar.

- **Joined Table**: every variant found in any selected sample.
- **Variants Shared by Selected Samples/Families**: only variants called in *all* selected samples.

## Common Genes by Patient Table

Genes carrying variants across the selected samples. The bar chart shows how many selected samples have a variant in each gene. Set how many genes to show with **Top N genes**.

## Candidate Variants

Your shortlist of variants for review.

1. Select a row in a variant table on another tab.
2. Come back here and click the matching **Add from…** button.
3. Add your own columns (e.g. *Segregation*, *Sanger confirmed*) with **Add custom column**, then double-click cells to fill them in.
4. Click **Save Changes**. The list is kept for your next session.

## Lollipop Plot

Pick a gene to see its variants plotted along the protein, colored by consequence, with protein domains drawn below. The table under the plot lists each variant with the samples carrying it and their phenotypes. Domain information is fetched online the first time a gene is viewed (only the gene symbol is sent), then stored for later.

Use **Download PNG** (300 dpi image) or **Download PDF** (sharp at any size, best for figures) to save the plot. Screenshot tools can capture the plot while it is redrawing, which makes it look faded.

## Alignment paths

Lists where each sample's alignment file (CRAM) is stored, from `cram_paths.xlsx` (columns `Patient` and `CRAM_path`). Optional.

## Variant Upload

Add one sample or family at a time from an annotated variant file (TSV or CSV).

1. Choose the file and enter a **Sample/Family Name**. Use the same name in the Phenotypes table.
2. Check that CHR, POS, REF and ALT were detected correctly.
3. Tick the **annotation columns** to keep (gene, consequence, scores, frequencies) and the **genotype columns** for this sample (e.g. Zygosity, GT, depth).
4. Click **Process & Save Files**.
5. Click **Refresh Data After Upload** to see the new sample in the other tabs.
