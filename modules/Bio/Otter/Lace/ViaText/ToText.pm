# Generate text representation from new EnsEMBL objects

package Bio::Otter::Lace::ViaText::ToText;

use strict;
use warnings;

use Bio::Otter::Lace::ViaText ('%OrderOfOptions');

use base ('Exporter');
our @EXPORT    = ();
our @EXPORT_OK = qw( &GenerateSimpleFeatures &GenerateAlignFeatures &GenerateRepeatFeatures
                     &GenerateMarkerFeatures &GenerateDitagFeatureGroups
                     &GeneratePredictionTranscripts &GenerateGenes );

### The following generators create ViaText representation of lists of objects: ###

sub GenerateSimpleFeatures {
    my ($sfs, $analysis_name) = @_;

    my @sf_optnames = @{ $OrderOfOptions{SimpleFeature} };

    my $output_string = '';

    foreach my $sf (@$sfs) {
            # output a SimpleFeature line
        my @sf_optvalues = ('SimpleFeature');
        for my $opt (@sf_optnames) {
            push @sf_optvalues, $sf->$opt();
        }

        if(!$analysis_name) {
            push @sf_optvalues, $sf->analysis()->logic_name();
        }

        $output_string .= join("\t", @sf_optvalues)."\n";
    }

    return $output_string;
}

sub GenerateAlignFeatures {
    my ($afs, $analysis_name, $sdbc) = @_;

    require 'Bio::Otter::DBSQL::SimpleBindingAdaptor';
    require 'Bio::Otter::HitDescription';

        # Put the names into the hit_description hash:
    my %hd_hash = ();
    foreach my $af (@$afs) {
        $hd_hash{$af->hseqname()} = '';
    }

        # Fetch the hit descriptions from the pipeline
    my $hd_adaptor = Bio::Otter::DBSQL::SimpleBindingAdaptor->new( $sdbc );
    $hd_adaptor->fetch_into_hash(
        'hit_description',
        'hit_name',
        { qw(
            hit_length _hit_length
            hit_description _description
            hit_taxon _taxon_id
            hit_db _db_name
        )},
        'Bio::Otter::HitDescription',
        \%hd_hash,
    );

    my @af_optnames = @{ $OrderOfOptions{AlignFeature} };
    my @hd_optnames = @{ $OrderOfOptions{HitDescription} };

    my $output_string = '';

        # Stringify only the simple fields:
    my %hit_seen = (); # collect the seen hit names here
    foreach my $af (@$afs) {
        my $hit_name = $af->hseqname();
        my $hd = $hd_hash{$hit_name};
        if($hd) {
            if(!exists($hit_seen{$hit_name})) { # a new one

                    # output a HitDescription line
                my @hd_optvalues = ('HitDescription', $hit_name);
                for my $opt (@hd_optnames) {
                    push @hd_optvalues, $hd->$opt();
                }
                $output_string .= join("\t", @hd_optvalues)."\n";

                $hit_seen{$hit_name} = 1;
            }
        }

            # output an AlignFeature line
        my @af_optvalues = ('AlignFeature');
        for my $opt (@af_optnames) {
            push @af_optvalues, $af->$opt();
        }
        push @af_optvalues, $af->cigar_string();

        if(!$analysis_name) {
            push @af_optvalues, $af->analysis()->logic_name();
        }

        $output_string .= join("\t", @af_optvalues)."\n";
    }

    return $output_string;
}

sub GenerateRepeatFeatures {
    my ($rfs, $analysis_name) = @_;

    my @rf_optnames = @{ $OrderOfOptions{RepeatFeature} };
    my @rc_optnames = @{ $OrderOfOptions{RepeatConsensus} };

    my $output_string = '';

        # Stringify only the simple fields:
    my %rc_seen = (); # collect the seen repeat consensus ids here
    foreach my $rf (@$rfs) {
        my $rc = $rf->repeat_consensus(); # object
        my $rc_id = $rc->dbID();

        if(!exists($rc_seen{$rc_id})) { # a new one

                # output a repeat consensus line
            my @rc_optvalues = ('RepeatConsensus');
            for my $opt (@rc_optnames) {
                push @rc_optvalues, $rc->$opt() || 0;
            }
            $output_string .= join("\t", @rc_optvalues)."\n";

            $rc_seen{$rc_id} = 1;
        }

            # output a repeat feature line
        my @rf_optvalues = ('RepeatFeature');
        for my $opt (@rf_optnames) {
            push @rf_optvalues, $rf->$opt();
        }
        push @rf_optvalues, $rc_id;

        if(!$analysis_name) {
            push @rf_optvalues, $rf->analysis()->logic_name();
        }

        $output_string .= join("\t", @rf_optvalues)."\n";
    }

    return $output_string;
}

