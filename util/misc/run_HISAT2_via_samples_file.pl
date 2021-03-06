#!/usr/bin/env perl

use strict;
use warnings;
use FindBin;
use lib ("$FindBin::Bin/../../PerlLib");
use Process_cmd;
use Getopt::Long qw(:config no_ignore_case bundling pass_through);
use Pipeliner;
use File::Basename;

my $CPU = 2;

my $usage = <<__EOUSAGE;

############################################################
#
# Required:
#
#  --genome <string>         target genome.fasta file
#
#  --gtf <string>            annotation in gtf format
#
#  --samples_file <string>   Trinity samples file
#
# Optional:
#
#  --CPU <int>               multithreading (default: $CPU)
#
###########################################################


__EOUSAGE

    ;




my $help_flag;
my $genome_fa;
my $annotation_gtf;
my $samples_file;


&GetOptions ( 'h' => \$help_flag,
              'genome=s' => \$genome_fa,
              'gtf=s' => \$annotation_gtf,
              'samples_file=s' => \$samples_file,
              'CPU=i' => \$CPU,
    );

if ($help_flag) { die $usage; }

unless ($genome_fa && $annotation_gtf && $samples_file) {
    die $usage;
}



main: {
    
    my @read_sets = &parse_samples_file($samples_file);
    
    ## align reads to the mini-genome using hisat2

    ###########################
    # first, build genome index
    
    my $pipeliner = new Pipeliner(-verbose => 1);
    
    $pipeliner->add_commands(new Command("hisat2_extract_splice_sites.py $annotation_gtf  > $annotation_gtf.ss",
                                         "$annotation_gtf.ss.ok"));
    
    $pipeliner->add_commands(new Command("hisat2_extract_exons.py $annotation_gtf > $annotation_gtf.exons",
                                         "$annotation_gtf.exons.ok"));
        
    $pipeliner->add_commands(new Command("hisat2-build --exon $annotation_gtf.exons --ss $annotation_gtf.ss -p $CPU $genome_fa $genome_fa",
                                         "$genome_fa.hisat2.build.ok"));

    $pipeliner->run();


    #####################
    ## now run alignments
    
    my $aln_checkpoints_dir = "hisat2_aln_chkpts." . basename($genome_fa);
    unless (-d $aln_checkpoints_dir) {
        mkdir($aln_checkpoints_dir) or die "Error, cannot mkdir $aln_checkpoints_dir";
    }
    
    foreach my $read_set_aref (@read_sets) {
        my ($sample_id, $left_fq, $right_fq) = @$read_set_aref;


        my $bamfile = "$sample_id.cSorted.hisat2." . basename($genome_fa) . ".bam";
        
        $pipeliner->add_commands(new Command("bash -c \"set -eof pipefail; hisat2 --dta -x $genome_fa -p $CPU -1 $left_fq -2 $right_fq | samtools view -Sb -F 4 | samtools sort -o $bamfile \" ",
                                             "$aln_checkpoints_dir/$bamfile.ok"));
        
    }
    
    $pipeliner->run();
    
    exit(0);
    
}



####
sub parse_samples_file {
    my ($samples_file) = @_;

    my @samples;
    
    open(my $fh, $samples_file) or die "Error, cannot open file $samples_file";
    while (<$fh>) {
        chomp;
        my @x = split(/\t/);
        my ($cond, $rep, $fq_a, $fq_b) = @x;

        push (@samples, [$rep, $fq_a, $fq_b]);
    }
    close $fh;

    return (@samples);
}

