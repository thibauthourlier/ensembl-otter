### MenuCanvasWindow::ZmapSeqChooser

package MenuCanvasWindow::XaceSeqChooser;

use strict;
use Carp qw{ cluck confess };
use ZMap::Connect qw(:all);
use Sys::Hostname;
use Tie::Watch;
use Hum::Ace::LocalServer;
use Data::Dumper;

my $ZMAP_DEBUG = 1;

#==============================================================================#
#
# WARNING: THESE ARE INJECTED METHODS!!!!
#  I HAVE PREFIXED THEM ALL WITH zMap SO NONE SHOULD CLASH
#  BUT ALL WILL NEED CHANGING LATER (RDS)
#
#==============================================================================#

=pod

=head1 WARNING

This modules injects methods into the MenuCanvasWindow::XaceSeqChooser
namespace.  All have  been prefixed with "zMap" to  avoid any clashes,
but this isn't a long term solution.

=head1 zMapLaunchZmap

This is where it all starts.  This is the method which gets called 
on 'Launch ZMap' menu item in xaceseqchooser window.

=cut

sub printForFun{ print "Ha ha! @_\n"; }
sub new_command{
    my ($self) = @_;
    return unless $self->current_state eq 'subseq';
    $self->edit_new_subsequence(1);
} 
my $replace = 1;
my $coexist = 0;
my $ZMAP_MENUS = {
    'Close'   => [\&printForFun,$replace],
    'Variant' => [\&printForFun,$replace],
    'Delete'  => [\&printForFun,$replace],
    'New'     => [\&new_command,$replace],
};

sub zMap_make_exoncanvas_edit_window{
    my( $self, $sub ) = @_;
    
    my $sub_name = $sub->name;
    warn "subsequence-name $sub_name " ;
#    warn "locus " . $sub->Locus->name ;
    my $canvas = $self->canvas;
    
    # Make a new window
    my $top = $canvas->Toplevel;
    
    # Make new MenuCanvasWindow::ExonCanvas object and initialize
    my $ec = MenuCanvasWindow::ZMapExonCanvas->new($top, 345, 50);
    $ec->name($sub_name);
    $ec->XaceSeqChooser($self);
    $ec->SubSeq($sub);
    $ec->initialize;
    
    $self->save_subseq_edit_window($sub_name, $ec);
    
    return $ec;
}

