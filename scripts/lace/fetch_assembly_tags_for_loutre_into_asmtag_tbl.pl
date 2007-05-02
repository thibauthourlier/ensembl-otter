#!/usr/local/bin/perl -w

### fetch_assembly_tags

use strict;
use Hum::Submission ('prepare_statement');
use Hum::Tracking ('intl_clone_name');
use Hum::AnaStatus::Sequence;

use Bio::Otter::Lace::Defaults;
use Bio::EnsEMBL::DBSQL::CloneAdaptor;
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Vega::AssemblyTag;

use Getopt::Long 'GetOptions';

$| = 1;

my ($dataset, $verbose, $check);

my $help = sub { exec('perldoc', $0) };


Bio::Otter::Lace::Defaults::do_getopt(
									  'ds|dataset=s' => \$dataset,
									  'v|verbose'    => \$verbose,
									  'check'        => \$check,
									  'h|help'       => $help,
									 ) or $help->(); # plus default options

$help->() unless ( $dataset );


my $client    = Bio::Otter::Lace::Defaults::make_Client();
my $dset      = $client->get_DataSet_by_name($dataset);
my $loutre_db = $dset->make_Vega_DBAdaptor;
my $sliceAd   = $loutre_db->get_SliceAdaptor();
my $atagAd    = $loutre_db->get_AssemblyTagAdaptor;
my $atags     = [];

{
  update_assembly_tagged_contig_table();

  # fetch acefile with assembly_tag info of clones
  my $clones = $sliceAd->fetch_all('clone');
  prepare_assembly_tag_data($clones);

  update_database($atags);
}

#--------------------
#    subroutines
#--------------------

sub update_database {

  my ($atags) = @_;

  foreach my $atag ( @$atags ) {
    $atagAd->store($atag);
  }
}

sub update_assembly_tagged_contig_table {

  my $sth = $loutre_db->prepare(qq{
								   SELECT sr.seq_region_id
								   FROM seq_region sr
								   LEFT JOIN assembly_tagged_contig atc
								   ON sr.seq_region_id = atc.seq_region_id
								   WHERE sr.coord_system_id = 5
								   AND atc.seq_region_id IS NULL
								  }
							   );
  $sth->execute;

  my @seqids;

  while ( my $id = $sth->fetchrow ){
    push(@seqids, "($id)");
  }
  $sth->finish;

  unless ( @seqids ){
	warn "All contigs already in assembly_tagged_contigs table.\n\n";
	return;
  }

  if ( $check ){
	print STDERR "Found ", scalar @seqids, " clones to update\n\n";
	exit;
  }

  my $vals = join(',', @seqids);
  my $insert = $loutre_db->prepare(qq{INSERT INTO assembly_tagged_contig (seq_region_id) VALUES $vals});
  eval {
    $insert->execute;
  };
  die $@ if $@;
}

sub prepare_assembly_tag_data {

  my $clones = shift;

  foreach my $cl ( @$clones ) {
    $cl->seq_region_name =~ /(.*)\.(\d+)/;

    my $cln_db_ver  = $2;
    my $acc         = $1;
    my $contig_name = $cl->seq_region_name.".".$cl->start.".".$cl->end;

    my $seq;
    eval {
      $seq = Hum::AnaStatus::Sequence->new_from_accession($acc);
    };

    unless ( $@ ) {
      my $seq_ver =  $seq->sequence_version;
      unless ( $seq_ver ){
        print STDERR "ERROR: $acc has no version in submissions db - cannot update, Investigate!\n";
        next;
      }

	  # only update if the version of loutre contig match that of submissions db
      if ( $cln_db_ver eq $seq_ver ) {

		my $contig   = $sliceAd->fetch_by_region('contig', $contig_name);
		my $seq_region_id = $sliceAd->get_seq_region_id($contig);

		if ( $atagAd->check_seq_region_id_is_transferred($seq_region_id) ){
		  print STDERR "$contig_name (srid $seq_region_id) is already transferred\n";
		  next;
		}

        my $dir      = $seq->analysis_directory;
        my $seq_ver  = $seq->sequence_version;
        my $seq_name = $seq->sequence_name;

        # double check existence of acefile
        if ( -e "$dir/rawdata/$seq_name.humace.ace" ) {
          my $acefile = "$dir/rawdata/$seq_name.humace.ace";
          print STDERR "INFO: updating $acc.$seq_ver: $acefile\n";

          parse_ace($contig, $seq_region_id, $acefile, $loutre_db, $sliceAd); # create a list of atag objs
        } else {
          print STDERR "No update for $acc.$seq_ver: MISSING  $dir/rawdata/$seq_name.humace.ace\n";
        }
      }
    }
  }

  return $atags;
}

