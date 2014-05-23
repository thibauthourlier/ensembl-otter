
### Bio::Otter::Lace::Defaults

package Bio::Otter::Lace::Defaults;

use strict;
use warnings;
use Carp;
use Getopt::Long 'GetOptions';
use Config::IniFiles;
use File::Temp;
use Try::Tiny;


my $CLIENT_STANZA   = 'client';
my $DEBUG_CONFIG    = 0;
#-------------------------------

### Package state
my $CONFIG_INIFILES; # arrayref of config object
my $UCFG_POS;        # array index for user's config (present or absent)
my $GETOPT;          # config object for the GetOptions variables
my $DONE_GETOPT;     # tristate bool
my $_USERCFG_FN;     # for testing
{
    my $hardwired;
    sub __init {
        if (!defined $hardwired) {
            $hardwired = Config::IniFiles->new(-file => \*DATA)
              or die "Builtin config fail";
            close DATA; # avoids ", <DATA> line 8." on errors
        }
        $CONFIG_INIFILES = [ $hardwired ];
        $GETOPT = Config::IniFiles->new;
        undef $DONE_GETOPT;
        return ();
    }
}
__init();
__fast_ini();

my @CLIENT_OPTIONS = qw(
    url=s
    author=s
    email=s
    write_access!
    gene_type_prefix=s
    debug=s
    ); # a "constant"

# @CLIENT_OPTIONS is Getopt::GetOptions() keys which will be included in the
# $CLIENT_STANZA config.  To add another client option just include in above
# and if necessary add to hardwired defaults in do_getopt().

sub __save_option {
    my ($option, $value) = @_;
    $GETOPT->newval($CLIENT_STANZA, $option, $value);
    return;
}

sub __save_deep_option {
    my (undef, $getopt) = @_; # ignore the option name
    my ($option, $value) = split(/=/, $getopt, 2);
    $option = [ split(/\./, $option) ];
    my $param = pop @$option;
    return unless @$option;
    my $opt_str = join('.', @$option);
    $GETOPT->newval($opt_str, $param, $value);
    return;
}


################################################
#
## PUBLIC SUBROUTINES (there are no methods in here)
#
################################################


=head2 do_getopt

A wrapper function around GetOptions

    We get options from:
     - files provided by list_config_files()
     - command line
     - hardwired defaults (in this subroutine)
    overriding as we go.

Returns true on success, but on failure does:

  exec('perldoc', $0)

Suggested usage:

  Bio::Otter::Lace::Defaults::do_getopt(
    -dataset => \$dataset,
    );


Iff L<Tk> is already loaded, this function gives L<Tk::CmdLine> a
chance to use and remove options first.  These include

 -display
 -name
 -title
 -synchronous

This can provoke errors for incorrect options or invalid X11 displays.
It will eat the options, preventing both their visibility to the
application and the invocation of perldoc when they were not requested
by the application.  L<Tk> will also stop at (and remove) a C<-->.

=cut

sub do_getopt {
    my (@script_args) = @_;

    # Tk::CmdLine takes X11-related options, one time only
    Tk::CmdLine->GetArguments() if $INC{'Tk.pm'};

    confess "do_getopt already called" if defined $DONE_GETOPT;
    $DONE_GETOPT = 0;

    ## If you have any 'local defaults' that you want to take precedence
    #  over the configuration files' settings, unshift them into @ARGV
    #  before running do_getopt()

    __parse_available_config_files();
    ############################################################################
    ############################################################################
    GetOptions(
        'h|help!' => \&show_help,

        # map {} makes these lines dynamically from @CLIENT_OPTIONS
        # 'host=s'        => \&__save_option,
        (map { $_ => \&__save_option } @CLIENT_OPTIONS),

        # this allows setting of options as in the config file
        'cfgstr=s' => \&__save_deep_option,

        # this is just a synonym feel free to add more
        'view' => sub { $GETOPT->newval($CLIENT_STANZA, 'write_access', 0) },

        # this allows multiple extra config file to be used
        'cfgfile=s' => sub {
            push(@$CONFIG_INIFILES, __options_from_file(pop));
        },

        # these are the caller script's options
        @script_args,
      )
      or show_help();
    ############################################################################
    ############################################################################

    push(@$CONFIG_INIFILES, $GETOPT);
    $DONE_GETOPT = 1;

    # now safe to call any subs which are required to setup stuff

    return 1;
}

sub show_help {
    exec('perldoc', $0);
}

sub make_Client {
    require Bio::Otter::Lace::Client;
    return Bio::Otter::Lace::Client->the;
}

sub Client_needs_ready {
    my ($pkg) = @_;
    return __ready(); # () or error
}

sub testmode_redirect_reset {
    ($_USERCFG_FN) = @_;
    __init();
    return ();
}

