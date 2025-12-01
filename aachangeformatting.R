#this script adds a column with protein change in the format p.AminoacidproteinPositionAminoacid

df$protein_change <- ifelse(
  !is.na(df$aminoacids) & grepl("/", df$aminoacids),
  paste0("p.", sub("/.*", "", df$aminoacids), df$protPos, sub(".*/", "", df$aminoacids)),
  NA
)


final_annotations$protein_change <- ifelse(
  !is.na(final_annotations$Amino_acids) & grepl("/", final_annotations$Amino_acids), 
  paste0("p.", sub("/.*", "", final_annotations$Amino_acids), final_annotations$Protein_position, 
  sub(".*/", "", final_annotations$Amino_acids)), 
NA
)



final_annotations_final <- final_annotations_filtered_nointron %>% 
  select(ID,Chrom, Pos, Ref, Alt, GeneName, Consequence_CADD, Consequence_VEP, 
         protein_change,PHRED,db_pop_freq_max,db_pop_freq_max_AF,
         gnomADw_AF,gnomADe_AF,gnomADe_Hom,gnomADe_Hemi,Existing_variation,Intron,Exon,Codons,
         cDNApos,CDSpos,protPos,Domain,SIFTcat,PolyPhenCat,clinvar_CLINSIGN,clinvar_PHENOTYPE,HGVSc,HGVSp,best_rank)