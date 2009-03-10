#!/usr/bin/env perl

use warnings;


### parse all EST/cDNA submitted to EMBL - based on files prepared by Hans
### run script on machine: cbi3
### typical run: perl ~/bin/embl/parse_EST_cDNA_stats.pl -db mushroom_200610 -host cbi3 -user genero

use strict;
use DBI;
use Getopt::Long;

my ($dbname, $dbuser, $dbhost);
my $dbport = 3306;
my $dbpass = '';

GetOptions('db=s'   => \$dbname,
		   'user=s' => \$dbuser,
		   'host=s' => \$dbhost,
		  );

my $EST_libID_taxID  = {};
my $cDNA_libID_taxID = {};
my $EST_tax_id       = {};
my $cDNA_tax_id      = {};

my $est     = 'est';
my $std     = 'std';

# parse data from Hans
foreach ( $est, $std ){
  parse_est_cdna_files($_);
}

my ($EST_lib_IDS, $cDNA_lib_IDS, $EST_taxIDs, $cDNA_taxIDs, $STAT);

my $dbh = DBI->connect("DBI:mysql:$dbname:$dbhost:$dbport", $dbuser, $dbpass, {RaiseError => 1}
					  ) || die "cannot connect to $dbname, $DBI::errstr";

my ($est_lib_stat, $est_tax_stat, $cdna_lib_stat, $cdna_tax_stat);
my $i = 0;

foreach ($EST_libID_taxID, $EST_taxIDs, $cDNA_libID_taxID, $cDNA_taxIDs) {
  ++$i;
  if ( $i == 1 ){
  	$EST_lib_IDS  = join(',', keys %$EST_libID_taxID);
	get_stats_from_mushroom_db('EST_lib', $EST_lib_IDS, $est_lib_stat);
  }
  elsif ( $i == 2 ){
	$EST_taxIDs = join(',', keys %$EST_tax_id);
	get_stats_from_mushroom_db('EST_tax', $EST_taxIDs, $est_tax_stat) if $EST_taxIDs;
  }
  elsif ( $i == 3 ){
	$cDNA_lib_IDS = join(',', keys %$cDNA_libID_taxID);
	get_stats_from_mushroom_db('cDNA_lib', $cDNA_lib_IDS, $cdna_lib_stat) if $cDNA_lib_IDS;
  }
  else {
	$cDNA_taxIDs = join(',', keys %$cDNA_tax_id);
	get_stats_from_mushroom_db('cDNA_tax', $cDNA_taxIDs, $cdna_tax_stat) if $cDNA_taxIDs;
  }
}

# output HTML
my $html =<<HTML;
<!--#set var="title" value="The Sanger Institute EST/cDNA sequence submission and clustering" -->
<!--#include virtual="/perl/header"-->

<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN">
<html>
  <head>
    <title>The Sanger Institute EST/cDNA sequence submission and clustering</title>
	<link rel="stylesheet" type="text/css" href="css/est_sequencing.css">
  </head>

  <body>
    <h2>The Sanger Institute EST/cDNA sequence submission and clustering</h2>


<div id='content'><a href='mailto:anacode-people\@sanger.ac.uk'>The Finished Sequence Analysis group</a> of the Sanger Institute provides helps submitting sequenced ESTs/cDNAs generated by the Sanger Institute sequencing projects to EMBL nucleotide database.</div>
<div id='secL2'>A summary of current status of ESTs/cDNAs submitted by the group as well as others at Sanger (data prepared: Oct.2006)</div>
HTML


my $footer =<<FOOTER;
<!--#include virtual="/perl/footer"-->
  </body>
</html>
FOOTER


my $table = make_tables($STAT);
print $html, $table, $footer;

