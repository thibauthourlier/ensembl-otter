#!/usr/bin/env perl

### star_search.pl

use strict;
use warnings;
use Getopt::Long qw{ GetOptions };
use File::Temp qw{ tmpnam };
use DBI;

{
    my $usage       = sub { exec('perldoc', $0) };
    my $genome_star = '';
    my $fasta_input = '';
    my $analysis_logic_name = '';
    my $run_flag    = 0;

    my ($db_name, $db_host, $db_port, $db_user, $db_pass);
    my @command_line = @ARGV;
    GetOptions(

        # DB connection parameters chosen to be compatible with EnsEMBL pipeline script convention
        'dbname=s' => \$db_name,
        'dbhost=s' => \$db_host,
        'dbport=s' => \$db_port,
        'dbuser=s' => \$db_user,
        'dbpass=s' => \$db_pass,

        'analysis=s'    => \$analysis_logic_name,
        'genome=s' => \$genome_star,
        'fasta=s'  => \$fasta_input,
        'run!'     => \$run_flag,
        'h|help!'  => $usage,
    ) or $usage->();
    $usage->() unless $genome_star and $fasta_input and $analysis_logic_name;

    my $dbh = DBI->connect("DBI:mysql:database=$db_name;host=$db_host;port=$db_port",
        $db_user, $db_pass, {RaiseError => 1, AutoCommit => 0});

    my $lsf_mem    = 30_000;
    my $n_threads  = 4;
    my $intron_max = 1e5;

    if ($run_flag) {
        my $cmd = [
            'STARlong',
            '--runThreadN'                    => $n_threads,
            '--genomeDir'                     => $genome_star,
            '--outTmpDir'                     => scalar(tmpnam()),
            '--readFilesIn'                   => $fasta_input,
            '--alignIntronMax'                => $intron_max,
            qw{
                --outStd                         SAM
                --outFilterMultimapScoreRange    100
                --outFilterScoreMinOverLread     0
                --outFilterMatchNminOverLread    0.66
                --outFilterMismatchNmax          1000
                --outSAMattributes               jM
                --winAnchorMultimapNmax          200
                --seedSearchStartLmax            12
                --alignWindowsPerReadNmax        30000
                --seedPerReadNmax                100000
                --seedPerWindowNmax              1000
                --alignTranscriptsPerReadNmax    100000
                --alignTranscriptsPerWindowNmax  10000
            },
        ];
        fetch_analysis_id($dbh, $analysis_logic_name);
        fetch_chr_seq_region_ids($dbh, $genome_star);
        # run_and_store($dbh, $cmd);
        ### Update meta_coord table!
    }
    else {
        my $star_v = "STAR_2.4.2a";
        $ENV{'PATH'} = "/software/svi/bin/$star_v/bin/Linux_x86_64:$ENV{PATH}";
        my @bsub = (
            'bsub',
            -q => 'normal',
            -n => $n_threads,
            -M => $lsf_mem,
            -R => "select[mem>$lsf_mem] rusage[mem=$lsf_mem] span[hosts=1]",
            -o => "$fasta_input.out",
            -e => "$fasta_input.err",
            $0, '-run', @command_line,
        );

        # print STDERR "@bsub\n";
        system(@bsub);
    }

    $dbh->disconnect;
}

sub run_and_store {
    my ($dbh, $cmd) = @_;

    open(my $star, '-|', @$cmd) or die "Error launching '@$cmd'; $!";
    parse_and_store($dbh, $star);
    close($star) or die "Error running '@$cmd'; exit $?";
}

{
    my $chr_to_seq_region_id = {};
    my @coord_system_id;

    sub fetch_chr_seq_region_ids {
        my ($dbh, $star_genome_dir) = @_;

        my $chr_names_file = "$star_genome_dir/chrName.txt";
        open(my $chr_names, $chr_names_file) or die "Failed to open chr names file '$chr_names_file'; $!";
        my $sth = $dbh->prepare(q{ SELECT seq_region_id, coord_system_id FROM seq_region WHERE name = ? });
        my %uniq_cs_id;
        while (my $chr = <$chr_names>) {
            chomp($chr);
            $sth->execute($chr);
            my @ids;
            while (my ($seq_region_id, $coord_system_id) = $sth->fetchrow) {
                $uniq_cs_id{$coord_system_id} = 1;
                push(@ids, $seq_region_id);
            }
            if (@ids == 1) {
                $chr_to_seq_region_id->{$chr} = $ids[0];
            }
            else {
                my $id_str = join(", ", @ids);
                die "Expecting one seq_region to match '$chr' but got: [$id_str]";
            }
        }
        close($chr_names) or die "Error reading file '$chr_names_file'; $!";
        @coord_system_id = keys(%uniq_cs_id);
    }

    sub chr_seq_region_ids {
        return $chr_to_seq_region_id;
    }
}