sub zMapReplaceMenuCommands {
    my ($self) = @_;

    return unless $ZMAP_MENUS;

    foreach my $mb($self->menu_bar->children){
        next unless $mb && $mb->isa("Tk::Menubutton");
        foreach my $menu($mb->children){
            my $max = $menu->index('last');
            for my $i(0..$max){
                next unless $menu->type($i) eq 'command';
                my $label = $menu->entrycget($i, '-label');
                my $original_cb = $menu->entrycget($i, '-command');
                print "found $label with cb $original_cb\n";

                if(my $replacement = $ZMAP_MENUS->{$label}->[0]){
                    print "reconfiguring $label\n";
                    my $cb = undef;
                    # This is to so we call both the original callback together we our own version
                    if($ZMAP_MENUS->{$label}->[1]){
                        $cb = sub { 
                            print "$self \n";
                            $self->$replacement(); 
                        };
                    }else{
                         $cb = sub { 
                            print "$self \n";
                            $self->$replacement(); 
                            if($#$original_cb){
                                $original_cb->[0]->($original_cb->[1..$#$original_cb]);
                            }else{
                                $original_cb->[0]->();
                            }
                        };
                    }

                    $menu->entryconfigure($i, -command => $cb );
                }
            }
        }
    }
    
    $ZMAP_MENUS = undef;

}
sub zMapLaunchZmap {
    my( $self ) = @_;

    #$self->zMapReplaceMenuCommands();

    $self->zMapKillZmap;
    my $z = $self->zMapInsertZmapConnector();
    $self->zMapWriteDotZmap();
    $self->zMapWriteDotGtkrc();
    $self->isZMap(1);
    my @e = ('zmap', 
             '--conf_dir' => $self->zMapZmapDir,
             '--win_id'   => $z->server_window_id);
    warn "export PATH=$ENV{PATH}\nexport LD_LIBRARY_PATH=$ENV{LD_LIBRARY_PATH}\n@e\n" if $ZMAP_DEBUG;

    # this makes it a lot easier to debug with ddd
    if(my $command_file = $ENV{DEBUG_WITH_DDD}){
        my $ddd_file = $self->zMapZmapDir() . "/xremote.ddd";
        eval{
            unlink($ddd_file);
            open(my $ddd, ">$ddd_file");
            open(my $input, "<$command_file");
            while(<$input>){ print $ddd $_ }
            close $input;
            my $ld_library_path = "/nfs/team71/acedb/zmap/prefix/LINUX/lib";
            print $ddd "set environment LD_LIBRARY_PATH $ld_library_path\n";
            print $ddd "run --conf_dir ".$self->zMapZmapDir." --win_id ".$z->server_window_id. "\n";
            close $ddd;
        };
        if(!$@){
            @e = ('ddd', '--nx', '--command', $ddd_file, 'zmap');
        }
    }

    sleep(2);
    my $ref = Hum::Ace::LocalServer::full_child_info();
    my $pid = fork_exec(\@e, $ref, 0, sub { 
        my ($info) = @_;
        flush_bad_windows;
        use Data::Dumper;                
        warn "INFO: ", Dumper($info);
    });

    if($pid){
        $self->zMapProcessIDList($pid);
    }else{
        my $mess = "Error: couldn't fork()\n";
        warn $mess;
        $self->message($mess);
    }
}
sub zMapKillZmap {
    my( $self ) = @_;
    
    if (my $pid = $self->zMapProcessIDList) {
        my $mainWindowName = 'ZMap port #' . $self->AceDatabase->ace_server->port;
        my $xr = xclient_with_name($mainWindowName, 0, "$self")
            or return;
        $xr->send_commands('<zmap action="shutdown" />');
        ### Check shutdown by checking property set by ZMap?
    }
}
sub zMapProcessIDList {
    my( $self, $zmap_process_id ) = @_;
    
    if ($zmap_process_id) {
        $self->{'_zMap_ZMAP_PROCESS_ID'} = $zmap_process_id;
    }
    return $self->{'_zMap_ZMAP_PROCESS_ID'};
}
sub zMapInsertZmapConnector{
    my ($self) = @_;
    my $zc = $self->{'_zMap_ZMAP_CONNECTOR'};
    if(!$zc){
        my $mb   = $self->menu_bar();
        my $zmap = ZMap::Connect->new( -server => 1 );
        $zmap->init($mb, \&RECEIVE_FILTER, [ $self, qw( register_client ) ]);
        my $id = $zmap->server_window_id();
        $zc = $self->{'_zMap_ZMAP_CONNECTOR'} = $zmap;
    }
    return $zc;
}
sub zMapZmapConnector{
    return shift->zMapInsertZmapConnector(@_);
}

sub zMapWriteDotZmap{
    my ($self) = @_;
    my $dir    = $self->zMapZmapDir();
    my $file   = "${dir}/ZMap";
    my $fh;
    eval{
        # directory should be made already
        open($fh, ">$file") or die "write_dot_zmap: error writing file '$file', $!";
    };
    warn "Error in :$@" if $@;
    unless($@){
        my $content = $self->zMapDotZmapContent();
        print $fh $content;
        return 1;
    }
    close $fh;
    return 0;
}

sub zMapDotZmapContent{
    my ($self) = @_;

    return
        $self->zMapZMapDefaults
      . $self->zMapWindowDefaults
      . $self->zMapBlixemDefaults
      . $self->zMapServerDefaults
      ;
}

sub zMapServerDefaults {
    my ($self) = @_;
    
    my $server = $self->AceDatabase->ace_server;
    
    my $protocol    = 'acedb';
    my $username    = 'any';
    my $password    = 'any';

    my $url = sprintf q{"%s://%s:%s@%s:%d"},
        $protocol,
        $username, $password,
        $server->host, $server->port;
    
    return $self->formatZmapDefaults(
        'source',
        url         => $url,
        writeback   => 'false',
        sequence    => 'true',
        featuresets => sprintf(q{"%s"}, join ' ', $self->zMapListMethodNames_ordered),
        # Can specify a stylesfile instead of featuresets

    );
}

sub zMapZMapDefaults {
    my ($self) = @_;

    # make this configurable for those users where zmap doesn't start due to not having window
    # id when doing XChangeProperty.
    my $boolean   = { true => 'true', false => 'false'};
    my $win       = Bio::Otter::Lace::Defaults::option_from_array([qw(client zmap_main_window)]);
    my $show_main = $boolean->{$win} || $boolean->{'false'};
    
    return $self->formatZmapDefaults(
        'ZMap',
        show_mainwindow  => $show_main,
    );
}

sub zMapBlixemDefaults {
    my ($self) = @_;
    
    return $self->formatZmapDefaults(
        'blixem',
        qw{
            netid       "pubseq"
            port        22100
            script      "blixem"
            scope       40000
            homol_max   0
        }
    );
    # script could also be "blixem_standalone" sh wrapper (if needed)
}

sub zMapWindowDefaults {
    my ($self) = @_;
    
    return $self->formatZmapDefaults(
        'ZMapWindow',
        qw{
            feature_line_width          1
            feature_spacing             4.0
            colour_column_highlight     "CornSilk"
        }
    );
}

sub formatZmapDefaults {
    my ($self, $key, %defaults) = @_;
    
    my $def_str = "\n$key\n{\n";
    while (my ($setting, $value) = each %defaults) {
        $def_str .= qq{$setting = $value\n};
    }
    $def_str .= "}\n";
    
    return $def_str;
}

sub zMapWriteDotGtkrc {
    my $self = shift;
    
    my $dir = $self->zMapZmapDir;
    my $file = "$dir/.gtkrc";
}

sub zMapZmapDir {
    my $self = shift;

    confess "Cannot set ZMap directory directly" if @_;

    my $ace_path = $self->ace_path();
    my $path = "$ace_path/ZMap";
    unless(-d $path){
        mkdir $path;
        die "Can't mkdir('$path') : $!\n" unless -d $path;
    }
    return $path;
}

sub zMapListMethodNames_ordered{
    my $self = shift;
    my @list = ();
    my $collection = $self->AceDatabase->get_default_MethodCollection;
    $collection->order_by_right_priority;
    return map $_->name, @{$collection->get_all_Methods};
}

#===========================================================

sub zMapCurrentXclient{
    my ($self) = @_;
    return xclient_with_name(${$self->zMapEntryRef}, 0, "$self");
}
sub zMapEntryRef{
    my ($self) = @_;
    my $n = '';
    $self->{'_zMap_ENTRY_REF'} ||= \$n;
    return $self->{'_zMap_ENTRY_REF'};
}
sub zMapSetEntryValue{
    my ($self, $value) = @_;
    my $ref = $self->zMapEntryRef();
    $$ref   = $value;
}


sub zMapRegisterClient{
    my ($self, $request) = @_;
    my $mainWindowName = 'ZMap port #' . $self->AceDatabase->ace_server->port;
    my $p  = parse_request($request);
    my $xr = xclient_with_name($mainWindowName, 0, "$self");
    my $z  = $self->zMapZmapConnector();
    my $h  = {
        response => {
            client => [{
                created => 0,
                exists  => 1,
            }]
        }
    };
    $z->protocol_add_meta($h);

    $self->zMapEntryRef();
    
    return (200, make_xml($h)) if $xr;

    unless($p->{'client'}->{'xwid'} 
           && $p->{'client'}->{'request_atom'}
           && $p->{'client'}->{'response_atom'}){
        warn "mismatched request for register_client:\n", 
        "id, request and response required\n",
        "Got '$request'\n";
        return (403, $z->basic_error("Bad Request!"));
    }

    warn "after first return zmapregisterclient..." if $ZMAP_DEBUG;
 
    xclient_with_name($mainWindowName, $p->{'client'}->{'xwid'}, "$self");

    $self->zMapSetEntryValue($mainWindowName);

    Tie::Watch->new(-variable => \$WAIT_VARIABLE,
                    -debug    => 1,
                    -store    => [ \&open_clones, $self ],
                    );
    # this feels convoluted
    $h->{'response'}->{'client'}->[0]->{'created'} = 1;
    return (200, make_xml($h));
}


#===========================================================

sub zMapMakeRequest{
    my ($self, $xmlObject, $action, $xml_cmd_string) = @_;

    my $xr = $self->zMapCurrentXclient;
    unless($xr){
        warn "No current window.";
        return ;
    }
    warn "Current window " . $xr->window_id . " @_\n" if $ZMAP_DEBUG;
    my $handler ||= \&RESPONSE_HANDLER;
    my $error   ||= \&ERROR_HANDLER;

    my @commands;

    if(!$xmlObject && !$action && $xml_cmd_string){
        @commands = ($xml_cmd_string);
    }else{
        @commands = obj_make_xml($xmlObject, $action);
    }
    warn "@commands" if $ZMAP_DEBUG;
    my @a = $xr->send_commands(@commands);

    for(my $i = 0; $i < @commands; $i++){
        my ($status, $xmlHash) = parse_response($a[$i]);
        if($status =~ /^2\d\d/){ # 200s
            $handler->($self, $xmlHash);
        }else{
            $error->($self, $status, $xmlHash);
        }
    }
    return ;
}

# This  menu stuff  needs  rewriting.  It doesn't  work  100% like  it
# should.  It isn't  really needed  for production  so it's  not  a high
# priority
sub zMapUpdateMenu{ 
    my ($self) = @_; my $menu_item = $self->{'_zMapMenuItem'}; 

    my $cleanUpMenu = sub{
        my ($menuRoot, $this) = @_;
        my @current = list_xclient_names("$self");
        $this->{'_zMapSubMenuItems'} ||= {};
        my @remove = ();
        foreach my $k(keys(%{$this->{'_zMapSubMenuItems'}})){
            my $idx = $this->{'_zMapSubMenuItems'}->{$k};
            print "This is $k \n" if $ZMAP_DEBUG;
            if(!(grep /^$k$/, @current)){
                delete $this->{'_zMapSubMenuItems'}->{$k};
                push(@remove, $idx);
            }
        }
        map { $menuRoot->delete($_) } @remove;
    };

    my $fullCleanUpMenu = sub {
        my ($button, $this) = @_;
        if(my $menu = $button->cget('-menu')){
            $cleanUpMenu->($menu, $this);
        }        
    };

    unless($menu_item){
        my $frame  = $self->menu_bar;
        my $button = $frame->Menubutton(-text => 'ZMap')->pack(-side => 'left');
        my $menu   = $button->Menu(-tearoff => 0);
        $button->configure(-menu => $menu);
        $button->bind('<Button-1>', [ $fullCleanUpMenu, $self ]);

        $self->{'_zMapMenuItem'} = 
            $menu_item = $button; #$self->make_menu('ZMap', 1);
    }

    my $addSubMenuItem = sub {
        my ($this, $menuRoot, $name) = @_;
        $this->{'_zMapSubMenuItems'} ||= {};
        $this->{'_zMapSubMenuItems'}->{$name} = scalar(keys(%{$this->{'_zMapSubMenuItems'}}));
        my $submi = $menuRoot->cascade(-label => $name, -tearoff => 0);

        if($name =~ /port/){
            $submi->command(-command => [ sub { 
                my $self = shift;
                my $z = newXMLObj('client');
                $self->zMapSetEntryValue($name); 
                $self->zMapMakeRequest($z, 'close');
            }, $self ],-label => 'Shutdown ZMap');     
        }else{
            $submi->command(-command => [ sub { 
                my $this = shift;
                my $z    = newXMLObj('zoom_in');
                $this->zMapSetEntryValue($name); 
                $this->zMapMakeRequest($z, 'zoom_in');
            }, $self ], 
                            -label => 'Zoom In');             
            $submi->command(-command => [ sub { 
                my $this = shift;
                my $z    = newXMLObj('zoom_in');
                $self->zMapSetEntryValue($name); 
                $self->zMapMakeRequest($z, 'zoom_out');
            }, $self ], 
                            -label => 'Zoom Out');             
        }
    };

    $cleanUpMenu->($menu_item, $self);

    foreach my $name (list_xclient_names("$self")){
        $addSubMenuItem->($self, $menu_item, $name);
    }

    return ;
}


#===========================================================

sub RECEIVE_FILTER{
    my ($_connect, $_request, $_obj, @list) = @_;
    my ($_status, $_response) 
        = (404, $_obj->zMapZmapConnector->basic_error("Unknown Command"));

    my $lookup = {register_client => 'zMapRegisterClient'};
    my $action = '';
    my $reqXML = parse_request($_request);
    $action    = $reqXML->{'action'};

    foreach my $valid(@list){
        if($action eq $valid
           && ($valid = $lookup->{$valid}) # N.B. THIS SHOULD BE ASSIGNMENT NOT EQUALITY 
           && $_obj->can($valid)){
            ($_status, $_response) 
                = $_obj->$valid($_request);
            last;
        }
    }
    return ($_status, $_response) ;
}

sub open_clones{
    my ($watch) = @_;
    my ($self)  = @{$watch->Args('-store')};

    my ($chr, $st, $end) = split(/\.|\-/, $self->slice_name);

    my $seg = newXMLObj('segment');
    setObjNameValue($seg, 'sequence', $self->slice_name);
    setObjNameValue($seg, 'start', 1);
    setObjNameValue($seg, 'end', '0');

    $self->zMapMakeRequest($seg, 'new');

    ### ZMap menu not needed for first ZMap test release
    ### and now that we have a single slice.
    #$self->zMapUpdateMenu();
    
    $watch->Unwatch;
}

sub RESPONSE_HANDLER{
    my ($self, $xml) = @_;
    warn "In RESPONSE_HANDLER\n" if $ZMAP_DEBUG;
    my ($name, $id) = ($xml->{'response'}->{'zmapid'}, $xml->{'response'}->{'windowid'});
    if($name){
        xclient_with_name($name, $id, "$self") if $id;
        $self->zMapSetEntryValue($name);
    }
    return ;
}
sub ERROR_HANDLER{
    my ($self, $status, $xml) = @_;
    $xml = $xml->{'error'}; # this is all we care about
    warn "In ERROR_HANDLER\n" if $ZMAP_DEBUG;
    my $full = Dumper $xml;
    warn "status $status, xml string '$full'\n" if $ZMAP_DEBUG;

    if($status == 400){

    }elsif($status == 401){

    }elsif($status == 402){

    }elsif($status == 403){

    }elsif($status == 404){
        # could do something clever here so that we don't send the same window this command again.
        my $message = $xml->{'message'};
    }elsif($status == 412){
        delete_xclient_with_id($xml->{'windowid'});
    }elsif($status == 500){
    
    }elsif($status == 501){
    
    }elsif($status == 502){
    
    }elsif($status == 503){
    
    }else{
        warn "I know nothing about status $status\n";
    }
    return ;
}



1;

__END__


=pod

=head1 REMOVE

sub update_display{
    my ($self , $ace) = @_ ;
    warn "cannot update display yet";
    return 1;
}
# this should be called when a user tries to save, but no ZMap is opened
sub open_dialogue{
    my ($self) = @_ ;
    warn "cannot open dialogue yet";
    return undef;

}

sub get_window_id {
    my( $self ) = @_;

    # be good if we could replace this with something more automatic....    
    my $mid = $self->message("Please click on the xace main window with the cross-hairs");
    $self->delete_message($mid);
    local *XWID;
    open XWID, "xwininfo |"
        or confess("Can't open pipe from xwininfo : $!");
    my( $xwid );
    while (<XWID>) {
        # xwininfo: Window id: 0x7c00026 "ACEDB 4_9c, lace bA314N13"

      # HACK
      # above format NOT returnd by xwininfo on Sun OS 5.7:
      #  tace version:
      #  ACEDB 4_9r,  build dir: RELEASE.2003_05_01
      # 2 lines before modified to support xace at RIKEN

        # BEFORE: if (/Window id: (\w+) "([^"]+)/) {
        if (/Window id: (\w+) "([^"]+)/ || /Window id: (\w+)/) {
            my $id   = $1;
            my $name = $2;
	    # BEFORE: if ($name =~ /^ACEDB/){
            if ($name =~ /^ACEDB/ || $name eq '') {
                $xwid = $id;
                $self->message("Attached to:\n$name");
            } else {
                $self->message("'$name' is not an xace main window");
            }
        }
    }
    if (close XWID) {
        return $xwid;
    } else {
        $self->message("Error running xwininfo: $?");
    }
}


sub attach {
    my( $self ) = @_;
    
    if (my $xwid = $self->zmap_id) {
        my $xrem = Hum::Ace::XaceRemote->new($xwid);
        $self->xace_remote($xrem);
        #$xrem->send_command('save');
# This command may be redundant with zmap + lace
#        $xrem->send_command('writeaccess -gain');
    } else {
        warn "no xwindow id: $xwid";
    }
}


=head1 NAME - MenuCanvasWindow::ZmapSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk


=cut

__DATA__



