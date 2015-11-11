package Bio::Otter::UI::AboutBoxMixIn;

use strict;
use warnings;

# Any number of URLs may be inserted in $content.  If we want images or
# other markup, it's time to break out a new class.

sub make_box {
    my ($self, $title, $content, $all_mono) = @_;

    my $box = $self->top_window->DialogBox
        (-title   => $title,
         -buttons => [qw[ Close ]]);
    $box->Tk::bind('<Escape>', [ $box, 'Exit' ]);

    my ($x, $y) = (30, 0);
    foreach my $ln (split /\n/, $content) {
        $y++;
        $x = length($ln) if length($ln) > $x;
    }

    my $font = $self->named_font('prop');
    my $mono = $self->named_font('mono');

    if ($all_mono) {
        $font = $mono;
    }

    my $txt =
       $box->ROText(
           -bg                => 'white',
           -height            => $y,
           -width             => $x,
           -selectborderwidth => 0,
           -borderwidth       => 0,
           -font              => $font,
       )
       ->pack(
           -side   => 'top',
           -fill   => 'both',
           -expand => 1,
       );

    foreach my $seg (split m{(\w+://\S+)}, $content) {
        my @tag;
        push @tag, 'link' if $seg =~ m{://};
        $txt->insert(end => $seg, @tag);
    }

    $txt->tagConfigure(link => -foreground => 'blue', -underline => 1, -font => $mono);
    $txt->tagBind(link => '<Button-1>', [ $self, 'about_hyperlink', $txt, Tk::Ev('@') ]);
    $txt->configure(-state => 'disabled');

    return $box;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
