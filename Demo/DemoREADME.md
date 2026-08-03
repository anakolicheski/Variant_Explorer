VCF Processing:

Overview:

As detailed in the methods section, public VCF files were processed to TSV files to demonstrate database functionalities. Per database requirements, users will need to upload a TSV file. Users wishing to upload VCF files should follow the steps to transform data to meet database specifications.

Installation:

Prior installation of Docker images is required for data processing. The following images are needed to run the Bash scripts:

ensemblorg/ensembl-vep (docker pull ensemblorg/ensembl-vep:latest)
biocontainers/bcftools (docker pull biocontainers/bcftools:v1.9-1-deb_cv1)
Reference Files:

Before running the scripts, download the following reference files:

CADD (https://cadd.gs.washington.edu/download) All possible SNVs for GRCh37/hg19 file: whole_genome_SNVs.tsv.gz (https://krishna.gs.washington.edu/download/CADD/v1.7/GRCh37/whole_genome_SNVs.tsv.gz) GRCh37 liftover of gnomAD v4 indels (genomes + exomes): gnomad.genomes-exomes.r4.0.indel.tsv.gz (https://krishna.gs.washington.edu/download/CADD/v1.7/GRCh37/gnomad.genomes-exomes.r4.0.indel.tsv.gz)

gnomAD (https://gnomad.broadinstitute.org/downloads) gnomAD v2.1.1 GRCh37/hg19, all chromosomes: gnomad.genomes.r2.1.1.sites.vcf.bgz (https://storage.googleapis.com/gcp-public-data--gnomad/release/2.1.1/vcf/genomes/gnomad.genomes.r2.1.1.sites.vcf.bgz)

ClinVar (https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh37/) Index of /pub/clinvar/vcf_GRCh37: clinvar.vcf.gz: (https://ftp.ncbi.nlm.nih.gov/pub/clinvar/vcf_GRCh37/clinvar.vcf.gz)

FASTA (https://www.gencodegenes.org/human/release_37lift37.html) Genome sequence, primary assembly (GRCh37):GRCh37.primary_assembly.genome.fa (https://ftp.ebi.ac.uk/pub/databases/gencode/Gencode_human/release_37/GRCh37_mapping/GRCh37.primary_assembly.genome.fa.gz)

Scripts:

The four scripts below transform unannotated VCF files into upload-ready TSV files. The first three files are Bash scripts; the last is an RScript. File paths specified in quotations in each script will need to be updated with user-specific paths.

VEP Annotation: Runs VEP using the ensembl-vep Docker image. Files aligned to GRCh38 will require different reference files. VCF files that are already annotated may skip this step.
VCF to TSV: Converts VCF to TSV format. This step is only required if genotype level inputs (i.e., depth, zygosity) are included in the uploaded dataset.
Intron Filter (optional): Filters out intronic variants. Users can modify this script based on their own filtering criteria.
TSV Reformatting: Final processing steps which removes duplicate variants and creates additional columns (i.e., a numeric consequence severity field).
Citations:

McLaren W, et al. The Ensembl Variant Effect Predictor. Genome Biology 2016;17(1):122. https://doi.org/10.1186/s13059-016-0974-4

Kircher M, et al. A general framework for estimating the relative pathogenicity of human genetic variants. Nature Genetics 2014;46(3):310–315. https://doi.org/10.1038/ng.2892

Danecek P, et al. Twelve years of SAMtools and BCFtools. GigaScience 2021;10(2):giab008. https://doi.org/10.1093/gigascience/giab008