sub make_tables {

  my $searchables = {
					 "Danio rerio" => "http://wwwdev.sanger.ac.uk/cgi-bin/Projects/D_rerio/ESTs/sanger_zfish_est_db_search"
					};

  my $STAT = shift;

  my $tbl =<<TABLE;
<div id='secL3'>NA: not applicable.<br>Species name in darkred is accompanied by a link to a searchable EST database.<br>
Where a libraryname is not available, the NCBI taxonomy id is shown instead of unilib id.<br>
Figures are updated in synch with each release of EMBL nucleotide database.
 </div>
<div id='tbl'><table rules=all cellpadding=4 bgcolor='#F7F7F7'>
  <tr>
    <td id='cell1'><b>Species</b></td>
    <td><b><span id='unilib'>unilib_id/</span><br><span id='taxon'>ncbi_tax_id</span></b></td>
    <td><b>Library name</b></td>
    <td><b>EST seqs_to_date</b></td>
	<td><b>cDNA seqs_to_date</b></td>
  </tr>
TABLE

  foreach my $os ( sort keys %$STAT ){

	# links to searchable EST db if available
	my $OS;
	(exists $searchables->{$os}) ? ($OS = qq{<a href=$searchables->{$os}><span id='estdb'>$os</span></a>}) : ($OS = $os);

	# add one for total row
	my $rowspan ;
	( scalar @{$STAT->{$os}} != 1) ? ($rowspan = scalar @{$STAT->{$os}} + 1) : ($rowspan = scalar @{$STAT->{$os}});

	my $current_row = 0;
	my ($est_sum, $cdna_sum);

	foreach my $data ( @{$STAT->{$os}} ){

	  ++$current_row;
	  my ($dataclass, $commonName, $ID, $libname, $seqs_to_date) = @$data;

	  my $idval;
	  ($libname eq "NA") ? ($idval = qq{<span id='taxon'>$ID</span>}) : ($idval = $ID);

	  # est or cdna submission
	  my ($est_sub, $cdna_sub);
	  if ($dataclass eq "EST" ){
		$est_sum += $est_sub  = $seqs_to_date;
		$cdna_sub = "-";
	  }
	  else {
		$est_sub  = "-";
		$cdna_sum += $cdna_sub = $seqs_to_date;
	  }

	  if ( $current_row == 1 ){
		$tbl .= "<tr><td id='cell1' rowspan=\"$rowspan\"><i>$OS</i><br>($commonName)</td>" .		
		        "<td>$idval</td>" .
				"<td>$libname</td>".
			    "<td>$est_sub</td>".
		        "<td>$cdna_sub</td></tr>";
	  }
	  else {
		$tbl .= "<tr><td>$idval</td>".
		        "<td>$libname</td>".
	            "<td>$est_sub</td>".	
		        "<td>$cdna_sub</td></tr>";
	  }
	}
	if ( $rowspan != 1 ){

	  $est_sum  = "-" unless $est_sum;
	  $cdna_sum = "-" unless $cdna_sum;

	  $tbl .= "<tr><td colspan=2><b>Total</b></td><td><b>$est_sum</b></td><td><b>$cdna_sum</b></td></tr>";
	}
  }

  $tbl .= "</table></div>";
  return $tbl;
}

sub get_stats_from_mushroom_db {

  my ($dataclass, $id_str, $stat) = @_;

  if ( $dataclass eq "EST_lib" or $dataclass eq "cDNA_lib" ){

	my $qry_unilib = $dbh->prepare(qq{
									  SELECT organism, unilib_id, library_name, sequences_to_date
									  FROM unilib
									  WHERE unilib_id in ($id_str)
									  ORDER BY organism
									 });
	$qry_unilib->execute;

	while ( my $h = $qry_unilib->fetchrow_hashref ){
	  my $os           = $h->{organism};
	  my $commonName   = binaryName2commonName($os);
	  my $unilibID     = $h->{unilib_id};
	  my $libname      = $h->{library_name};
	  my $seqs_to_date = $h->{sequences_to_date};

	  # est or cdna
	  $dataclass =~ s/_lib//;

	  push(@{$STAT->{$os}}, [$dataclass, $commonName, $unilibID, $libname, $seqs_to_date]);
	  #printf("LIB %s\t%s\t%d\t%s\t%d\n", $os, $commonName, $unilibID, $libname, $seqs_to_date);
	}
  }
  else {

	my $tax_id_os = {};
	my $tax_id_name  = {};

	my $qry_taxID = $dbh->prepare(qq{
									 SELECT ncbi_tax_id, name
									 FROM taxonomy_name
									 WHERE ncbi_tax_id in ($id_str)
									 AND name_type = 'scientific name'
									});

	$qry_taxID->execute;

	while ( my ($id, $os) = $qry_taxID->fetchrow ){

	  my $commonName   = binaryName2commonName($os);
	  my $seqs_to_date = $cDNA_tax_id->{$id};

	  # est or cdna
	  $dataclass =~ s/_lib//;

	  push(@{$STAT->{$os}}, [$dataclass, $commonName, $id, "NA", $seqs_to_date]) unless $STAT->{$os};
	  #printf("TAX %s\t%s\t%d\t%s\t%d\n", $os, $tax_id_name->{$id},  $id, "-", $seqs_to_date );
	}
  }
}

