package Bio::Otter::Lace::OnTheFly;

## Moose provides these, but webpublish doesn't know that!
##
use strict;
use warnings;
##

use namespace::autoclean;
use Moose::Role;

requires 'build_target_seq';
requires 'build_aligner';

use Bio::Otter::Lace::OnTheFly::QueryValidator;
use Bio::Otter::Lace::OnTheFly::TargetSeq;

has 'query_validator' => (
    is      => 'ro',
    isa     => 'Bio::Otter::Lace::OnTheFly::QueryValidator',
    handles => [qw( confirmed_seqs seq_types seqs_for_type seqs_by_name seq_by_name record_hit names_not_hit )],
    writer  => '_set_query_validator',
    );

has 'target_seq_obj'  => (
    is     => 'ro',
    isa    => 'Bio::Otter::Lace::OnTheFly::TargetSeq',
    handles => {
        target_fasta_file => 'fasta_file',
        target_start      => 'start',
        target_end        => 'end',
        target_seq        => 'target_seq',
        },
    writer => '_set_target_seq_obj',
    );

has 'softmask_target' => ( is => 'ro', isa => 'Bool' );

has 'aligner_options' => (
    is  => 'ro',
    isa => 'HashRef',
    default => sub { {} },
    );

has 'aligner_query_type_options' => (
    is  => 'ro',
    isa => 'HashRef',
    default => sub { { dna => {}, protein => {} } },
    );

sub _aligner_option_accessor {
    my ($self, $option, @args) = @_;
    ($self->aligner_options->{$option}) = @args if @args;
    return $self->aligner_options->{$option};
}

sub bestn {
    my ($self, @args) = @_;
    return $self->_aligner_option_accessor('--bestn', @args);
}

sub maxintron {
    my ($self, @args) = @_;
    return $self->_aligner_option_accessor('--maxintron', @args);
}

sub BUILD {
    my ($self, $params) = @_;

    $self->_set_query_validator( Bio::Otter::Lace::OnTheFly::QueryValidator->new($params));
    $self->_set_target_seq_obj( $self->build_target_seq($params) );

    return;
}

sub aligners_for_each_type {
    my $self = shift;

    my @aligners;
    foreach my $type ( $self->seq_types ) {
        push @aligners, $self->build_aligner(
            type               => $type,
            seqs               => $self->seqs_for_type($type),
            target             => $self->target_seq_obj,
            softmask_target    => $self->softmask_target,
            options            => $self->aligner_options,
            query_type_options => $self->aligner_query_type_options,
            );
    }
    return @aligners;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
