#!/usr/local/bin/ Rscript
args = commandArgs(trailingOnly=TRUE)

#check arguments
if (length(args)!=4){stop("Oops.  Need 4 arguments (vcffile, skiprows, sampledb, accessiondb)", call.=FALSE)}

vcffile=args[1]
skipr=args[2]  #count header lines in command line (grep -c "##" final.vcf)
samplefile=args[3]
accessionfile=args[4]

skipc=9  #non sample columns


library(adegenet)
library(stringr)
library(hierfstat)
library(MASS)

#read in vcf, skipping ##header rows and removing other junk
print("read in vcf")
vcf=read.delim(vcffile, sep="\t", header=T, skip=skipr)
loci_names=paste(vcf[,1],"-",vcf[,2], sep="")     #make locus names (chr_bp)
chroms=vcf[,1]
posbp=vcf[,2]
vcf=vcf[c(-skipc:-1)]                             #remove non sample columns
genos=apply(vcf,2,substr,1,3)                     #get just genotypes
genos=t(genos)                                    #transpose 
colnames(genos)=loci_names                        #add locus names
dim(genos)                                        #print number of samples and loci

#add sample metadata
print("read in metadata")
sampleinfo=read.csv(samplefile, header=T)  #read in sample information
samplematches=match(sampleinfo$SampleID, rownames(genos))  #subset for just samples in this analysis
samples=sampleinfo[!is.na(samplematches),][order(na.omit(samplematches)),]

accessioninfo=read.csv(accessionfile, header=T)  #read in accession information
accessionmatches=match(samples$AccessionID, accessioninfo$AccessionID)
samples=cbind(samples,accessioninfo$Latitude[accessionmatches],accessioninfo$Longitude[accessionmatches],
              accessioninfo$PopulationName[accessionmatches])
names(samples)[names(samples)=="accessioninfo$Latitude[accessionmatches]"]="Latitude"
names(samples)[names(samples)=="accessioninfo$Longitude[accessionmatches]"]="Longitude"
names(samples)[names(samples)=="accessioninfo$PopulationName[accessionmatches]"]="PopulationName"
samples$PopulationName=droplevels(samples$PopulationName) #fix annoying extra level with no assignment
dim(samples)

#put in matrix format
print("matrix format")
genos.matrix=genos
genos.matrix[genos.matrix == "./."] <- "NA"
write.csv(genos.matrix, file="genos_matrix.csv", row.names=T, quote=F)

#alt matrix format encoding
#0=homoz alt allele #1=heterozygote #2=homoz ref allele
#genos.matrix[genos.matrix == "./."] <- "NA"
#genos.matrix[genos.matrix == "1/1"] <- "0"
#genos.matrix[genos.matrix == "0/1"] <- "1"
#genos.matrix[genos.matrix == "1/0"] <- "1"
#genos.matrix[genos.matrix == "0/0"] <- "2"

#put in allele count formats for baypass and gdm
print("allele counts for baypass and gdm")
#initilize matrix
afs=matrix(, nrow=dim(genos)[2], ncol=length(levels(samples$PopulationName))*2)
row.names(afs)=loci_names
pops_double=vector(mode="character", length=length(levels(samples$PopulationName))*2)
gdm_abund=matrix(,nrow=length(levels(samples$PopulationName)),ncol=dim(genos)[2]*2+3)
#get population allele frequencies
#loop over populations
for (i in 1:length(levels(samples$PopulationName)))
    {
        print(levels(samples$PopulationName)[i])
        #subset for samples from the population
        samples_pop=subset(samples, PopulationName==levels(samples$PopulationName)[i], 
                                select=c(SampleID))
        print(dim(samples_pop)[1])
        #get genotypes and count alleles at each locus
        genos_pop=genos[row.names(genos) %in% samples_pop[,1],]
        loci=apply(genos_pop,2,paste,collapse="")
        ref_count=str_count(loci,"0")
        alt_count=str_count(loci,"1")
        na_count=str_count(loci,"[.]")

        #sanity check
        if (sum(is.na(match((ref_count+alt_count+na_count),dim(samples_pop)[1]*2)))>0)
            {print("warning--values do not add up for:")
             print(levels(samples$PopulationName)[i])
            }

        #print to afs matrix
        afs[,i*2-1]=ref_count
        afs[,i*2]=alt_count
        pops_double[i*2-1]=paste(levels(samples$PopulationName)[i],"_A",sep="")
        pops_double[i*2]=paste(levels(samples$PopulationName)[i],"_B",sep="")

        #print to gdm format
        sitedata=c(levels(samples$PopulationName)[i],samples$Longitude[i],samples$Latitude[i],ref_count,alt_count)
        gdm_abund[i,]=sitedata
    }