{
    my $analysis_id;

    sub fetch_analysis_id {
        my ($dbh, $analysis_logic_name) = @_;

        my $sth = $dbh->prepare(q{ SELECT analysis_id FROM analysis WHERE logic_name = ? });
        $sth->execute($analysis_logic_name);
        ($analysis_id) = $sth->fetchrow;
        $sth->finish;
        unless ($analysis_id) {
            die "Failed to fetch analysis_id for '$analysis_logic_name'";
        }
    }

    sub analysis_id {
        return $analysis_id;
    }
}

# CREATE TABLE dna_spliced_align_feature (
#
#   dna_spliced_align_feature_id  INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
#   seq_region_id                 INT(10) UNSIGNED NOT NULL,
#   seq_region_start              INT(10) UNSIGNED NOT NULL,
#   seq_region_end                INT(10) UNSIGNED NOT NULL,
#   seq_region_strand             TINYINT(1) NOT NULL,
#   hit_start                     INT NOT NULL,
#   hit_end                       INT NOT NULL,
#   hit_strand                    TINYINT(1) NOT NULL,
#   hit_name                      VARCHAR(40) NOT NULL,
#   analysis_id                   SMALLINT UNSIGNED NOT NULL,
#   score                         DOUBLE,
#   evalue                        DOUBLE,
#   perc_ident                    FLOAT,
#   alignment_type                TEXT,
#   alignment_string              ENUM('vulgar_exonerate_components'),
#   external_db_id                INTEGER UNSIGNED,
#   hcoverage                     DOUBLE,
#   external_data                 TEXT,
#
#   PRIMARY KEY (dna_spliced_align_feature_id),
#   KEY seq_region_idx (seq_region_id, analysis_id, seq_region_start, score),
#   KEY seq_region_idx_2 (seq_region_id, seq_region_start),
#   KEY hit_idx (hit_name),
#   KEY analysis_idx (analysis_id),
#   KEY external_db_idx (external_db_id)
#
# ) ENGINE=InnoDB;

{
    my %sth_n;

    sub get_sth_for_n_rows {
        my ($dbh, $n_rows) = @_;

        my $sth;
        unless ($sth = $sth_n{$n_rows}) {
            my $sql = q{ INSERT INTO dna_spliced_align_feature (
                seq_region_id, seq_region_start, seq_region_end, seq_region_strand
              , hit_name,             hit_start,        hit_end,        hit_strand
              , analysis_id, score, perc_ident, alignment_type, alignment_string
              , hcoverage
              ) VALUES };
            my $values = q{(?,?,?,?,?,?,?,?,?,?,?,'vulgar_exonerate_components',?,?,?),} x $n_rows;
            chop($values);
            $sth = $sth_n{$n_rows} = $dbh->prepare($sql . $values);
        }
        return $sth;
    }

    sub store_vulgar_features {
        my ($dbh, $data) = @_;

        my $sth = get_sth_for_n_rows($dbh, @$data / 13);
        $sth->execute(@$data);
        $dbh->commit;
    }
}