sub GenerateMarkerFeatures {
    my ($mfs, $analysis_name) = @_;

    my @mf_optnames = @{ $OrderOfOptions{MarkerFeature} };
    my @mo_optnames = @{ $OrderOfOptions{MarkerObject} };
    my @ms_optnames = @{ $OrderOfOptions{MarkerSynonym} };

    my $output_string = '';

        # Stringify only the simple fields:
    my %mo_seen = (); # collect the seen marker object ids here
    foreach my $mf (@$mfs) {
        my $mo = $mf->marker(); # object
        my $mo_id = $mo->dbID();

        if(!exists($mo_seen{$mo_id})) { # a new one

                # output a marker object line:
            my @mo_optvalues = ('MarkerObject');
            for my $opt (@mo_optnames) {
                push @mo_optvalues, $mo->$opt() || 0;
            }
            $output_string .= join("\t", @mo_optvalues)."\n";

                # output all marker synonym lines:
            my $mss = $mo->get_all_MarkerSynonyms();
            for my $ms (@$mss) {
                my @ms_optvalues = ('MarkerSynonym');
                for my $opt (@ms_optnames) {
                    push @ms_optvalues, $ms->$opt() || 0;
                }
                push @ms_optvalues, $mo_id;
                $output_string .= join("\t", @ms_optvalues)."\n";
            }

            $mo_seen{$mo_id} = 1;
        }

            # output a marker feature line:
        my @mf_optvalues = ('MarkerFeature');
        for my $opt (@mf_optnames) {
            push @mf_optvalues, $mf->$opt();
        }
        push @mf_optvalues, $mo_id;

        if(!$analysis_name) {
            push @mf_optvalues, $mf->analysis()->logic_name();
        }

        $output_string .= join("\t", @mf_optvalues)."\n";
    }

    return $output_string;
}

sub GenerateDitagFeatureGroups {
    my ($dfs, $analysis_name) = @_;

    my @df_optnames = @{ $OrderOfOptions{DitagFeature} };
    my @do_optnames = @{ $OrderOfOptions{DitagObject} };

    my $output_string = '';

        # Stringify only the simple fields:
    my %do_seen = (); # collect the seen ditag object ids here

    foreach my $df (@$dfs) {

        my $do = $df->ditag(); # object
        my $do_id = $do->dbID();

        if(!exists($do_seen{$do_id})) { # a new one

                # output a ditag object line:
            my @do_optvalues = ('DitagObject');
            for my $opt (@do_optnames) {
                push @do_optvalues, $do->$opt() || 0;
            }
            $output_string .= join("\t", @do_optvalues)."\n";

            $do_seen{$do_id}++;
        }

            # output a ditag feature line:
        my @df_optvalues = ('DitagFeature');
        for my $opt (@df_optnames) {
            push @df_optvalues, $df->$opt();
        }
        push @df_optvalues, $do_id;

        if(!$analysis_name) {
            push @df_optvalues, $df->analysis()->logic_name();
        }

        $output_string .= join("\t", @df_optvalues)."\n";
    }

    return $output_string;
}

sub GeneratePredictionTranscripts {
    my ($pts, $analysis_name) = @_;

    my @pt_optnames = @{ $OrderOfOptions{PredictionTranscript} };
    my @pe_optnames = @{ $OrderOfOptions{PredictionExon} };

    my $output_string = '';

    foreach my $pt (@$pts) {

            # output a predictioin transcipt line:
        my @pt_optvalues = ('PredictionTranscript');
        for my $opt (@pt_optnames) {
            push @pt_optvalues, $pt->$opt();
        }
        if(!$analysis_name) {
            push @pt_optvalues, $pt->analysis()->logic_name();
        }
        $output_string .= join("\t", @pt_optvalues)."\n";

        my $pt_id = $pt->dbID();

        for my $pe (@{$pt->get_all_Exons}) {
                # output an exon line
            my @pe_optvalues = ('PredictionExon');
            for my $opt (@pe_optnames) {
                push @pe_optvalues, $pe->$opt || 0;
            }
            push @pe_optvalues, $pt_id;

            $output_string .= join("\t", @pe_optvalues)."\n";
        }
    }

    return $output_string;
}

sub GenerateGenes {
    my ($genes, $allowed_transcript_analyses_hash, $allowed_translation_xref_db_hash) = @_;

    require 'Bio::Otter::ToXML';

    my $output_string = '';

    foreach my $gene (@$genes) {
        $output_string .= $gene->toXMLstring(
            $allowed_transcript_analyses_hash,
            $allowed_translation_xref_db_hash
        );
    }

    return $output_string;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::ViaText::ToText

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