sub binaryName2commonName {

  my $binaryName = shift;
  my $commonName;
  my $qry_name = $dbh->prepare(qq{
								   SELECT name, name_type
								   FROM taxonomy_name
								   WHERE ncbi_tax_id = (SELECT ncbi_tax_id
														FROM taxonomy_name
														WHERE  name = '$binaryName')								
								  });

  $qry_name->execute;

  while ( my $h = $qry_name->fetchrow_hashref ){
	if ( $h->{name_type} eq 'genbank common name'){
	  $commonName = $h->{name};
	  last;
	}
	elsif ( $h->{name_type} eq 'common name'){
	  $commonName = $h->{name};
	}
  }
  $commonName ? return $commonName : return "NA";
}

sub parse_est_cdna_files {

  my $file = shift;

  # std file format
  # AJ404496.1      genomic DNA     STD     ENV     129598  0       RL   Cox C.J., Cancer Research, Sanger Centre, 

  # est file format
  # AJ973486.1      mRNA    EST     HUM     9606    39316   RL   Eades T.L., Wellcome Trust Genome Camp

  # est-lib file format (unilib_id, number_accs)
  #36869   29927

  if ( -e $file ) {
	open( my $f, "$file") or die $!;

	while (<$f>) {
	  my @fds = split(/\t/, $_);
	
	  my $moltype   = $fds[1];
	  my $dataclass = $fds[2];
	  my $tax_id    = $fds[4];
	  my $unilib_id = $fds[5];
	  if ( $moltype eq "mRNA" and $dataclass eq "EST" ) {
		if ( $unilib_id != 0 ) {
		  $EST_libID_taxID->{$unilib_id} = $tax_id;
		}
		else {
		  $EST_tax_id->{$tax_id}++;
		}
	  }
	  elsif ( $moltype eq "mRNA" and $dataclass eq "STD" ) {
		if ( $unilib_id != 0 ) {
		  $cDNA_libID_taxID->{$unilib_id} = $tax_id;
		}
		else {
		  $cDNA_tax_id->{$tax_id}++;
		}
	  }
	}
  }
}

__END__

MOLECULAR TYPE
	* genomic dna
    * genomic rna
    * mrna 
    * other dna
    * other rna 
    * pre-rna
    * rrna
    * unassigned dna
    * unassigned rna
    * scrna
    * snorna
    * snrna
    * trna

DATA CLASS
	* ANN: Constructed sequence with annotation
    * CON: Constructed sequence
    * EST: Expressed Sequence Tag
    * GSS: Genome Survey Sequence
    * HTC: High Throughput cDNA sequencing
    * HTG: High Throughput Genome sequencing
    * MGA: Mass Genome Annotation
    * PAT: Patent
    * SET: Project set (EMBL WGS Masters only)
    * STD: Standard
    * STS: Sequence Tagged Site
    * TPA: Third Party Annotation
    * WGS: Whole Genome Shotgun

DIVISION
    * ENV: Environmental Samples
    * FUN: Fungi
    * HUM: Human
    * INV: Invertebrates
    * MAM: Other Mammals
    * MUS: Mus musculus
    * PHG: Bacteriophage
    * PLN: Plants
    * PRO: Prokaryotes
    * ROD: Rodents
    * SYN: Synthetic
    * UNC: Unclassified
    * VRL: Viruses
    * VRT: Other Vertebrates