colnames(afs)=pops_double
write.csv(afs, file="pop_alleles_baypass.csv", row.names=T, quote=F)
write.table(gdm_abund, file="pop_alleles_gdm.csv", sep=",", row.names=F, col.names=F, append=F, quote=F)

#fst matrix
print("fst matrix")
#format for input into genid object
#fix so there is no 0 allele
genos.fst=genos
genos.fst[genos.fst == "./."] <- "NA"
genos.fst[genos.fst == "1/1"] <- "2/2"
genos.fst[genos.fst == "0/1"] <- "1/2"
genos.fst[genos.fst == "1/0"] <- "2/1"
genos.fst[genos.fst == "0/0"] <- "1/1"

#convert to genid object
genos.gi <- df2genind(genos.fst,sep="/", missing=NA, pop=samples$PopulationName)
genos.gi

#basic fstats
#fstat(genos.gi, pop=samples$PopulationName)

#by locus fstats
#library(pegas)
#genos.li=as.loci(genos.gi)
#fstats=Fst(genos.li,pop=samples$PopulationName)

#pairwise w&c fst
genos.df=genind2df(genos.gi)
genos.df=as.data.frame(sapply(genos.df[,-1], as.numeric))
genos.df=cbind(samples$PopulationName,genos.df)
fst.mat=pairwise.WCfst(genos.df)
write.csv(fst.mat, file="fst_pop.csv", row.names=T, quote=F)
#pairwise neis
#pairwise.fst(genos.gi, pop=samples$PopulationName)

#EEMS
print("plink for eems")
#plink format encoding
#0=missing #1=ref allele #2=alt allele
genos.plink=genos
genos.plink[genos.plink == "./."] <- "0 0"
genos.plink[genos.plink == "1/1"] <- "2 2"
genos.plink[genos.plink == "0/1"] <- "1 2"
genos.plink[genos.plink == "1/0"] <- "2 1"
genos.plink[genos.plink == "0/0"] <- "1 1"

#check order of samples
sum(rownames(genos.plink)!=samples$SampleID)

#format for plink ped
rownames(genos.plink)=NULL
colnames(genos.plink)=NULL
info.plink=data.frame(rep(0, times=dim(genos)[1]),samples$SampleID,rep(0, times=dim(genos)[1]),
                      rep(0, times=dim(genos)[1]),rep(0, times=dim(genos)[1]),rep(0, times=dim(genos)[1]))
colnames(info.plink)=NULL
plink.ped=cbind(info.plink,genos.plink)
colnames(plink.ped)=NULL
write.matrix(plink.ped, file="plink.ped")

#plink map
plink.map=data.frame(chroms,loci_names,rep(0, times=dim(genos)[2]),posbp)
#plink.map=data.frame(do.call(rbind,strsplit(colnames(genos),"_")), colnames(genos),rep(0, times=dim(genos)[2]))
#plink.map=plink.map[,c("X1","colnames.genos.","rep.0..times...dim.genos..2..","X2")] #order columns
colnames(plink.map)=NULL
write.matrix(plink.map, file="plink.map")

#write long/lat to file
longlat=cbind(samples$Longitude, samples$Latitude)
write.matrix(longlat, file="eems.coord", sep=" ")

#write polygon file
maxlong=max(samples$Longitude)+1
minlong=min(samples$Longitude)-1
maxlat=max(samples$Latitude)+1
minlat=min(samples$Latitude)-1
polyd=c(minlong,minlat,maxlong,minlat,maxlong, maxlat,minlong,maxlat,minlong,minlat)
poly=matrix(polyd, nrow=5, ncol=2, byrow=T, dimnames=NULL)
write.matrix(poly, file="eems.outer", sep=" ")

print("DONE!")
