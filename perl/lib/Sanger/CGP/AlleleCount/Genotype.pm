package Sanger::CGP::AlleleCount::Genotype;

use strict;

use Carp;
use English qw( -no_match_vars );
use warnings FATAL => 'all';

use Sanger::CGP::AlleleCount;
use Sanger::CGP::AlleleCount::PileupData;

use Bio::DB::Sam;
use Bio::DB::Bam::AlignWrapper;

use constant MAX_PILEUP_DEPTH => 1_000_000;
use constant MIN_MAPQ => 35;
use constant TAB => "\t";
use constant NL => "\n";

my $g_pu_data; # required for pileup;
my $g_pb_qual;
my $g_sam;

sub new {
  my ($class, $opts) = @_;
  my $self = { };
  bless $self, $class;
  if(defined $opts) {
    $self->{'species'} = $opts->{'species'};
    $self->{'build'} = $opts->{'build'};
  }
  return $self;
}

=item get_full_snp6_profile
  Writes tab seperated allelic counts and depth to specified FH
  Uses all snps defined in file used by ngs_cn (format slightly different)
=cut
sub get_full_snp6_profile {
  my ($self, $bam_file, $fh, $min_qual) = @_;
  $g_pb_qual = $min_qual || MIN_MAPQ;
  my $sam = Bio::DB::Sam->new(-bam => $bam_file);
  $sam->max_pileup_cnt(MAX_PILEUP_DEPTH);
  $g_sam = $sam;
  my $snp6_file = $self->ngs_cn_snps({'species'=>'HUMAN','build'=>37});
  my ($region, $chr, $pos, $allA, $allB);
  print $fh "#CHR\tPOS\tCount_Allele_A\tCount_Allele_B\tGood_depth\n" or croak "Failed to write line: $OS_ERROR\n";
  open my $SNP6, '<', $snp6_file or croak "Unable to open $snp6_file for reading: $OS_ERROR\n";
  while(my $line = <$SNP6>) {
    chomp $line;
    ($chr, $pos, undef, undef, $allA, $allB) = split /\s/, $line;
    $g_pu_data = Sanger::CGP::AlleleCount::PileupData->new($chr, $pos, $allA, $allB);
    $region = $chr.':'.$pos.'-'.$pos;
    $sam->fast_pileup($region, \&allele_counts_callback);
    print $fh $g_pu_data->chr,TAB,$g_pu_data->pos,TAB,$g_pu_data->count_A,TAB,$g_pu_data->count_B,TAB,$g_pu_data->depth,NL or croak "Failed to write line: $OS_ERROR\n";
  }
  close $SNP6;
  return 1;
}

=item get_full_loci_profile
  Writes tab seperated allelic counts and depth to specified FH
  Uses all loci defined in specified file
=cut
sub get_full_loci_profile {
  my ($self, $bam_file, $fh, $loci_file, $min_qual) = @_;
  $g_pb_qual = $min_qual || MIN_MAPQ;
  my $sam = Bio::DB::Sam->new(-bam => $bam_file);
  $sam->max_pileup_cnt(MAX_PILEUP_DEPTH);
  $g_sam = $sam;
  my ($region, $chr, $pos, $allA, $allB);
  print $fh "#CHR\tPOS\tCount_A\tCount_C\tCount_G\tCount_T\tGood_depth\tInputFile\n" or croak "Failed to write line: $OS_ERROR\n";
  open my $LOCI, '<', $loci_file or croak 'Unable to open '.$loci_file.' for reading';
  while(my $line = <$LOCI>) {
    chomp $line;
    ($chr, $pos) = split /\s/, $line;
    $g_pu_data = Sanger::CGP::AlleleCount::PileupData->new($chr, $pos);
    $region = $chr.':'.$pos.'-'.$pos;
    $sam->fast_pileup($region, \&allele_counts_callback);
    print $fh $g_pu_data->chr or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$g_pu_data->pos or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$g_pu_data->residue_count('A') or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$g_pu_data->residue_count('C') or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$g_pu_data->residue_count('G') or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$g_pu_data->residue_count('T') or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$g_pu_data->depth or croak "Failed to write line: $OS_ERROR\n";
    print $fh TAB,$bam_file,NL or croak "Failed to write line: $OS_ERROR\n";
  }
  close $LOCI;
  return 1;
}

sub allele_counts_callback {
  my ($seqid, $pos, $pu) = @_;
  return if($pos != $g_pu_data->pos);
  foreach my $p (@{$pu}) {
    next if($p->indel || $p->is_refskip);
    my $a = $p->alignment;
    my $flagValue = $a->flag;
    
    next if(($flagValue & 4)); #Unmapped read
    next if(($flagValue & 8)); #Mate unmapped read
    next if(!($flagValue & 2)); #Not a proper pair
    next if(($flagValue & 1024)); #PCR/Optical duplicate
    next if(($flagValue & 256)); #Not primary alignment
    next if(($flagValue & 512)); #Fails vendor checks
    next if(($flagValue & 2048)); #Supp. alignment
    next if($a->qual < $g_pb_qual); # check mapping quality
    
    # NB, we are using the same cutoff for mapping quality and base quality checks.  

    if($g_pb_qual) {
      my $fa = Bio::DB::Bam::AlignWrapper->new($a, $g_sam);
      my $qual = ($fa->qscore)[$p->qpos];
      next if($qual <= $g_pb_qual);
    }

    # get the base at this pos
    my $qbase  = substr($a->qseq, $p->qpos, 1);
    $g_pu_data->register_allele($qbase);
  }
  return 1;
}




1;