package TransientWindow::OpenRange;

use strict;
use warnings;

use base qw( TransientWindow );


sub draw{
    my $self   = shift;
    return if $self->{'_drawn'};

    my $trim_window = $self->window;
    
    my $no_of_cs = ${$self->text_variable_ref('total')};
    my $max_pp   = ${$self->text_variable_ref('per_page')};
    my $label    = $trim_window->Label(-text => "It looks as though you are about to open" .
                                       " a large sequence set. Would you like to restrict" .
                                       " the number of clones visible in the ana_notes window?" .
                                       " If so please enter the number of the first and last" .
                                       " clones you would like to see.",
                                       -wraplength => 400, ####????
                                       -justify    => 'center'
                                       )->pack(-side   =>  'top');
    $label->bind('<Destroy>', sub { $self = undef});


    my $entry_frame = $trim_window->Frame()->pack(-side   =>  'top',
                                                  -pady   =>  5,
                                                  -fill   =>  'x'
                                                  ); 
    $entry_frame->bind('<Destroy>', sub { $self = undef });

    my $label1        = $entry_frame->Label(-text => "First Clone: (1)"
                                            )->pack(-side => 'left');
    my $search_entry1 = $entry_frame->Entry(
                                            -width        => 5,
                                            -relief       => 'sunken',
                                            -borderwidth  => 2,
                                            -textvariable => $self->text_variable_ref('user_min'),
                                            )->pack(-side => 'left',
                                                    -padx => 5,
                                                    -fill => 'x'
                                                    );

    my $auto_last_clone = sub {
        my $min = ${$self->text_variable_ref('user_min')};
        $self->text_variable_ref('user_max', $min + $max_pp > $no_of_cs ? $no_of_cs : $min + $max_pp, 1);
    };
    $search_entry1->bind('<FocusOut>', $auto_last_clone);
    $search_entry1->bind('<Destroy>', sub { $self = undef});
    
    my $label2       = $entry_frame->Label(-text => "Last Clone: ($no_of_cs)"
                                           )->pack(-side   =>  'left');
    my $search_entry2 = $entry_frame->Entry(-width        => 5,
                                            -relief       => 'sunken',
                                            -borderwidth  => 2,
                                            -textvariable => $self->text_variable_ref('user_max'),
                                            )->pack(-side => 'left',
                                                    -padx => 5,
                                                    -fill => 'x',
                                                    );
    $search_entry2->bind('<Destroy>', sub { $self = undef});
    ## search cancel buttons
    my $limit_cancel_frame = $trim_window->Frame()->pack(-side => 'bottom',
                                                         -padx =>  5,
                                                         -pady =>  5,
                                                         -fill => 'x'
                                                         );   
    my $openRange    = $self->action('openRange');
    my $limit_button = $limit_cancel_frame->Button(-text    => 'Open Range',
                                                   -command => [ $openRange, $self ],
                                                   )->pack(-side  => 'right');
    my $openAll       = $self->action('openAll');
    my $cancel_button = $limit_cancel_frame->Button(-text    => 'Open All',
                                                    -command => [ $openAll, $self ],
                                                    )->pack(-side => 'right');
    
    $limit_cancel_frame->bind('<Destroy>', sub { $self = undef});
    # clean up circulars
    $self->delete_all_actions();

    $self->{'_drawn'} = 1;
    return;
}

1;





__END__