sub parse_and_store {
    my ($dbh, $star_fh) = @_;

    my $chr_to_seq_region_id = chr_seq_region_ids();
    my $analysis_id = analysis_id();

    my $data = [];
    my $hit_n = 0;
    my $chunk_size = 1000;
    while (<$star_fh>) {
        next if /^@/;
        $hit_n++;
        chomp;
        my ($hit_name
          , $binary_flags
          , $chr_name
          , $chr_start
          , $map_quality
          , $cigar
          , $rnext
          , $pnext
          , $tlen
          , $hit_sequence
          , $hit_quality
          , @optional_flags
        ) = split /\t/, $_;

        my $chr_db_id = $chr_to_seq_region_id->{$chr_name} or die "No seq_region_id for chr '$chr_name'";

        # Parse the optional flags
        my ($chr_strand, $score, $edit_distance);
        foreach my $attr (@optional_flags) {
            my ($FG, $type, $value) = split /:/, $attr;
            if ($FG eq 'jM') {
                my @splices = $value =~ /,(-?\d+)/g;
                my $strand_vote = 0;
                foreach my $n (@splices) {
                    next unless $n > 0; # Value of 0 signifies non-consensus splice; -1 no splice sites.
                    # Odd numbers are forward strand splice sites, even are reverse
                    $strand_vote += $n % 2 ? 1 : -1;
                }

                if ($strand_vote == 0) {
                    # No splice info, so we don't know which genomic strand we're on
                    $chr_strand = 0;
                }
                elsif ($strand_vote > 1) {
                    $chr_strand = 1;
                }
                else {
                    $chr_strand = -1;
                }
            }
            elsif ($FG eq 'AS') {
                $score = $value;
            }
            elsif ($FG eq 'NM') {
                $edit_distance = $value;
            }
        }

        my $flipped_hit = $binary_flags & 16;
        my ($hit_strand);
        if ($chr_strand == 0) {
            # No information about chr strand from splice sites
            $hit_strand = 1;
            $chr_strand = $flipped_hit ? -1 : 1;
        }
        else {
            # A flipped hit to a reverse strand gene is a match to the forward strand of the hit
            $hit_strand = $chr_strand * ($flipped_hit ? -1 : 1);
        }

        my @cigar_fields = $cigar =~ /(\d+)(\D)/g;
        if ($chr_strand == -1) {
            # Reverse the CIGAR, keeping the pairs of OP + INT together.
            my $limit = @cigar_fields - 2;  # Last pair would be a no-op
            for (my $i = 0; $i < $limit; $i += 2) {
                splice(@cigar_fields, $i, 0, splice(@cigar_fields, -2, 2));
            }
        }

        my @vulgar_fields;
        my $hit_start      = 1;
        my $hit_aln_length = 0;
        my $chr_aln_length = 0;
        my $hit_pad_length = 0; # Needed for percent identity
        my $hit_del_length = 0; # Needed for hit coverage
        my $hit_length = length($hit_sequence);
        for (my $i = 0; $i < @cigar_fields; $i += 2) {
            my ($len, $op) = @cigar_fields[ $i, $i + 1 ];
            if ($op eq 'M') {
                push @vulgar_fields, 'M', $len, $len;
                $chr_aln_length += $len;
                $hit_aln_length += $len;
            }
            elsif ($op eq 'N') {
                push @vulgar_fields, 5, 0, 2, 'I', 0, $len - 4, 3, 0, 2;
                $chr_aln_length += $len;
            }
            elsif ($op eq 'I') {
                push @vulgar_fields, 'G', $len, 0;
                $hit_aln_length += $len;
                $hit_del_length += $len;    # Will not contribute to hcoverage
            }
            elsif ($op eq 'D') {
                push @vulgar_fields, 'G', 0, $len;
                $chr_aln_length += $len;
                $hit_pad_length += $len;    # Will add to span of alignment
            }
            elsif ($op eq 'S') {
                # Soft clipping - clipped sequence is present in SAM
                if ($i == 0) {
                    $hit_start += $len;
                }
            }
            elsif ($op eq 'H') {
                # Hard clipping - clipped sequence not present in SAM
                $hit_length += $len;
            }
            else {
                die "Unexpected SAM CIGAR element: '$len$op'";
            }
        }
        my $hit_end = $hit_start + $hit_aln_length - 1;
        my $chr_end = $chr_start + $chr_aln_length - 1;

        # The total span of the gapped alignment (not including introns) minus the edit distance
        my $percent_identity = sprintf "%.3f", 100 * (1 - ($edit_distance / ($hit_pad_length + $hit_aln_length)));
        
        my $hit_coverage     = sprintf "%.3f", 100 * (($hit_aln_length - $hit_del_length) / $hit_length);

        if ($hit_strand == -1) {
            my $new_hit_start = $hit_length - $hit_end   + 1;
            $hit_end          = $hit_length - $hit_start + 1;
            $hit_start = $new_hit_start;
        }

        push(@$data,
            $chr_db_id, $chr_start, $chr_end, $chr_strand,
            $hit_name, $hit_start, $hit_end, $hit_start,
            $analysis_id, $score, $percent_identity, "@vulgar_fields", $hit_coverage);

        # my $pattern = "%18s  %-s\n";
        # print STDERR "\n";
        # printf STDERR $pattern, 'seq_region_start',  $offset + $chr_start;
        # printf STDERR $pattern, 'seq_region_end',    $offset + $chr_end;
        # printf STDERR $pattern, 'seq_region_strand', $chr_strand;
        # printf STDERR $pattern, 'hit_start',         $hit_start;
        # printf STDERR $pattern, 'hit_end',           $hit_end;
        # printf STDERR $pattern, 'hit_strand',        $hit_strand;
        # printf STDERR $pattern, 'hit_name',          $hit_name;
        # printf STDERR $pattern, 'perc_ident',        $percent_identity;
        # printf STDERR $pattern, 'hcoverage',         $hit_coverage;
        # printf STDERR $pattern, 'alignment_string',  "@vulgar_fields";

        # print STDERR join("\t", $chr_name, $chr_strand, $hit_name, $hit_start, $hit_end, $hit_strand, "@vulgar_fields"), "\n";
        
        unless ($hit_n % $chunk_size) {
            store_vulgar_features($dbh, $data);
            $data = [];
        }
    }
    if (@$data) {
        store_vulgar_features($dbh, $data);
        $data = [];
    }
}


__END__

=head1 NAME - star_search.pl

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

