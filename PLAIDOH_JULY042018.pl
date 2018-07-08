#!/usr/bin/perl

#Built in Modules
use warnings;
use strict;
use Getopt::Long qw(GetOptions);
use Term::ANSIColor;
use Term::ANSIColor 2.00 qw(:pushpop);

#Modules in "Modules" folder downloaded with PLAIDOH
use lib '../Modules';
use List::Util qw(sum);
use List::Util qw(max);
use List::Util qw(min);
use Math::GSL::CDF qw/:all/;
use Math::Round qw(:all);
use Statistics::R;





##################################################################
###################### COMMAND LINE OTIONS ######################
##################################################################

if (@ARGV == 0 ){ die 
                 
"\nUsage: perl $0 [options] <Input tab-delimited bed file with columns: #Chr Start Stop Name Type(lncRNA, antisense_RNA or protein_coding) Sample1_Expression Sample2_Expression etc >
                
                Please Note: Input expression file and all user-generated bed
                files should be sorted using the following command if you wish
                to use any default PLAIDOH input files:
                sort -k1,1 -k2,2n in.bed > in.sorted.bed
                
        OPTIONS
        
        -s filename for Super-enhancer file
           --cellSE Optional selection to pick a specific cell line
                variable from the SE list
           
       -e filename for Enhancer data
           --cellENH Optional selection to pick a specific cell line
                variable from the Enhancer list
       
       -f finename for Nuclear Fraction file
       
       -b filename for Biomart Query file
        
        -c filename for Chip-seq data
           --cellCHIP Optional selection to pick a specific cell line
                variable from the ChipSeq list
        
        -p filename for CHIA-pet data
        
        -r filename for RBP file
           --RBP Optional selection to pick a specific cell line
                variable from the RBP list\n\n";
                    
                    }

my $command = join(" ", @ARGV);


### Setting Default files if no options are chosen by the user 
my $chiapetfile="Default_Files/K562_and_MCF7_POL2RAChIApet.txt";
my $chipfile="Default_Files/ENCODE_ChIPseq_pValues.txt";
my $sefile="Default_Files/SEA_SuperEnhancers.bed";
my $rbpfile="Default_Files/RNABindingProtein_eCLIP_h19.txt";
my $enhancerfile="Default_Files/EnhancerAtlas_Enhancers.bed";
my $nucfracfile="Default_Files/Nuclear_Fraction_GM12878_hg19.txt";
my $biomartfile = "Default_Files/Biomartquery_hg19.txt";
my $cellectSE="NA";
my $cellectENH="NA";
my $cellectCHIP="NA";
my $cellectRBP="NA";



GetOptions("s=s" => \$sefile,
           "p=s" => \$chiapetfile,
           "c=s" => \$chipfile,
           "e=s" => \$enhancerfile,
           "r=s" => \$rbpfile,
           "f=s" => \$nucfracfile,
           "b=s" => \$biomartfile,
           "cellSE=s" => \$cellectSE,
           "cellENH=s" => \$cellectENH,
           "cellCHIP=s" => \$cellectCHIP,
           "RBP=s" => \$cellectRBP) ;



if (not -e "Default_Files/RNABindingProtein_eCLIP_h19.txt") {
    print "\nIt looks like you don't have the Default RBP file yet! Hold on a minute while I make it and then I'll get around to that PLAIDOH command!\n";
    system("cat Default_Files/RBPs/*.txt | sort -k1,1 -k2,2n > Default_Files/RNABindingProtein_eCLIP_h19.txt")
}

if (not -e "Default_Files/ENCODE_ChIPseq_pValues.txt") {
    print "\nIt looks like you don't have the Default  ChIP-seq file yet! Hold on a minute while I make it and then I'll get around to that PLAIDOH command!\n";
    system("cat Default_Files/ChIP_Files/*.txt | sort -k1,1 -k2,2n > Default_Files/ENCODE_ChIPseq_pValues.txt")
}

#ENCODE_ChIPseq_pValues.txt
#die("done!");

###############################################################################################
###################### OPENS THE USER-GENERATED INPUT EXPRESSION FILE ######################
###############################################################################################

my $file = shift(@ARGV);
open(IN, "<$file") or die "Could not open file: $file\n";


##################################################################
###################### POPULATES LOG ############################
##################################################################


my $today = localtime();

open(DAILYLOG, ">>PLAIDOH_RUN_LOG.txt") or die "Could not open: PLAIDOH_RUN_LOG.txt";

print DAILYLOG "\n$0 run $today Using files:
                Input: $file
                SE file: $sefile selecting for: $cellectSE
                Enhancer file: $enhancerfile selecting for: $cellectENH
                ChIP File: $chipfile selecting for: $cellectCHIP
                ChIA-PET file: $chiapetfile
                RBP file: $rbpfile selecting for: $cellectRBP 
                Using command: perl $0 $command\n";

