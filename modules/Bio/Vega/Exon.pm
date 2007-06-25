package Bio::Vega::Exon;

use strict;
use base 'Bio::EnsEMBL::Exon';

sub hashkey_structure {
    return 'slice_name-start-end-strand-phase-end_phase';
}

# This is to be used by storing mechanism of GeneAdaptor,
# to simplify the loading during comparison.

sub last_db_version {
    my $self = shift @_;

    if(@_) {
        $self->{_last_db_version} = shift @_;
    }
    return $self->{_last_db_version};
}

1;