# Public function to return name of config file in ~/ to enable
# transition.  There should be only one config file, else previous
# versions will see something different.
sub user_config_filename {
    my $user_home = (getpwuid($<))[7];
    my @fn = ("$user_home/.otter/config.ini", # tidy, since v79
              "$user_home/.otter_config");    # since (always .. 2013-01 v78)

    my ($fn, $spare) = grep { -f $_ } @fn; # take first that exists
    if (defined $spare) {
        warn "Ignoring spare user config file $spare, taking $fn\n";
        # Possible if a file is created in old location after rename,
        # causing configuration split at the ...v78/v79... transition.
    } elsif (!defined $fn) {
        $fn = $fn[0];
        warn "No user config present yet (expected at $fn)\n";
        # New user gets config at new filename
    } elsif ($fn eq $fn[1] && ! -l $fn[1] && -d "$user_home/.otter" && -w _) {
        # Present at old filename, we should rename it.
        #
        # An already-running older otterlace could then find the name
        # has changed, but set_and_save is not called by any (v79 or
        # earlier) otterlace when a config file was already present.
        $fn = __rename_user_config($fn[1], $fn[0], $user_home);
    } # else we have it

    return $_USERCFG_FN if defined $_USERCFG_FN; # for testing
    return $fn;
}

sub __rename_user_config {
    my ($old, $new, $user_home) = @_;
    my $what = "user config file from $old to $new";
    if (!defined try { Bio::Otter::LogFile->current_logfile }) {
        warn "Postponed renaming $what until logfile started\n";
        return $old;
    } elsif (rename $old, $new) {
        warn "Renamed $what\n";
        # One attempt to also rename backup or variant files
        if (opendir my $dh, $user_home) {
            foreach my $leaf (readdir $dh) {
                next unless $leaf =~ m{^\.otter_config(.+)$};
                my $sfx = $1;
                my ($a, $b) = ("$user_home/.otter_config$sfx",
                               "$user_home/.otter/config.ini$sfx");
                my $err = (-l $a || !-f $a || -e $b) ? 'skip' : 'ok';
                if ($err eq 'ok') {
                    $err = $! unless rename $a, $b;
                }
                warn "Rename spare config file from $a to $b: $err\n";
            }
        } else {
            warn "Renaming spare config files skipped: $!";
        }
        return $new;
    } else {
        warn "Failed to rename $what: $!";
        return $old;
    }
}

sub __parse_available_config_files {
    my $ucfg_fn = user_config_filename();
    my @conf_files = ("/etc/otter_config");
    if ($ENV{'OTTER_HOME'}) {
        push(@conf_files, "$ENV{OTTER_HOME}/otter_config");
    }
    push @conf_files, $ucfg_fn;

    foreach my $file (@conf_files) {
        $UCFG_POS = @{$CONFIG_INIFILES} if $file eq $ucfg_fn;
        if (my $file_opts = __options_from_file($file, 1)) {
            push @$CONFIG_INIFILES, $file_opts;
        }
    }
    die "confused" unless defined $UCFG_POS;

    return ();
}

sub __options_from_file {
    my ($file, $allowempty) = @_;
    $allowempty ||= 0;

    return unless -e $file;

    warn "Trying $file\n" if $DEBUG_CONFIG;
    my $ini = Config::IniFiles->new( -file => $file, -allowempty => $allowempty);
    confess "Errors found in configuration $file: @Config::IniFiles::errors"
      unless defined $ini;

    # Is it actually empty?
    my @sec = $ini->Sections;
    if (!@sec) {
        warn "Config file $file is empty - ignoring\n";
        unlink($file) and warn "Removed empty config file $file";
        return;
    }

    return $ini;
}


sub __fast_ini {
    # a heuristic to detect O(n^2) versions of Config::IniFiles and
    # warn, to insulate against build regression
    my $civ = Config::IniFiles->VERSION;
    if ($civ =~ m{^\d+\.\d+$} && $civ < 2.84) {
        warn "***\n*** Suspect we have the slow Config::IniFiles v$civ"
          unless Config::IniFiles->can('_cache_purge');
    } else {
        warn "Config::IniFiles v$civ: unknown, is it a slow one?";
    }
    return;
}


################################################
#
##  Subroutines called from Bio::Otter::Lace::Client only
#
################################################

sub save_server_otter_config {
    my ($config) = @_;
    __ready();

    my $tmp = File::Temp->new
      (TEMPLATE => 'server_otter_config.XXXXXX',
       TMPDIR => 1, SUFFIX => '.ini');
    unless ((print {$tmp} $config) && close $tmp) {
        die sprintf('Error writing to %s; %s', $tmp->filename, $!);
    }
    my $ini = __options_from_file($tmp->filename);
    undef $tmp; # DESTROY unlinks it

    # Server config file should be second in list, just after $hardwired
    splice(@$CONFIG_INIFILES, 1, 0, $ini);

    return;
}