##################################################################
######################### VARIABLES ##############################
##################################################################

## HASHES
my %interact;
my %lncs;
my %pcs;
my %CHIA;
my %Master; 
my %limMaster;
my %alllncs;
my %intragenic;
my %check;
my %TADS;
my %CHIP;
my %NEAR;
my %GO;
my %subcell;
my %adjustp;
my %adjustedp;
my %strand;
my %NEAR2;
my %RBP;

## ARRAYS
my @cors;
my @prot;
my @lnc;
my @Lexp;
my @Pexp;
my @testadjust;

#STRINGS
my $header = 0;
my $lchr;
my $lstart;
my $lstop;
my $pchr;
my $pstart;
my $pstop;
my $laverage;
my $paverage;
my $lname;
my $pname;
my $limiter;
my $yes=0;
my ($M, $N);
my $numsamp;
my $indcount=0;
my $yes2;
my $pearson;
my $pearsont;
my $spearman;
my $spearmant;
my $pearsonp;
my $spearmanp;
my $upplus;
my $downplus;
my $count =1;
my $FantDist;
my $invFantDist;
my $ap;
my $dist;
my $ptss;
my $ltss;
my $tsstotss;


##################################################################
############## OPENING OUTPUT FILES ##############################
##################################################################

# Opens all the major required Output files
open(LNCS, ">lncs_$file") or die "Could not open first output lncs_$file\n";
open(PCS, ">protein_coding_$file") or die "Could not open first output protein_coding_$file\n";
open(MISC, ">misc_$file") or die "Could not open first output misc_$file\n";




