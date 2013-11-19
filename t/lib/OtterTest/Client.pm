# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Lace::Client;   # _build_meta_hash
use Bio::Otter::Utils::MM;
use Bio::Otter::Server::Config;
use Bio::Otter::Server::Support::Local;
use Bio::Otter::ServerAction::TSV::LoutreDB;
use Bio::Otter::Version;

use File::Slurp qw( slurp write_file );
use Test::Builder;
use Try::Tiny;

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub get_accession_types {
    my ($self, @accessions) = @_;
    my $types = $self->mm->get_accession_types(\@accessions);
    # FIXME: de-serialisation is in wrong place: shouldn't need to serialise here.
    # see apache/get_accession_types and AccessionTypeCache.
    my $response = '';
    foreach my $acc (keys %$types) {
        $response .= join("\t", $acc, @{$types->{$acc}}) . "\n";
    }
    return $response;
}

sub mm {
    my $self = shift;
    return $self->{_mm} ||= Bio::Otter::Utils::MM->new;
}

# FIXME: scripts/apache/get_config needs reimplementing with a Bio::Otter::ServerAction:: class,
#        which we can then use here rather than duplicating the file names.
#
sub get_otter_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('otter_schema.sql');
}

sub get_loutre_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('loutre_schema_sqlite.sql');
}

sub get_meta {
    # FIXME: what about dataset?
    my $self = shift;
    my $response = $self->_meta_response;
    return $self->Bio::Otter::Lace::Client::_build_meta_hash($response);
}

sub get_db_info {
    # FIXME: what about dataset?
    return { 'coord_system.chromosome' => [ 2, 1, 'chromosome', 'Otter', 2, 'default_version' ] };
}

sub _meta_response {
    my $self = shift;

    my $tb = Test::Builder->new;

    my $fn = $self->_meta_response_cache_fn;
    my $cache_age = 1; # days

    if (-f $fn && (-M _) < $cache_age) {
        # got it, and it's recent
        my $response = slurp($fn);
        return $response;
    } else {
        # probably need to fetch it
        my ($error, $response) = $self->_get_meta_fresh($fn);
        if ($error && -f $fn) {
            my $age = -M $fn;
            $tb->diag("Proceeding with $age-day stale $fn because cannot fetch fresh ($error)");
            $response = slurp($fn);
        } elsif ($error) {
            die "No cached data at $fn ($error)";
        }
        return $response;
    }
}

sub _get_meta_fresh {
    my ($self, $fn) = @_;

    my ($error, $meta_tsv);
    try {
        my $tb = Test::Builder->new;

        my $local_server = Bio::Otter::Server::Support::Local->new;
        $local_server->set_params(dataset => 'human'); # FIXME: hard-coded

        my $ldb_tsv = Bio::Otter::ServerAction::TSV::LoutreDB->new($local_server);
        $meta_tsv = $ldb_tsv->get_meta;
        $tb->note("OtterTest::Client::get_meta: fetched fresh copy");

        write_file($fn, \$meta_tsv);
        $tb->note("OtterTest::Client::get_meta: cached in '$fn'");

        1;
    }
    catch {
        $error = $_;
    };
    return ($error, $meta_tsv);
}

sub _meta_response_cache_fn {
    my $fn = __FILE__; # this module
    my $pkgfn = __PACKAGE__;
    $pkgfn =~ s{::}{/}g;
    my $vsn = Bio::Otter::Version->version;
    $fn =~ s{(/t/)lib/\Q$pkgfn.pm\E$}{$1.OTC.meta_response.$vsn.txt}
      or die "Can't make filename from $fn";
    return $fn;
}

1;