sub __ready {
    confess "Not ready to operate on configuration until after do_getopt"
      unless $DONE_GETOPT;
    return ();
}


# Set option in user config and save (if necessary, create) the file.
# Comments are preserved.  Whitespace on "k = v" and "\n\n" are not.
#
# Set undef to clear (but note that our defaults may overlay the
# absence).  Can die for various reasons - config should be unchanged.
# No action taken here to make change take effect on running process.
sub set_and_save {
    my ($section, $param, $value) = @_;
    __ready();

    # Get config
    my $ucfg_fn = user_config_filename();
    my ($ucfg) = grep { my $ofn = $_->GetFileName; defined $ofn && $ofn eq $ucfg_fn } @$CONFIG_INIFILES;

    # Ensure we can write safely
    if (!$ucfg) {
        # No config file at startup
        $ucfg = Config::IniFiles->new();
        $ucfg->SetFileName($ucfg_fn);
        $ucfg->AddSection('client');
        $ucfg->SetSectionComment(client => "Config auto-created ".localtime());
        die "File $ucfg_fn was created since this Otterlace started"
          if -f $ucfg_fn;
        splice(@$CONFIG_INIFILES, $UCFG_POS, 0, $ucfg);
    } else {
        # Did another Otterlace change the file since we loaded it?
        # (No file locks because we expect to be Quick)
        my $ucfg_new = Config::IniFiles->new(-file => $ucfg_fn);
        die "File $ucfg_fn changed and can no longer be read: @Config::IniFiles::errors"
          unless $ucfg_new;
        my $old = __cfgini_to_txt($ucfg);
        my $new = __cfgini_to_txt($ucfg_new);
        if ($old ne $new) {
            warn "Config change detail in $ucfg_fn:\n---\n$old\n+++\n$new\n";
            die "File $ucfg_fn changed since this Otterlace started";
        }
        # nb. whitespace changes ignored because we can't preserve them
    }

    # Mark file as edited
    my @comm = $ucfg->GetSectionComment('client');
    my $CAU = "Config auto-updated ";
    @comm = grep { not m{^# $CAU} } @comm;
    push @comm, $CAU.localtime();
    $ucfg->SetSectionComment(client => @comm);

    # Config change
    if (defined $value) {
        $ucfg->newval($section, $param, $value);
    } else {
        $ucfg->delval($section, $param);
    }

    $ucfg->RewriteConfig
      or die "Option changed but saving configuration failed.  ".
        "Please check the Error Log.\n";

    return ();
}

sub __cfgini_to_txt {
    my ($cfg) = @_;
    my $out = '';
    open my $fh, '>', \$out or die "PerlIO::scalar open fail: $!";
    my $old;
    ## no critic (InputOutput::ProhibitOneArgSelect)
    # that is the API
    try {
        $old = select $fh;
        $cfg->OutputConfig;
        close $fh or die "PerlIO::scalar close fail: $!";
    } finally {
        select $old;
    };
    return $out;
}

# debug (cfg -> config name) fn needed to explain $CONFIG_INIFILES
sub __fn_map { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my @config = @_;
    my @file = map {
        ($_ == $GETOPT) ? 'getopt' : $_->GetFileName;
    } @config;
    my @filename = map {
        (!defined $_) ? 'anon'
            : (ref($_) && $_ == \*DATA) ? 'DATA'
            : $_;
    } @file;
    return @filename;
}


sub config_value {
    my ($section, $key) = @_;
    __ready();

    my $value;
    foreach my $ini ( @$CONFIG_INIFILES ) {
        if (my $v = $ini->val($section, $key)) {
            $value = $v;
        }
    }

    return $value;
}

sub default_config_value {
    my ($section, $key) = @_;
    __ready();
    return $CONFIG_INIFILES->[0]->val($section, $key);
}

sub config_value_list {
    my ($key1, $key2, $name) = @_;
    __ready();

    my $keys = [ "default.$key2", "$key1.$key2" ];
    return [ map { _config_value_list_ini_keys_name($_, $keys, $name); } @$CONFIG_INIFILES, ];
}

sub _config_value_list_ini_keys_name {
    my ($ini, $keys, $name) = @_;
    return map { $ini->val($_, $name); } @{$keys};
}

sub config_value_list_merged {
    my ($key1, $key2, $name) = @_;
    __ready();

    my @keys = ( "default.$key2", "$key1.$key2" );

    my $values;
    foreach my $ini ( @$CONFIG_INIFILES ) {
        foreach my $key ( @keys ) {
            my @vs = $ini->val($key, $name);
            next unless @vs;
            my $vs = \@vs;
            if ( $values ) {
                _config_value_list_merge($values, $vs);
            }
            else {
                $values = $vs;
            }
        }
    }

    return $values;
}

sub _config_value_list_merge {
    my ($values, $vs) = @_;

    # hash the new values
    my $vsh = { };
    $vsh->{$_}++ foreach @{$vs};

    # find the position of the first new value in the current list
    my $pos = 0;
    foreach ( @{$values} ) {
        last if $vsh->{$_};
        $pos++;
    }

    # remove any existing copies of the new values
    @{$values} = grep { ! $vsh->{$_} } @{$values};

    # splice the new values into place
    splice @{$values}, $pos, 0, @{$vs};

    return;
}

sub config_section {
    my ($key1, $key2) = @_;
    __ready();

    my $keys = [ "default.$key2", "$key1.$key2" ];
    return { map { _config_section_ini_keys($_, $keys) } @$CONFIG_INIFILES };
}

sub _config_section_ini_keys {
    my ($ini, $keys) = @_;
    return map { _config_section_ini_key($ini, $_); } @{$keys};
}

sub _config_section_ini_key {
    my ($ini, $key) = @_;
    return
        $ini->SectionExists($key)
        ? ( map {
            $_ => _config_section_ini_key_name($ini, $key, $_);
            } $ini->Parameters($key) )
        : ( );
}

sub _config_section_ini_key_name {
    my ($ini, $key, $name) = @_;
    my @val = $ini->val($key, $name);
    # convert a multi-value into an arrayref
    my $val =
        defined $ini->GetParameterEOT($key, $name)
        ? [ @val ] : $val[0];
    return $val;
}

sub config_keys {
    my ($key1, $key2) = @_;
    __ready();

    my $keys = [ "default.$key2", "$key1.$key2" ];
    return [ map { _config_keys_ini_keys($_, $keys) } @$CONFIG_INIFILES ];
}

sub _config_keys_ini_keys {
    my ($ini, $keys) = @_;
    return map { _config_keys_ini_key($ini, $_); } @{$keys};
}

sub _config_keys_ini_key {
    my ($ini, $key) = @_;
    return map { _section_key($_, $key) } $ini->Sections;
}

sub _section_key {
    my ($section, $key) = @_;
    return unless my ( $key1, $key2 ) = $section =~ /^([^\.]*\.[^\.]*)\.(.*)$/;
    return unless $key1 eq $key;
    return $key2;
}

1;

=head1 NAME - Bio::Otter::Lace::Defaults

=head1 DESCRIPTION

Loads default values needed for creation of an
otter client from:

  command line settings
  --cfgfile options on @ARGV when do_getopt ran
  ~/.otter_config  (but see user_config_filename())
  $ENV{'OTTER_HOME'}/otter_config (if defined)
  /etc/otter_config
  Otter Server's otter_config (spliced in late)
  hardwired defaults (in this module)

in that order.  The values filled in, which can
be given by command line options of the same
name, are:

=over 4

=item B<url>

Defaults to B<http://otter.sanger.ac.uk/cgi-bin/otter>

=item B<author>

Defaults to user name

=item B<email>

Defaults to user name

=item B<write_access>

Defaults to B<0>

=back


=head1 EXAMPLE

Here's an example config file:

  [client]
  url=http://otter.dev.sanger.ac.uk/cgi-bin/otter

  [default.use_filters]
  trf=1
  est2genome_mouse=1

  [zebrafish.use_filters]
  est2genome_mouse=0

  [default.filter.est2genome_mouse]
  module=Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity
  max_coverage=12


You can also specify options on the command line 
using the B<cfgstr> option.  Thus:

    -cfgstr zebrafish.use_filters.est2genome_mouse=0

will switch off est2genome_mouse for the
zebrafish dataset exactly as the config file example
above does.

=head1 SYNOPSIS

  use Bio::Otter::Lace::Defaults;

  # Script can add Getopt::Long compatible options:
  my $foo = 'bar';

  # or override the defaults from ~/.otter_config onwards
  # (but allow the user's command line options to take precedence) :
  unshift @ARGV, '--write_access=0', '--debug=2';

  Bio::Otter::Lace::Defaults::do_getopt(
      'foo=s'   => \$foo,     
      );

  # Obtain the singleton Bio::Otter::Lace::Client instance
  my $client = Bio::Otter::Lace::Defaults::make_Client();

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut


__DATA__

# This is where the HARDWIRED ABSOLUTE DEFAULTS are stored

[client]
url=http://otter.sanger.ac.uk/cgi-bin/otter
write_access=0
gff_version=3
acedb_version=4.9.61
debug=Client,Zircon,XRemote
log_level=INFO
short_window_title_prefix=1
session_colourset = cadetblue firebrick goldenrod #f80 #ff00ff chartreuse2

[Peer]
timeout-ms=2000
timeout-retries=10
rolechange-wait=500

[RequestQueue]
# just send everything for now
# concurrent=12
concurrent=10000
min-batch=4
send-queued-callback-timeout-ms=500