##Opens the file and removes the endline characters. Splits the line at tabs into the array @data
while (my $line = <IN>) {
    chomp($line);
    my @data = split("\t", $line);
    
    if ($line =~ /\#/){
        my $total = @data;
        $numsamp = $total - 5;
        my @samples = @data[5..$#data];
        
        
        print "\nThis script assumes that you have";
        print color('bold red');
        print " $numsamp ";
        print color('reset');
        print "samples with the following names:\n";
        print color('bold blue');
        print "@samples\n\n";
        print color('reset');
        print "If this is incorrect, please double-check that your input file is properly formatted.\n";
        print "Also, please check misc_$file to see if any critical transcripts have been erroneously removed.\n\n";
        next;
    }
    
# Writes out the lncs and protein coding genes to two separate files. Anything that is not annotated as "lnc" or
# "protein_coding" gets shunted to the "misc" file. Make sure to double-check this file to make sure that nothing
# has been accidentally misannotated.

    
    if ($data[4]=~ /lnc/ || $data[4] =~ /antisense/) {
        $lncs{$data[3]} = $line;
        print LNCS "$line\tL$indcount\n";
    }elsif($data[4]=~ /protein_coding/){
        $pcs{$data[3]} = $line;
        print PCS "$line\tP$indcount\n";
    }else{
        print MISC "$line\n";
    }
    
    $indcount++;
}

close IN;
close LNCS;
close PCS;
close MISC;


##################################################################
################ READING IN CHIAPET DATA# ########################
##################################################################
##Assumes CHR1  START   STOP    CHR2   START   STOP



#Opens up the CHIApet file and various other output files for the two "halves" of each CHIAPET interaction
open(CHIA, "<$chiapetfile") or die "Could not open file: $chiapetfile\n"; ##Changed this to NB4...who knows?
open(LEFT, ">LEFT1.txt") or die "Could not open file: LEFT1.txt\n";
open(RIGHT, ">RIGHT1.txt") or die "Could not open file: RIGHT1.txt\n";

#Just a counter for later hash referencing
my $countchia = 0;

#Actually reading in the CHIAPET data from the file and out-putting the different reads to the LEFT and RIGHT files. 
while (my $line = <CHIA>) {
    
    chomp($line);
    my @data = split("\t", $line);
    
    my $ans = &Overlap($data[1], $data[2], $data[4], $data[5]);
    next if ($ans == 1);
    
    if (defined($data[6])) {
        print LEFT "$data[0]\t$data[1]\t$data[2]\tLE$countchia\t$data[6]\n"; ##Added $data6 (the type of chiapet on November 10th)
        print RIGHT "$data[3]\t$data[4]\t$data[5]\tRI$countchia\t$data[6]\n"; ##Added $data6 (the type of chiapet on November 10th)
    }else{
        print LEFT "$data[0]\t$data[1]\t$data[2]\tLE$countchia\tLE$countchia\n"; ##Added $data6 (the type of chiapet on November 10th)
        print RIGHT "$data[3]\t$data[4]\t$data[5]\tRI$countchia\tRI$countchia\n"; ##Added $data6 (the type of chiapet on November 10th)
    }
    
    
    
    $countchia++;
    
}



close CHIA;
close LEFT;
close RIGHT;

##All the CHIApet bedtools intersects 

system("sort -k1,1 -k2,2n LEFT1.txt > LEFT.txt");
system("sort -k1,1 -k2,2n RIGHT1.txt > RIGHT.txt");

system("bedtools intersect -wa -wb -a lncs_$file -b LEFT.txt >> CHIAPET_temp.txt");
system("bedtools intersect -wa -wb -a lncs_$file -b RIGHT.txt >> CHIAPET_temp.txt");
system("bedtools intersect -wa -wb -a protein_coding_$file -b LEFT.txt >> CHIAPET_temp.txt");
system("bedtools intersect -wa -wb -a protein_coding_$file -b RIGHT.txt >> CHIAPET_temp.txt");
#system("bedtools window -w -a lncs_$file -b LEFT.txt >> CHIAPET_temp.txt");
#system("bedtools window -w -a lncs_$file -b RIGHT.txt >> CHIAPET_temp.txt");
#system("bedtools window -w -a protein_coding_$file -b LEFT.txt >> CHIAPET_temp.txt");
#system("bedtools window -w -a protein_coding_$file -b RIGHT.txt >> CHIAPET_temp.txt");

open(CHIA2, "<CHIAPET_temp.txt");

while (my $line = <CHIA2>) {
    
    chomp($line);
    my @data = split("\t", $line);
    #Saves the individual lnc or protein/CHIAPET overlaps
    #$CHIA{L/P#}={LE/RI#}
    #$CHIA{cell_type}{L/P#}={LE/RI#}
    $CHIA{$data[$numsamp+10]}{$data[$numsamp+5]} .= "$data[$numsamp+9]\t";
    #print "$data[$numsamp+5]\t$data[$numsamp+9]\n";
}

close CHIA2;

#####STUPID FILLER FOR A SPLIT########
foreach my $key (keys %CHIA){
    foreach my $key2 (keys $CHIA{$key}){
        $CHIA{$key}{$key2} .= "spacer";
    }
}
system("rm CHIAPET_temp.txt;");

print "ChIA-PET file hashed...\n";

##################################################################
################# PROTEIN-LESS LNCS #############################
##################################################################

system("rm lncs_and_proteins_intersect_$file");
##Performs the linRNA/protein intersect and outputs the master file
system("bedtools window -w 400000 -a lncs_$file -b protein_coding_$file > lncs_and_proteins_intersect_$file");
system("bedtools window -c -w 400000 -a lncs_$file -b protein_coding_$file > temp_$file");
system("bedtools intersect -u -a lncs_$file -b protein_coding_$file > temp2_$file");

###This part saves a hash of the lncs that are not within 100kb of a protein-coding gene. 
open(LNC0, "<temp_$file");

##Creates a hash %alllncs that has an L# as the key and the line with all the lnc data as the value. 

while (my $line = <LNC0>) {
    chomp($line);
    my @data = split("\t", $line);
    if ($data[$#data] == 0) {
        pop(@data);
        my @arr = ("1") x $numsamp;
        my $nocount = join("\t", @data,"chrZ","1000000","1000001","null","protein_coding",@arr,"P0");
        $alllncs{$data[$numsamp+5]} = "$nocount";
        system("echo \"$nocount\" >> lncs_and_proteins_intersect_$file");
    } 
}

close LNC0;
system("rm temp_$file;");

open(LNC1, "<temp2_$file");

##Creates a hash %intragenic that includes all lncs that overlap a protein_coding gene.

while (my $line = <LNC1>) {
    chomp($line);
    my @data = split("\t", $line);
    $intragenic{$data[$numsamp+5]}=0;
}

close LNC1;
system("rm temp2_$file;");


print "Distal lncs hashed...\n";


##################################################################
##################### READING IN TAD DATA ########################
##################################################################

open(LANDP, "<lncs_and_proteins_intersect_$file");
open(OUTTAD, ">MAXregion.bed");
while (my $line = <LANDP>) {
    
     
    substr($line, 0, 0) = $count."\t";
    my @data = split("\t", $line);
    #Just making easier-to-use-variables
    next if ($data[1] eq "chrZ");
    $lchr = $data[1];
    $lstart = $data[2];
    $lstop = $data[3];
    $pchr = $data[$numsamp+7];
    $pstart = $data[$numsamp+8];
    $pstop = $data[$numsamp+9];
    $upplus = $data[2]-1000;
    $downplus = $data[3]+1000;
    my @positions = ($lstart, $lstop, $pstart, $pstop);
    
    my $min = min(@positions);
    my $max = max(@positions);
    
    print OUTTAD "$lchr\t$min\t$max\t$count\n";
    $count++;
}

close OUTTAD;

##Performs the lncRNA/protein intersect with TADs
system("bedtools intersect -u -f 1 -a MAXregion.bed -b hESCTADboundariesCombined.bed > lncsandproteinsintads.bed");
system("rm MAXregion.bed");


open(TAD2, "<lncsandproteinsintads.bed");

##Reads in the lncs/proteins and stores the line # as a key in a hash. Numbers were made the same way they are later so...hopefully this works...
while (my $line = <TAD2>) {
    chomp($line);
    my @data = split("\t", $line);
    
    $TADS{$data[3]} = 1;
    
}
system("rm lncsandproteinsintads.bed");
close TAD2;

print "TADs hashed...\n";

##################################################################
################## READING IN CHIPSEQ DATA #######################
##################################################################


system("bedtools intersect -wa -wb -a lncs_$file -b $chipfile > tempchip1.txt"); 
open(CHIP1, "<tempchip1.txt");

###This should make a hash with the lnc number (L3, L567 etc) and will be defined if it overlaps with a chip-seq peak. 
while (my $line = <CHIP1>) {
    
    chomp($line);
    my @data = split("\t", $line);
    
    if ($cellectCHIP eq "NA") {
        $CHIP{$data[$numsamp+9]}{$data[$numsamp+5]} .= "$data[$numsamp+9]\t";
    }else{
        if ($line =~ /$cellectCHIP/g) {
            $CHIP{$data[$numsamp+9]}{$data[$numsamp+5]} .= "$data[$numsamp+9]\t";
        }
    }
    
}

close CHIP1;
system("rm tempchip1.txt");


print "ChIP file hashed...\n";

##################################################################
################## READING IN FANTOM DATA ########################
##################################################################

###AKA dealing with things that are near lncs, but not necessarily overlapping them. Paper used 5kb.

if ($cellectENH ne "NA") {
    system("grep \"$cellectENH\" $enhancerfile > tempselectenhancers.txt");
    $enhancerfile = "tempselectenhancers.txt";
}


system("bedtools closest -D ref -t first -a lncs_$file -b $enhancerfile > tempnear1.txt");

open(NEAR, "<tempnear1.txt");

while (my $line = <NEAR>) {
    chomp($line);
    my @data = split("\t", $line);
    
    $NEAR{$data[$numsamp+5]}=$data[$#data];

}

close NEAR;
system("rm tempnear1.txt");

print "Enhancers hashed...\n";

##################################################################
###################### READING IN SE DATA ########################
##################################################################


if ($cellectSE ne "NA") {
    system("grep \"$cellectSE\" $sefile > tempselectsuperenhancers.txt");
    $sefile = "tempselectsuperenhancers.txt";
}

system("bedtools closest -D ref -t first -a lncs_$file -b $sefile > tempnear2.txt"); 
open(NEAR2, "<tempnear2.txt");

while (my $line = <NEAR2>){
    chomp($line);
    my @data = split("\t", $line);
    
    $NEAR2{$data[$numsamp+5]}=$data[$#data];

}

close NEAR2;
#system("rm tempnear2.txt");

print "Super Enhancers hashed...\n";

##################################################################
################## READING IN BIOMARTFILE DATA ###################
##################################################################

open(BIO, "<$biomartfile");



while (my $line = <BIO>) {
    chomp($line);
    my @data = split("\t", $line);
    
    $GO{$data[2]}=$data[0];
    
    $strand{$data[2]} = $data[1];  
    
}
close BIO;

print "Lnc characteristics hashed...\n";

##################################################################
################## READING IN NucorCyt file ######################
##################################################################

open(SUB, "<$nucfracfile");

#%subcell = %{hashbash("Count_hg19_nuc_cyt_Jan14_forCREPE.txt",0,9,"F")};

while (my $line = <SUB>) {
    chomp($line);
    my @data = split("\t", $line);
    
    next if ($data[1] eq "N/A");
    next if $data[8] == 0;
    $subcell{$data[0]}=$data[9];

}
close SUB;

print "Cell fraction file hashed...\n";

##################################################################
###################### READING IN RBP DATA #######################
##################################################################


if ($cellectRBP ne "NA") {
    system("grep \"$cellectRBP\" $rbpfile > tempselectrbps.txt");
    $rbpfile = "tempselectrbps.txt";
}

system("bedtools intersect -wa -wb -a lncs_$file -b $rbpfile > tempnear3.txt"); 

%RBP = %{hashbash("tempnear3.txt",$numsamp+5,$numsamp+9,"T")};

#system("rm tempnear3.txt");

print "RBPs hashed...\n";

##################################
##### OPENS AN INSTANCE OF R #####
##################################
my $R = Statistics::R->new();
#$R->run(q`rm(list = ls())`);
##################################
##################################


############################################################
## Pre-running the lnc and protein file for an adjusted p.#
############################################################

open(PRETEST, "<lncs_and_proteins_intersect_$file") or die "Could not open lncs_and_proteins_intersect_$file";

my $count2 =1;
while (my $line = <PRETEST>) {
    
    substr($line, 0, 0) = $count2."\t";
    chomp($line);
    my @data = split("\t", $line);
    
    @Lexp = @data[6..$numsamp+5];
    @Pexp = @data[$numsamp+12..$numsamp+11+$numsamp];
    #print "L expression: @Lexp\n";
    $R->set( 'col1', \@Lexp );
    $R->set( 'col2', \@Pexp );
    #print "@Lexp\n";
    #print "Lncs:@Lexp\n";
    #print "Proteins:@Pexp\n";
    $R->run(q`options(max.print = 99999999)`);
    $R->run(q`tabletest<-cor.test(col1,col2, alternative = "two.sided", method ="spearman")`);
    my @y = split(" ", $R->get( 'tabletest' ));
    #print "BEFORE CREPE1: @y\n";
    $adjustedp{$count2} = "$y[13]";
    push(@testadjust, $y[13]);
    $count2++;
    
    
}

$R->set( 'pvals', \@testadjust );

##This array has all the adjusted pvalues in the same order as then appear in the corresponding lnc/protein file. 
my @adjustedps = split(" ", $R->run(q`p.adjust(pvals, method = "BH")`));
my @finalps;



#This strips off all the warnings from the R output and keeps just the numbers and the "NA"s
foreach my $val (@adjustedps){
    if ($val =~ /^\d/) {
        push(@finalps, $val);
    }if ($val eq "NA") {
        push(@finalps, $val);

    }
    #print OUTTEST "Neither: $val\t";
}

#print OUTTEST "\n";

print "p-values adjusted...\n\n";

print "Finished reading in all input files. Starting CREPE calculations!\n\n";

#%%%%%%%%%%%%%%%%%%%%%%%%%%***********%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
##################################################################%
###################  THE HEART OF THE CREPE  #####################%
##################################################################%
#%%%%%%%%%%%%%%%%%%%%%%%%%%***********%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

##Open in the intersected file and open the final output file.
open(MAS, "<lncs_and_proteins_intersect_$file") or die "Could not open lncs_and_proteins_intersect_$file";
open(OUT, ">Master_$file") or die "Could not open Master_$file";

##print a Header for the output file:
print OUT "LINE_NUMBER\tCHRlnc\tSTARTlnc\tSTOPlnc\tNAMElnc\tTYPElnc\tNUMBERlnc\tCHRprot\tSTARTprot\tSTOPprot\tNAMEprot\t";
print OUT "TYPEprot\tNUMBERprot\tLNC_PROTEIN_OVERLAP\tDIST_L_to_P\tLNC_AVERAGE\tPROTEIN_AVERAGE\tPEARSON\tPEARSONp\t";
print OUT "SPEARMAN\tSPEARMANp\tCHIA\tTAD\tINTERGENIC\tCHIPSEQ\tH3K4ME3\tH3K27AC\tH3K4ME1\tRBPs\tNEARFANTOM\tNEAR_SE\t";
print OUT "GO\tP_strand\tL_strand\tTSStoTSSdist\tFraction\tPROTEIN_Fraction\tSENSE_CATEGORY\tADJUSTED_SPEARMAN\tSCORE\tENHANCER_SCORE\n";

$count =1;
my $checker=25;

while (my $line = <MAS>) {
    
    chomp($line);
    substr($line, 0, 0) = $count."\t";  
    my @data = split("\t", $line);
    $count++;
    
    ####Outputs a notification at 25, 50 and 75% complete
    if ($count/$count2 > 0.25 && $checker == 25) {
        print "25% complete...\n\n";
        $checker = 50;
    }if ($count/$count2 > 0.50 && $checker == 50) {
        print "50% complete...\n\n";
        $checker = 75;
    }if ($count/$count2 > 0.75 && $checker == 75) {
        print "75% complete...\n\n";
        $checker = 100;
    }
    
    my $percent = $count/$count2;

    ##Populates the %Master hash
    $Master{$data[0]}= $line;
    $limiter = join("\t", @data[0,1,2,3,4,5,$numsamp+6,$numsamp+7,$numsamp+8,$numsamp+9,$numsamp+10,$numsamp+11,$#data]);
    $limMaster{$data[0]}= $limiter;
    
    
    #Just making easier-to-use-variables
    $lchr = $data[1];
    $lstart = $data[2];
    $lstop = $data[3];
    $lname = $data[4];
    $pchr = $data[$numsamp+7];
    $pstart = $data[$numsamp+8];
    $pstop = $data[$numsamp+9];
    $pname = $data[$numsamp+10];
    @Lexp = @data[6..$numsamp+5];
    @Pexp = @data[$numsamp+12..$numsamp+11+$numsamp];
    $dist=0;
    $ltss="NA";
    $ptss="NA";
    

    if (exists $strand{$lname}) {
        if ($strand{$lname} > 0) {
            $ltss = $lstart;
        }if ($strand{$lname} < 0) {
            $ltss = $lstop;
        }
    }if (exists $strand{$pname}){
        if ($strand{$pname} > 0) {
            $ptss = $pstart;
        }if ($strand{$pname} < 0) {
            $ptss = $pstop;
        }        
    }
    

    
    
    
    #Annotates lncs as overlapping or distal to possible target genes 
    #Does the range (start1, end1) overlap with (start2, end2)?
    my $ans = &Overlap($lstart, $lstop, $pstart, $pstop); ####MIGHT NEED TO CHANGE WINDOW##
    if ($ans == 1) {
        $Master{$data[0]} .= "\tOverlap\t$dist";
        $limMaster{$data[0]} .= "\tOverlap\t$dist";
    }if ($ans == 0) {
        

                
        #if ($lstart < $pstart) {
        #    $dist = $pstart-$lstop;
        #}elsif($lstart > $pstart){
        #    $dist =$lstart-$pstop;
        #}
        
        #CHanged March 17. This should make the dist a negative number if the protein is upstream of the lnc
        
        if ($lstart < $pstart) {
            $dist = $pstart-$lstop;
        }elsif($lstart > $pstart){
            $dist =$pstop-$lstart;
        } 

        
        
        $Master{$data[0]} .= "\tDistal\t$dist";
        $limMaster{$data[0]} .= "\tDistal\t$dist";
        
    }
    

    ##calculates the average expression value
    $laverage = mean(@data[6..$numsamp+5]);
    $paverage = mean(@data[$numsamp+12..$numsamp+11+$numsamp]);
    
    
    #Adds the average expression for each lnc and protein
    $Master{$data[0]} .= "\t$laverage\t$paverage";
    $limMaster{$data[0]} .= "\t$laverage\t$paverage";
    

    
    ## Calculates the Pearson and Spearman correlation of the lnc and associated protein-coding gene.
    
    $R->set( 'col1', \@Lexp );
    $R->set( 'col2', \@Pexp );
    $R->run(q`tabletest<-cor.test(col1,col2, alternative = "two.sided", method ="pearson")`);
    my @y = split(" ", $R->get( 'tabletest' ));
    
    #print "WITHIN CREPE1: @y\n";

    $Master{$data[0]} .= "\t$y[$#y]";
    $limMaster{$data[0]} .= "\t$y[$#y]";
    $Master{$data[0]} .= "\t$y[15]";
    $limMaster{$data[0]} .= "\t$y[15]";
    

    
    $R->run(q`tabletest<-cor.test(col1,col2, alternative = "two.sided", method ="spearman")`);
    @y = split(" ", $R->get( 'tabletest' ));
    #print "WITHIN CREPE2: @y\n";
    
    $Master{$data[0]} .= "\t$y[$#y]";
    $limMaster{$data[0]} .= "\t$y[$#y]";
    $Master{$data[0]} .= "\t$y[13]";
    $limMaster{$data[0]} .= "\t$y[13]";

#################################################
######### Checking the CHIAPET Data #############
#################################################

    my $currentloops = 0;

    foreach my $key (keys %CHIA){
        #print "$key\t$data[$numsamp+6]\t$data[$numsamp+12+$numsamp]\n";
        if (exists $CHIA{$key}{$data[$numsamp+6]} && exists $CHIA{$key}{$data[$numsamp+12+$numsamp]}) {
            $yes2 =0;
            
    
            #print "$CHIA{$key}{$data[$numsamp+6]}\n";
            @lnc = split("\t", $CHIA{$key}{$data[$numsamp+6]});
            @prot = split("\t", $CHIA{$key}{$data[$numsamp+12+$numsamp]});
            
            pop @lnc;
            pop @prot;

        
            foreach my $entry (@lnc){
                $check {$entry}=1;
            }
            
    ##The following checks if the other half (right or left) of the CHIA loop matches between a lnc and a protein. If it does, "yes2" becomes 1 and outputs "Loop"
            
            foreach my $entry (@prot){
                
                if ($entry =~ /LE/) {
                    $entry =~ s/LE/RI/;
                }else{
                    $entry =~ tr/RI/LE/; 
                }
            
                #print "$entry\n";
                
                if (exists $check{$entry}) {
                    $yes2 =1;
                }
            }
            undef(%check);
            
            if ($yes2==1) {
                if ($key > $currentloops) {
                    $currentloops = "$key";
                }
                
            }
            
            
        }
    }   
        
    if ($currentloops eq "") {
        $Master{$data[0]} .= "\tNA";
        $limMaster{$data[0]} .= "\tNA";
    }else {
        $Master{$data[0]} .= "\t$currentloops";
        $limMaster{$data[0]} .= "\t$currentloops";
    }

    undef(%check);
    
#################################################
############## Checking TADs ####################
#################################################

    if (exists $TADS{$data[0]}) {
        
        $Master{$data[0]} .= "\t1";
        $limMaster{$data[0]} .= "\t1";
      
    }else  {
        
        $Master{$data[0]} .= "\t0";
        $limMaster{$data[0]} .= "\t0";
      
    }


    


#################################################
########### CHECKING INTERGENIC #################
#################################################

    my $intergenic = 1;

    if (exists $intragenic{$data[$numsamp+6]}) {
        $intergenic = 0;
    }
    

    $Master{$data[0]} .= "\t$intergenic";
    $limMaster{$data[0]} .= "\t$intergenic";



#################################################
############## Checking CHIPSEQ #################
#################################################

my $currentchip="";

foreach my $key (keys %CHIP){
        #print "$key\t$data[$numsamp+6]\t$data[$numsamp+12+$numsamp]\n";
        if (exists $CHIP{$key}{$data[$numsamp+6]}) {
            $currentchip .= "$key;";
        }
    }   
        
    if ($currentchip eq "") {
        $Master{$data[0]} .= "\t0";
        $limMaster{$data[0]} .= "\t0";
    }else {
        $Master{$data[0]} .= "\t$currentchip";
        $limMaster{$data[0]} .= "\t$currentchip";
    }

    my $H3K4ME3 = "0";
    my $H3K4ME1 = "0";
    my $H3K27AC = "0";
    
    my @peaks = split(";", $currentchip);
    
    foreach (@peaks){
        my @now = split ("_", $_);
        if ($now[0] =~ /K4M3/ && $now[1] > $H3K4ME3) {
            $H3K4ME3 = $now[1]/100;
        }if ($now[0] =~ /K4M1/ && $now[1] > $H3K4ME1) {
            $H3K4ME1 = $now[1];
        }if ($now[0] =~ /K27AC/ && $now[1] > $H3K27AC) {
            $H3K27AC = $now[1];
        }
    }
    
    
    $Master{$data[0]} .= "\t$H3K4ME3\t$H3K27AC\t$H3K4ME1";
    $limMaster{$data[0]} .= "\t$H3K4ME3\t$H3K27AC\t$H3K4ME1";

        
#################################################
############ Checking the RBP Data ##############
#################################################

    
    if (exists $RBP{$data[$numsamp+6]}) {
        #print "Original: $RBP{$data[$numsamp+6]}\n";
        my @currrbp =split("\t", $RBP{$data[$numsamp+6]});
        #print "Split: @currrbp\n";
        my $currrbp2 = join(";", @currrbp);
        #print "Join: $currrbp2\n";
        $Master{$data[0]} .= "\t$currrbp2";
        $limMaster{$data[0]} .= "\t$currrbp2";        
    }else {

        $Master{$data[0]} .= "\t0";
        $limMaster{$data[0]} .= "\t0";
    }


                
#################################################
######## CHECKING IF NEAR FANTOM ################
#################################################

    if (exists ($NEAR{$data[$numsamp+6]})) {
        $Master{$data[0]} .= "\t$NEAR{$data[$numsamp+6]}";
        $limMaster{$data[0]} .= "\t$NEAR{$data[$numsamp+6]}";
        $FantDist = $NEAR{$data[$numsamp+6]}
    }else{
        $Master{$data[0]} .= "\tNoData";
        $limMaster{$data[0]} .= "\tNoData";
        $FantDist = "0.1";
    }
    
                
               


    
#################################################
#################################################
    my $lewp=0;
    
    
    if ($currentloops ne "") {$lewp = 1};
    if ($FantDist == 0) {
        $invFantDist = 1000;
    } if ($FantDist == 0.1) {
        $invFantDist = 0;
    }elsif($FantDist >0){
        $invFantDist = 2**(1000/$FantDist);
    }
    

#################################################
########## CHECKING IF NEAR SE ##################
#################################################

    if (exists ($NEAR2{$data[$numsamp+6]})) {
        $Master{$data[0]} .= "\t$NEAR2{$data[$numsamp+6]}";
        $limMaster{$data[0]} .= "\t$NEAR2{$data[$numsamp+6]}";
    }else{
        $Master{$data[0]} .= "\tNoData";
        $limMaster{$data[0]} .= "\tNoData";
    }

#################################################
######## Adding GO Ontology #####################
#################################################

    my $GOONT = "";
    
    if (exists $GO{$pname}) {
        $GOONT = $GO{$pname};
    }
    
    
        $Master{$data[0]} .= "\t$GOONT";
        $limMaster{$data[0]} .= "\t$GOONT";



#################################################
######## Adding STRAND ##########################
#################################################

    my $strandp = "0";
    my $strandl = "0";
    if (exists $strand{$pname}) {
        $strandp = $strand{$pname};
    }if (exists $strand{$lname}) {
        $strandl = $strand{$lname};
    }


    $Master{$data[0]} .= "\t$strandp";
    $limMaster{$data[0]} .= "\t$strandp";
    $Master{$data[0]} .= "\t$strandl";
    $limMaster{$data[0]} .= "\t$strandl";


#############################################
######### Adding TSS to TSS info ################
#############################################
    if ($ltss eq "NA" || $ptss eq "NA") {
        $tsstotss = -1;  
    }else{
        $tsstotss = abs($ltss-$ptss);
    }
    
    


    $Master{$data[0]} .= "\t$tsstotss";
    $limMaster{$data[0]} .= "\t$tsstotss";


#################################################
######## Adding subcellularfraction of lnc #####
#################################################

    my $fraction = "NA";
    my $proteinfraction = "NA";
    
    if (exists $subcell{$lname}) {
        $fraction = $subcell{$lname};
    }if (exists $subcell{$pname}) {
        $proteinfraction = $subcell{$pname};
    }


    $Master{$data[0]} .= "\t$fraction\t$proteinfraction";
    $limMaster{$data[0]} .= "\t$fraction\t$proteinfraction";



#################################################
######## ANTISENSE AND OVERLAP #################
#################################################

    my $sensitivity = "NA";
    
    if ($tsstotss > 0 && $tsstotss <2000) {
        if (($strandp < 0 && $strandl >0) || ($strandp < 0 && $strandl >0) ) {
            
            if ($limMaster{$data[0]} =~ /Overlap/) {
                $sensitivity = "Antisense_Overlap";
            }if ($limMaster{$data[0]} =~ /Distal/) {
                $sensitivity = "Antisense_Distal";
            }
            
        }
        
    }else{
        if ($limMaster{$data[0]} =~ /Overlap/) {
                $sensitivity = "Overlap";
        }if ($limMaster{$data[0]} =~ /Distal/) {
                $sensitivity = "Distal";
        }
    }
   
    $Master{$data[0]} .= "\t$sensitivity";
    $limMaster{$data[0]} .= "\t$sensitivity";
    
#################################################
######## Adding ADJUSTED SPEARMAN P #############
#################################################


    $ap = shift(@finalps);

    $Master{$data[0]} .= "\t$ap";
    $limMaster{$data[0]} .= "\t$ap";



#################################################
######## FINAL SCORE AND ENHANCER SCORE ######
#################################################

### Cis-regulatory score:
    my $score=0;
    

    if ($ap ne "NA"){
        if ($fraction eq "NA") {
            $fraction=0.5
        }
        
        $score = 10*abs((-log($ap+ 0.001))) * (($H3K4ME3+0.1) * ($fraction+0.01));
    }else{
        $score= "NA";
    }
    
    $Master{$data[0]} .= "\t$score";
    $limMaster{$data[0]} .= "\t$score";  
    
### Enhancer Regulatory score:
    
    my $enhancerscore = ((($H3K4ME1+1))+( $H3K27AC+1))*(1+ ($currentloops)/100);
    
    $Master{$data[0]} .= "\t$enhancerscore";
    $limMaster{$data[0]} .= "\t$enhancerscore";


#################################################
#################################################
#################################################
#################################################
    
    ##Prints out the final file. 
    print OUT "$limMaster{$data[0]}\n";
       
}

close MAS;
print DAILYLOG "COMPLETED SUCCESSFULLY $today\n\n";

##################################
#### CLOSES AN INSTANCE OF R #####
##################################
$R->stop();
##################################
##################################


##################################################################
########################## Subroutines ###########################
##################################################################

##Enter start and stop of two elements as list
sub Overlap(){
    #Does the range (start1, end1) overlap with (start2, end2)?"""
    #print "$_[1] >= $_[2] && $_[3] >= $_[0]\n";
    if ($_[1] >= $_[2] && $_[3] >= $_[0]) {
        return "1";# end1 >= start2 and end2 >= start1
    }else{
        return "0";
    }
}
######################

##Takes as input a filename, an @data position for keys and a @data position for values
##and a concatenate option that is T or F. Outputs a hash;

sub hashbash{

    my %hash;
    undef(%hash);
    open(IN, "$_[0]");

    while (my $line = <IN>) {
        
        chomp($line);
        my @data = split("\t", $line);
        if ($_[3] eq "F") {
            $hash{$data[$_[1]]} = $data[$_[2]];
        }if($_[3] eq "T"){
            $hash{$data[$_[1]]} .= "$data[$_[2]]\t";
        }
    }
    
    close IN;
    
    return \%hash;
}

##Takes as input a filename, @data position for key1, @data position for key 2 and @data position for values
##and a concatenate option that is T or F. Outputs a multi-dimensional hash;

sub hashbash2{

    my %hash;
    undef(%hash);
    open(IN, "$_[0]");
            
    while (my $line = <IN>) {
        
        chomp($line);
        my @data = split("\t", $line);
        
        if ($_[4] eq "F") {
            $hash{$data[$_[1]]}{$data[$_[2]]} = $data[$_[3]];
        }if($_[4] eq "T"){
            $hash{$data[$_[1]]}{$data[$_[2]]} .= $data[$_[3]];
        }
        
        

    }
    
    close IN;
    
    return \%hash;   
}

######################

sub mean {
    return sum(@_)/@_;
}








 