sub parse_ace {

  my ($contig, $seq_region_id, $acefile, $loutre_db, $sliceAd)  = @_;

  my $contig_name       = $contig->seq_region_name;
  my $ctg_seq_region_id = $sliceAd->get_seq_region_id($contig);
  my $ctg_strand        = $contig->strand;
  my $ctg_len           = $contig->seq_region_length;

  if ($acefile =~ /\.gz$/) {
    $acefile = "gzip -cd $acefile |";
  }

  open( my $fh, $acefile ) || die "Failed to read $acefile";

  my $info;

  while ( my $line = <$fh> ) {

    $ctg_strand = 1 unless $ctg_strand; # default to 1 if info not available

    my ( $tag_type, $tag_start, $tag_end, $tag_info);

    # omit Type "Oligo"
    if ( $line =~ /^Assembly_tags\s+(-|\"-\"|unsure)\s+(\d+)\s+(\d+)\s+\"(.+)\"/i ) {

      ($1 eq "-" || $1 eq "\"-\"") ? ($tag_type = "Misc") : ($tag_type = $1);

      # convertion for Ensembl/otter_db: starting coord is always smaller, so flip if not so
      #                                  starting coord > end coord means minus strand

      if ( $2 > $3 ) {
        $tag_start = $3;
        $tag_end   = $2;
        if ( $ctg_strand == -1 ) {
          $ctg_strand = 1;
        }
      } elsif ( $2 < $3 ) {
        $tag_start  = $2;
        $tag_end    = $3;
      } elsif ( $2 == $3 ) {
        $tag_start = $tag_end = $2;
        $ctg_strand = 1;        # default setting
      }

      $4 ? ($tag_info = $4) : ($tag_info = "Null");
      $tag_info = trim($tag_info);

      # flag info about unsure tag beyond the length of the contig in contig table of otter db
      # this will be filtered out

      my $skip = 1;
      if ( $tag_type =~ /unsure/i ) {

        if ( $tag_end > $ctg_len ) {
          $skip = 0;
          $info .= "Unsure tag out of bound (loutre contig seq_region_id $ctg_seq_region_id)\n" .
            "\t [tag coord: $tag_end VS contig length: $ctg_len) - SKIPPED\n";
        }
      }

      # filter out unsure tag out of bound
      if (  $skip == 1 ) {
        if ( $verbose ){
          $info .= "flip\n" if $2>$3;
          $info .= "$ctg_seq_region_id : $tag_type : $ctg_strand : $tag_start : $tag_end : $tag_info\n";
        }

        make_atags($contig, $ctg_seq_region_id, $tag_type, $ctg_strand, $tag_start, $tag_end, $tag_info);
      }
    }

    if ( $line =~ /^(Clone_\w+_end)\s+(.+)\s+(\d+)/i ) {

      $tag_type   = $1;
      $tag_start  = $3;
      $tag_end    = $3;         # set end value to start value as no end value present
      $tag_info   = $2;
      $ctg_strand = 1;
      $tag_info   =~ s/\"//g;
      $tag_info   = trim($tag_info);
	
      # replace internal Sanger name (= $tag_info) with international clone name
      my $name = $tag_info." (Sanger name) ";
      $tag_info = Hum::Tracking::intl_clone_name($tag_info); # info in Oracle Trackings db
      $name .= $tag_info." (intl name)";

      $info .= "$ctg_seq_region_id : $tag_type : $ctg_strand : $tag_start : $tag_end : $tag_info --- [$name]\n" if $verbose;
      make_atags($contig, $ctg_seq_region_id, $tag_type, $ctg_strand, $tag_start, $tag_end, $tag_info);
    }
  }

  # log/info message
  if ( $info ) {
    $info = "\n".$contig_name." => ".$acefile."\n".$info;
    print $info if $verbose;
  } else {
    print "\nNOTE: ".$contig_name." => ".$acefile." (no assembly_tag data)\n" if $verbose;
  }
}

sub trim {
  my $st = shift;
  $st =~ s/\\n/ /g;
  $st =~ s/\s{1,}/ /g;
  return $st;
}

sub make_atags {
  my ($contig, $ctg_seq_region_id, $tag_type, $ctg_strand, $tag_start, $tag_end, $tag_info) = @_;

  my $atag = Bio::Vega::AssemblyTag->new();

#  $atag->seq_region_id($ctg_seq_region_id); # handled by atag adaptor
  $atag->seq_region_start($tag_start);
  $atag->seq_region_end($tag_end);
  $atag->seq_region_strand($ctg_strand);
  $atag->tag_type($tag_type);
  $atag->tag_info($tag_info);
  $atag->slice($contig);

  push(@$atags, $atag);
}

__END__


=head1 NAME - fetch_assembly_tags

=head1 SYNOPSIS

Running the script

Eg, fetch_assembly_tags B<-dataset> zebrafish [-verbose][-check]

=head1 DESCRIPTION

There are assembly_tags info for Sanger clones submitted to EMBL. They are stored in "submissions" database and are available as acefiles, eg, /nfs/disk100/humpub/analysis/projects/Chr_20/yR31BE7/20001221/rawdata/yR31BE7.humace.ace.

The Assembly_tags info is shown in AceDB under the Assembly_tags tag of a Sequence object and is stored in B<assembly_tag> table of an otter db.

This script populates and updates the otter B<assembly_tag> and B<assemlby_tagged_clone> tables, respectively.
The latter table is populated by "INSERT INTO assembly_tagged_clone (clone_id) SELECT clone_id FROM clone;"
before hand, where all clones have the transferred column with value initially set to "no".
For clones which have assembly_tag data, it will be updated to "yes".

The B<assembly_tagged_clone> table allows quick look up of clones that have assembly_tag info.

Assembly_tag info in the otter DB is dumped out in EMBL format via the script B<emblDump> in the humscripts directory.
(To check out: cvs -d /nfs/humace2/CVS_master checkout humscripts)

=head1 AUTHOR

Chao-Kung Chen B<email> ck1@sanger.ac.uk
