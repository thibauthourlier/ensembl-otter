
### Bio::Otter::Lace::Source::Collection

package Bio::Otter::Lace::Source::Collection;

use strict;
use warnings;
use Carp;
use Text::ParseWords qw{ quotewords };
use Hum::Sort qw{ ace_sort array_ace_sort };
use Bio::Otter::Lace::Source::Item::Bracket;
use Bio::Otter::Lace::Source::Item::Column;
use Data::Dumper;

$Data::Dumper::Terse = 1;

sub new {
    my ($pkg) = @_;

    return bless {
        '_item_list'    => [],
    }, $pkg;
}

sub new_from_Filter_list {
    my ($pkg, @list) = @_;

    @list = sort { array_ace_sort([$a->classification], [$b->classification])
                   || ace_sort($a->name, $b->name) } @list;

    my $cllctn = Bio::Otter::Lace::Source::Collection->new;
    my $bkt_path = [];
    foreach my $filter (@list) {
        my $col = Bio::Otter::Lace::Source::Item::Column->new;
        $col->name($filter->name);
        $col->Filter($filter);
        my @new_bkt = __maintain_Bracket_array($bkt_path, [ $filter->classification ]);
        foreach my $bkt (@new_bkt) {
            $cllctn->add_Item($bkt);
        }
        $col->indent(@$bkt_path || 0);
        $cllctn->add_Item($col);
    }

    return $cllctn;
}

sub __maintain_Bracket_array {
    my ($bkt_path, $clss) = @_;

    my @new_bkt;
    for (my $i = 0; $i < @$clss; $i++) {
        my $name =     $clss->[$i];
        my $bkt  = $bkt_path->[$i];
        # Since shorter classification arrays sort before longer ones
        # we don't need to deal with shortening the array of Brackets
        # if the classification list is shorter than the array of
        # Brackets, since it must contain a new name.
        unless (($bkt and defined($name)) and lc($bkt->name) eq lc($name)) {
            $bkt = Bio::Otter::Lace::Source::Item::Bracket->new;
            $bkt->name($name);  # We use the capitalisation of the fist occurrence of this name
            $bkt->indent($i);
            # Clip array at this postion and replace with new Bracket
            splice(@$bkt_path, $i, @$bkt_path - $i, $bkt);
            push(@new_bkt, $bkt);
        }
    }

    return @new_bkt;
}

sub search_string {
    my ($self, $search_string) = @_;
    
    if (defined $search_string) {
        $self->{'_search_string'} = $search_string;
        $self->construct_regex_list;
    }
    return $self->{'_search_string'};
}

sub construct_regex_list {
    my ($self) = @_;

    # Make a fresh new reference
    my $r_list = $self->{'_regex_list'} = [];
    
    foreach my $term (quotewords('\s+', 0, $self->search_string)) {
        my $test = 1;
        if ($term ne '-' and $term =~ s/^-//) {
            $test = 0;
        }
        push(@$r_list, [$test, qr{$term}m]);
    }
}

sub regex_list {
    my ($self) = @_;
    
    my $r_list = $self->{'_regex_list'}
        or confess "No regex list - construct_regex_list() not called?";
    return @$r_list;
}

sub add_Item {
    my ($self, $item) = @_;

    my $i_ref = $self->{'_item_list'};
    push @$i_ref, $item;
    return;
}

sub list_Items {
    my ($self) = @_;
    
    if (my $i_ref = $self->{'_item_list'}) {
        return @$i_ref;
    }
    else {
        return;
    }
}

sub clear_Items {
    my ($self) = @_;

    $self->{'_item_list'} = [];
    return;
}

sub filter {
    my ($self, $new) = @_;

    if ($new) {
        $new->clear_Items;
    }
    else {
        $new = ref($self)->new;
    }

    my @tests = $self->regex_list;
    my @item_list = $self->list_Items;
    my @hit_i;
    for (my $i = 0; $i < @item_list;) {
        my $item = $item_list[$i];
        my $hit = 0;
        foreach my $t (@tests) {
            my ($true, $regex) = @$t;
            if ($true) {
                if ($item->string =~ /$regex/) {
                    $hit = 1;
                }
            }
            else {
                if ($item->string !~ /$regex/) {
                    $hit = 1;
                }
            }
            last if $hit;
        }
        if ($hit) {
            $hit_i[$i] = 1;
            my $this_indent = $item->indent;
            if ($item->is_Bracket) {
                # Add every following item with an indent great than this
                for (my $j = $i + 1; $j < @item_list; $j++) {
                    my $other = $item_list[$j];
                    if ($other->indent > $this_indent) {
                        $hit_i[$j] = 1;
                    }
                    else {
                        # We're back to an item at the same level as the match
                        last;
                    }
                }
            }
            # Add every prevous Bracket with an intent less than this so that
            # the new collection has all the branches which lead to this node.
            for (my $j = $i - 1; $j > 0; $j--) {
                my $other = $item_list[$j];
                if ($other->is_Bracket) {
                    my $other_indent = $other->indent;
                    if ($other_indent < $this_indent) {
                        $hit_i[$j] = 1;
                        $this_indent--;     # or we would add all brackets at highter level!
                    }
                    last if $other_indent == 0;
                }
            }
        }
    }

    # Loop through @hit_i because it may be shorter than @item_list
    for (my $i = 0; $i < @hit_i; $i++) {
        if ($hit_i[$i]) {
            # Copy matched item into new object
            $new->add_Item($self->{'_item_list'}[$i]);
        }
    }
    return $new;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::Collection

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

