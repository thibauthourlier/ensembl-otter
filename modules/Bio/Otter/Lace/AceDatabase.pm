
### Bio::Otter::Lace::AceDatabase

package Bio::Otter::Lace::AceDatabase;

use strict;
use Carp;
use File::Path 'rmtree';
use Symbol 'gensym';
use Fcntl qw{ O_WRONLY O_CREAT };
use Ace;
use Bio::Otter::Lace::PipelineDB;
use Bio::Otter::Lace::SatelliteDB;
use Bio::Otter::Converter;

use Bio::EnsEMBL::Ace::DataFactory;

use Bio::EnsEMBL::Ace::Filter::Repeatmasker;
use Bio::EnsEMBL::Ace::Filter::CpG;
use Bio::EnsEMBL::Ace::Filter::DNA;
use Bio::EnsEMBL::Ace::Filter::TRF;
use Bio::EnsEMBL::Ace::Filter::Gene;
use Bio::EnsEMBL::Ace::Filter::Gene::Halfwise;
use Bio::EnsEMBL::Ace::Filter::Gene::Predicted;
use Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity;
use Bio::EnsEMBL::Ace::Filter::Similarity::ProteinSimilarity;
use Bio::EnsEMBL::Ace::Filter::SimpleFeature;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub Client {
    my( $self, $client ) = @_;
    
    if ($client) {
        $self->{'_Client'} = $client;
    }
    return $self->{'_Client'};
}

sub home {
    my( $self, $home ) = @_;
    
    if ($home) {
        $self->{'_home'} = $home;
    }
    elsif (! $self->{'_home'}) {
        $self->{'_home'} = "/var/tmp/lace.$$";
    }
    return $self->{'_home'};
}

sub title {
    my( $self, $title ) = @_;
    
    if ($title) {
        $self->{'_title'} = $title;
    }
    elsif (! $self->{'_title'}) {
        $self->{'_title'} = "lace.$$";
    }
    return $self->{'_title'};
}

sub tar_file {
    my( $self, $tar_file ) = @_;
    
    if ($tar_file) {
        $self->{'_tar_file'} = $tar_file;
    }
    elsif (! $self->{'_tar_file'}) {
        my $root = $ENV{'LACE_LOCAL'} || '/nfs/humace2/hum/data';
        my $file = 'lace_acedb.tar';
        $self->{'_tar_file'} = "$root/$file";
    }
    return $self->{'_tar_file'};
}

sub tace {
    my( $self, $tace ) = @_;
    
    if ($tace) {
        $self->{'_tace'} = $tace;
    }
    return $self->{'_tace'} || 'tace';
}

sub error_flag {
    my( $self, $error_flag ) = @_;
    
    if (defined $error_flag) {
        $self->{'_error_flag'} = $error_flag;
    }
    return $self->{'_error_flag'};
}

sub add_acefile {
    my( $self, $ace ) = @_;
    
    my $af = $self->{'_acefile_list'} ||= [];
    push(@$af, $ace);
}

sub list_all_acefiles {
    my( $self ) = @_;
    
    if (my $af = $self->{'_acefile_list'}) {
        return @$af;
    } else {
        return;
    }
}

sub write_otter_acefile {
    my( $self, $ss ) = @_;

    my $dir = $self->home;
    my $otter_ace = "$dir/rawdata/otter.ace";
    my $fh = gensym();
    open $fh, "> $otter_ace" or die "Can't write to '$otter_ace'";
    if ($ss) {
        print $fh $self->fetch_otter_ace_for_SequenceSet($ss);
    } else {
        print $fh $self->fetch_otter_ace;
    }
    close $fh or confess "Error writing to '$otter_ace' : $!";
    $self->add_acefile($otter_ace);
    $self->save_slice_dataset_hash;
}

sub fetch_otter_ace_for_SequenceSet {
    my( $self, $ss ) = @_;
    
    my $client = $self->Client
        or confess "No otter client attached";
    my( $ds );
  SEARCH: foreach my $this_ds ($client->get_all_DataSets) {
        my $ss_list = $this_ds->get_all_SequenceSets;
        foreach my $this_ss (@$ss_list) {
            if ($this_ss == $ss) {
                $ds = $this_ds;
                last SEARCH;
            }
        }
    }
    confess "Can't find DataSet that SequenceSet belongs to"
        unless $ds;
    $ds->selected_SequenceSet($ss);
    my $ctg_list = $ss->selected_CloneSequences_as_contig_list
        or confess "No CloneSequences selected";
    return $self->ace_from_contig_list($ctg_list, $ds);
}

sub fetch_otter_ace {
    my( $self ) = @_;

    my $client = $self->Client or confess "No otter Client attached";
    
    my $ace = '';
    my $selected_count = 0;
    foreach my $ds ($client->get_all_DataSets) {
        my $ss_list = $ds->get_all_SequenceSets;
        foreach my $ss (@$ss_list) {
            if (my $ctg_list = $ss->selected_CloneSequences_as_contig_list) {
                $ds->selected_SequenceSet($ss);
                $ace .= $self->ace_from_contig_list($ctg_list, $ds);
                foreach my $ctg (@$ctg_list) {
                    $selected_count += @$ctg;
                }
            }
        }
    }
    
    if ($selected_count) {
        return $ace;
    } else {
        return;
    }
}

sub ace_from_contig_list {
    my( $self, $ctg_list, $ds ) = @_;
    
    my $client = $self->Client or confess "No otter Client attached";
    
    my $ace = '';
    foreach my $ctg (@$ctg_list) {
        my $xml = Bio::Otter::Lace::TempFile->new;
        $xml->name('lace.xml');
        my $write = $xml->write_file_handle;
        print $write $client->get_xml_for_contig_from_Dataset($ctg, $ds);

        ### Nasty that genes and slice arguments are in
        ### different order in these two subroutines
        my ($genes, $slice, $sequence, $tiles, $feature_set) =
            Bio::Otter::Converter::XML_to_otter($xml->read_file_handle);
        $ace .= Bio::Otter::Converter::otter_to_ace($slice, $genes, $tiles, $sequence, $feature_set);

        # We need to record which dataset each slice came
        # from so that we know where to save it back to.
        my $slice_name = $slice->display_id;
        $self->save_slice_dataset($slice_name, $ds);
    }
    return $ace;
}

sub save_slice_dataset {
    my( $self, $slice_name, $dataset ) = @_;
    
    $self->{'_slice_name_dataset'}{$slice_name} = $dataset;
}

sub slice_dataset_hash {
    my $self = shift;
    
    confess "slice_dataset_hash method is read-only" if @_;
    
    my $h = $self->{'_slice_name_dataset'};
    unless ($h) {
        warn "Creating empty hash";
        $h = $self->{'_slice_name_dataset'} = {};
    }
    return $h;
}

# Makes hash persistent for "lace -recover"
# (Could store in Dataset_name tag in database?)
sub save_slice_dataset_hash {
    my( $self ) = @_;
    
    my $h    = $self->slice_dataset_hash;
    my $file = $self->slice_dataset_hash_file;
    
    my $fh = gensym();
    open $fh, "> $file" or confess "Can't write to file '$file' : $!";
    while (my ($slice, $ds) = each %$h) {
        my $ds_name = $ds->name;
        $slice =~ s/\t/\\t/g;   # Escape tab characterts in slice name (v. unlikely)
        print $fh "$slice\t$ds_name\n";
    }
    close $fh;
}

sub recover_slice_dataset_hash {
    my( $self ) = @_;
    
    my $cl   = $self->Client or confess "No Otter Client attached";
    my $h    = $self->slice_dataset_hash;
    my $file = $self->slice_dataset_hash_file;
    
    my $fh = gensym();
    open $fh, $file or confess "Can't read file '$file' : $!";
    while (<$fh>) {
        chomp;
        my ($slice, $ds_name) = split /\t/, $_, 2;
        $slice =~ s/\\t/\t/g;   # Unscape tab characterts in slice name (v. unlikely)
        my $ds = $cl->get_DataSet_by_name($ds_name);
        $h->{$slice} = $ds;
    }
    close $fh;
}

sub slice_dataset_hash_file {
    my( $self ) = @_;
    
    return $self->home . '/.slice_dataset';
}

sub save_all_slices {
    my( $self ) = @_;
    
    warn "SAVING ALL SLICES";
    
    # Make sure we don't have a stale database handle
    $self->drop_aceperl_db_handle;

    my $sd_h = $self->slice_dataset_hash;
    #warn "HASH = '$sd_h' has ", scalar(keys %$sd_h), " elements";
    ### This call to each was failing to return anything
    ### the second time it was called!!!
    #while (my ($name, $ds) = each %$sd_h) {
    foreach my $name (keys %$sd_h) {
        my $ds = $sd_h->{$name};
        warn "SAVING SLICE '$name'";
        $self->save_otter_slice($name, $ds);
    }
}

sub save_otter_slice {
    my( $self, $name, $dataset ) = @_;
    
    confess "Missing slice name argument"   unless $name;
    confess "Missing DatsSet argument"      unless $dataset;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";
    
    # Get the Genome_Sequence object ...
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');

    # ... its SubSequences ...
    $ace->raw_query('query follow SubSequence where ! CDS_predicted_by');
    $ace_txt .= $ace->raw_query('show -a');

    # ... and all the Loci attached to the SubSequences.
    $ace->raw_query('Follow Locus');
    $ace_txt .= $ace->raw_query('show -a');
    $ace->find(Person => '*');  # For Authors
    $ace_txt .= $ace->raw_query('show -a');

    # Then get the information for the TilePath
    $ace->find(Genome_Sequence => $name);
    $ace->raw_query('Follow AGP_Fragment');
    $ace_txt .= $ace->raw_query('show -a');
    ### Do show -a on a restricted list of tags
    
    # Cleanup text
    $ace_txt =~ s/\0//g;            # Remove nulls
    $ace_txt =~ s{^\s*//.+}{\n}mg;  # Strip comments
    
    #my $debug_file = "/tmp/otter-debug.$$.ace";
    #open DEBUG, ">> $debug_file" or die;
    #print DEBUG $ace_txt;
    #close DEBUG;
    
    return $client->save_otter_ace($ace_txt, $dataset);
}

sub unlock_all_slices {
    my( $self ) = @_;

    my $sd_h = $self->slice_dataset_hash;
    while (my ($name, $ds) = each %$sd_h) {
        $self->unlock_otter_slice($name, $ds);
    }
}

sub unlock_otter_slice {
    my( $self, $name, $dataset ) = @_;
    
    confess "Missing slice name argument"   unless $name;
    confess "Missing DatsSet argument"      unless $dataset;

    my $ace    = $self->aceperl_db_handle;
    my $client = $self->Client or confess "No Client attached";
    
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');

    $ace->find(Genome_Sequence => $name);
    $ace->raw_query('Follow AGP_Fragment');
    $ace_txt .= $ace->raw_query('show -a');
    
    # Cleanup text
    $ace_txt =~ s/\0//g;            # Remove nulls
    $ace_txt =~ s{^\s*//.+}{\n}mg;  # Strip comments
    
    return $client->unlock_otter_ace($ace_txt, $dataset);
}

sub aceperl_db_handle {
    my( $self ) = @_;
    
    my( $dbh );
    unless ($dbh = $self->{'_aceperl_db_handle'}) {
        my $home = $self->home;
        my $tace = $self->tace;
        $dbh = $self->{'_aceperl_db_handle'}
            = Ace->connect(-PATH => $home, -PROGRAM => $tace)
                or confess "Can't connect to database in '$home': ", Ace->error;
    }
    return $dbh;
}

sub drop_aceperl_db_handle {
    my( $self ) = @_;
    
    $self->{'_aceperl_db_handle'} = undef;
}

sub make_database_directory {
    my( $self ) = @_;
    
    my $home = $self->home;
    my $tar  = $self->tar_file;
    mkdir($home, 0777) or die "Can't mkdir('$home') : $!\n";
    
    my $tar_command = "cd $home ; tar xf $tar";
    if (system($tar_command) != 0) {
        $self->error_flag(1);
        confess "Error running '$tar_command' exit($?)";
    }
    
    # These two acefiles from the tar file need to get parsed
    $self->add_acefile("$home/rawdata/methods.ace");
    $self->add_acefile("$home/rawdata/misc.ace");
    
    $self->make_passwd_wrm;
    $self->edit_displays_wrm;
}

sub make_passwd_wrm {
    my( $self ) = @_;

    my $passWrm = $self->home . '/wspec/passwd.wrm';
    my ($prog) = $0 =~ m{([^/]+)$};
    my $real_name      = ( getpwuid($<) )[0];
    my $effective_name = ( getpwuid($>) )[0];

    my $fh = gensym();
    sysopen($fh, $passWrm, O_CREAT | O_WRONLY, 0644)
        or confess "Can't write to '$passWrm' : $!";
    print $fh "// PASSWD.wrm generated by $prog\n\n";

    # acedb looks at the real user ID, but some
    # versions of the code seem to behave differently
    if ( $real_name ne $effective_name ) {
        print $fh "root\n\n$real_name\n\n$effective_name\n\n";
    }
    else {
        print $fh "root\n\n$real_name\n\n";
    }

    close $fh;    # Must close to ensure buffer is flushed into file
}

sub edit_displays_wrm {
    my( $self ) = @_;
    
    my $home  = $self->home;
    my $title = $self->title;
    
    my $displays = "$home/wspec/displays.wrm";

    my $disp_in = gensym();
    open $disp_in, $displays or confess "Can't read '$displays' : $!";
    my @disp = <$disp_in>;
    close $disp_in;

    foreach (@disp) {
        next unless /^_DDtMain/;

        # Add our title onto the Main window
        s/\s-t\s*"[^"]+/ -t "$title/i;
        last;
    }

    my $disp_out = gensym();
    open $disp_out, "> $displays" or confess "Can't write to '$displays' : $!";
    print $disp_out @disp;
    close $disp_out;
}


sub initialize_database {
    my( $self ) = @_;
    
    my $home = $self->home;
    my $tace = $self->tace;
    my @parse_commands = map "parse $_\n",
        $self->list_all_acefiles;

    my $parse_log = "$home/init_parse.log";
    my $pipe = "| $tace $home > $parse_log";
    
    my $pipe_fh = gensym();
    open $pipe_fh, $pipe
        or die "Can't open pipe '$pipe' : $!";
    # Say "yes" to "initalize database?" question.
    print $pipe_fh "y\n";
    foreach my $com (@parse_commands) {
        print $pipe_fh $com;
    }
    close $pipe_fh or die "Error initializing database exit($?)\n";

    my $fh = gensym();
    open $fh, $parse_log or die "Can't open '$parse_log' : $!";
    my $file_log = '';
    my $in_parse = 0;
    my $errors = 0;
    while (<$fh>) {
        if (/parsing/i) {
            $file_log = "  $_";
            $in_parse = 1;
        }
        
        if (/(\d+) (errors|parse failed)/i) {
            if ($1) {
                warn "\nParse error detected:\n$file_log  $_\n";
                $errors++;
            }
        }
        elsif (/Sorry/) {
            warn "Apology detected:\n$file_log  $_\n";
            $errors++;
        }
        elsif ($in_parse) {
            $file_log .= "  $_";
        }
    }
    close $fh;

    return $errors ? 0 : 1;
}

sub write_pipeline_data {
    my( $self, $ss ) = @_;

    my $dataset = $self->Client->get_DataSet_by_name($ss->dataset_name);
    $dataset->selected_SequenceSet($ss);    # Not necessary?
    my $ens_db = Bio::Otter::Lace::PipelineDB::get_DBAdaptor(
        $dataset->get_cached_DBAdaptor
        );
    $ens_db->assembly_type($ss->name);
    my $factory = $self->make_AceDataFactory($ens_db);
    
    # create file for output and add it to the acedb object
    my $ace_file = $self->home . "/rawdata/pipeline.ace";
    $self->add_acefile($ace_file);
    my $fh = gensym();
    open $fh, "> $ace_file" or confess "Can't write to '$ace_file' : $!";
    $factory->file_handle($fh);

    my $slice_adaptor = $ens_db->get_SliceAdaptor();
    
    # note: the next line returns a 2 dimensional array (not a one dimensional array)
    # each subarray contains a list of clones that are together on the golden path
    my $sel = $ss->selected_CloneSequences_as_contig_list ;
    foreach my $cs (@$sel) {

        my $first_ctg = $cs->[0];
        my $last_ctg = $cs->[$#$cs];

        my $chr = $first_ctg->chromosome->name;  
        my $chr_start = $first_ctg->chr_start;
        my $chr_end = $last_ctg->chr_end;

        my $slice = $slice_adaptor->fetch_by_chr_start_end($chr, $chr_start, $chr_end);
        
        ### Check we got a slice
        my $tp = $slice->get_tiling_path;
        my $type = $slice->assembly_type;
        #warn "assembly type = $type";
        if (@$tp) {
            foreach my $tile (@$tp) {
                print STDERR "contig: ", $tile->component_Seq->name, "\n";
            }
        } else {
            warn "No components in tiling path";
        }

        $factory->ace_data_from_slice($slice);
    }
    $factory->drop_file_handle;
    close $fh;
}

sub make_AceDataFactory {
    my( $self, $ens_db ) = @_;

    my $percent_identity_cutoff = undef; ## change this if a cutoff value is reqired

    # create new datafactory object - cotains all ace filters and produces the data from these
    my $factory = Bio::EnsEMBL::Ace::DataFactory->new;       
#    $factory->add_all_Filters($ensdb);   
   
    
   my $ana_adaptor = $ens_db->get_AnalysisAdaptor;
   
   ##----------code to add all of the ace filters to data factory-----------------------------------
    
    my @logic_class = (
        [qw{ SubmitContig   Bio::EnsEMBL::Ace::Filter::DNA              }],
        [qw{ RepeatMask     Bio::EnsEMBL::Ace::Filter::Repeatmasker     }],
        [qw{ trf            Bio::EnsEMBL::Ace::Filter::TRF              }],
        [qw{ genscan        Bio::EnsEMBL::Ace::Filter::Gene::Predicted  }],
        [qw{ Fgenesh        Bio::EnsEMBL::Ace::Filter::Gene::Predicted  }],
        [qw{ CpG            Bio::EnsEMBL::Ace::Filter::CpG              }],
        );

    foreach my $lc (@logic_class) {
        my ($logic_name, $class) = @$lc;
        if (my $ana = $ana_adaptor->fetch_by_logic_name($logic_name)) {
            my $filt = $class->new;
            $filt->analysis_object($ana);
            $factory->add_AceFilter($filt);
        } else {
            warn "No analysis called '$logic_name'\n";
        }
    }
    
    #halfwise
    if (my $ana = $ana_adaptor->fetch_by_logic_name('Pfam')) {
        my $halfwise = Bio::EnsEMBL::Ace::Filter::Gene::Halfwise->new;
        $halfwise->url_string('http\\:\\/\\/www.sanger.ac.uk\\/cgi-bin\\/Pfam\\/getacc?%s');   ##??is this still correct?
        $halfwise->analysis_object($ana);
        $factory->add_AceFilter($halfwise);
    } else {
        warn "No analysis called 'Pfam'\n";
    }

## big list for DNASimilarity / Protein_similarity

## note: most of the list here is taken from the previous version, 
## currently only the uncommented ones seem to be in the database   
    my %logic_tag_method = (
#        'Est2Genome'        => [qw{             EST_homol  EST_eg           }],
        'Est2Genome_human'  => [qw{             EST_homol  EST_Human     }],
        'Est2Genome_mouse'  => [qw{             EST_homol  EST_Mouse     }],
        'Est2Genome_other'  => [qw{             EST_homol  EST           }],
#        'Full_dbGSS'        => [qw{             GSS_homol  GSS_eg           }],
#        'Full_dbSTS'        => [qw{             STS_homol  STS_eg           }],
#        'sccd'              => [qw{             EST_homol  egag             }],
#        'riken_mouse_cdnal' => [qw{             EST_homol  riken_mouse_cdna }],
#        'primer'            => [qw{             DNA_homol  primer           }],
        'vertrna'           => [qw{ vertebrate_mRNA_homol  vertebrate_mRNA 0 }],
#        'zfishEST'          => [qw{             EST_homol  EST_eg-fish      }],
        );
        
    foreach my $logic_name (keys %logic_tag_method) {
        if (my $ana = $ana_adaptor->fetch_by_logic_name($logic_name)) {
            my( $tag, $meth, $coverage ) = @{$logic_tag_method{$logic_name}};
            my $sim = Bio::EnsEMBL::Ace::Filter::Similarity::DnaSimilarity->new;
            #warn "setting analysis object to '$ana' for '$logic_name'\n";
            $sim->analysis_object($ana);
            $sim->homol_tag($tag);
            $sim->method_tag($meth);
            $sim->hseq_prefix('Em:');
            $sim->max_coverage($coverage);
            if ( defined($percent_identity_cutoff) ) {
                $sim->percent_identity_cutoff($percent_identity_cutoff);
            }
            $factory->add_AceFilter($sim);
#            warn 'logic_tag:' , $tag , "\n" ;
        } else{
            warn "No analysis called '$logic_name'\n";
        }
    }
    
    
    ## protein similarity
    if (my $ana = $ana_adaptor->fetch_by_logic_name('swall')) {
        my $prot_sim = Bio::EnsEMBL::Ace::Filter::Similarity::ProteinSimilarity->new;
        $prot_sim->analysis_object($ana);
        $prot_sim->homol_tag('swall');
        $prot_sim->method_tag('BLASTX');
        if( defined($percent_identity_cutoff)  ){
            $prot_sim->percent_identity_cutoff($percent_identity_cutoff);
        }
        $factory->add_AceFilter($prot_sim);    
    } else {
        warn "No analysis called 'swall'\n";
    }
    
    return $factory;
}


##  creates a data factory and adds all the appropriate filters to
##  it. It then produces a slice from the ensembl db (using the
##  $dataset coords) and produces output based on that slice in
##  ensembl.ace
sub write_ensembl_data {
    my( $self, $ss ) = @_;

    ### Analysis logic name should not be hard coded
    foreach my $key_logic (
        #    Key in meta table      Analysis logic_name
        [qw{ ensembl_core_db        ensembl    }],
        [qw{ ensembl_estgene_db     genomewise }],
        )
    {
        $self->write_ensembl_data_for_key($ss, @$key_logic);
    }
}

sub write_ensembl_data_for_key {
    my( $self, $ss, $key, $logic_name ) = @_;

    my $debug_flag = 0;

    my $dataset = $self->Client->get_DataSet_by_name($ss->dataset_name);
    $dataset->selected_SequenceSet($ss);    # Not necessary?
    my $ens_db = Bio::Otter::Lace::SatelliteDB::get_DBAdaptor(
        $dataset->get_cached_DBAdaptor, $key
        ) or return;

    # create file for output and add it to the acedb object
    my $ace_file = $self->home . "/rawdata/$key.ace";
    my $fh = gensym();
    open $fh, "> $ace_file" or confess "Can't write to '$ace_file' : $!";
    $self->add_acefile($ace_file);

    my $type = $ens_db->assembly_type;
    # later on will have to get chromsome names...not proper way to do it
    my $ch = get_all_LaceChromosomes($ens_db);

    my $factory = Bio::EnsEMBL::Ace::DataFactory->new;
    my $ana_adaptor = $ens_db->get_AnalysisAdaptor;
    my $ensembl = Bio::EnsEMBL::Ace::Filter::Gene->new;
    $ensembl->analysis_object( $ana_adaptor->fetch_by_logic_name($logic_name) );
    $factory->add_AceFilter($ensembl);

    my $slice_adaptor = $ens_db->get_SliceAdaptor();

    my $sel = $ss->selected_CloneSequences_as_contig_list;
    # unlike sanger (pipeline) databases, where data is clone based, 
    # in this case we need to deal with slice as a whole

    # Slightly smarter than rejecting entire slice if anything
    # different.  Is able to build a subslice if beginning or end
    # is incorrect, but can't build multiple subslices (all kinds
    # of duplicate partial gene problems could result in such
    # cases).

    # Since locally the agp could be correct, but globally wrong
    # has to deal with clone order walking in the wrong direction

    # Various patalogical cases are not dealt with optimally.  If
    # A matches; B doesn't but C, D, E and F match, will make a
    # subslice out of A.  Could be handelled, but would require a
    # double pass.

    foreach my $cs (@$sel) {

	my $otter_slice_name;
	{
	    # need to get name of slice in otter space (fetch from ensembl
	    # will be in a different coordinate space, but because of
	    # checks they are guarenteed to be equivalent)

	    my $first_ctg = $cs->[0];
	    my $last_ctg = $cs->[$#$cs];

	    my $chr = $first_ctg->chromosome->name;  
	    my $chr_start = $first_ctg->chr_start;
	    my $chr_end = $last_ctg->chr_end;
	    $otter_slice_name="$chr.$chr_start-$chr_end";
	}

	# check if agp of this DB is in sync for the selected clones
	# dump if in sync, else skip
	my $off=0;
	my $first=-1;
	my $first_dir;
	my $last;
	my $last_edge;
	my $slice_start;
	my $slice_end;
	my $fail;
	my $chr;
	for (my $i=0; $i < @$cs; $i++) {
	    my $ctg= $cs->[$i];

	    my $ens_ctg_set=get_LaceCloneSequence_by_sv($ens_db,$ch,
						      $ctg->accession,$ctg->sv,$type,
                                                      $debug_flag);
	    my $pass=0;
	    # should get only one match (present, but not unfinished)
	    if(scalar(@$ens_ctg_set)==1){
		my $ens_ctg=$ens_ctg_set->[0];
		# check if same part of contig is part of external agp
		if($ens_ctg->contig_start==$ctg->contig_start &&
		   $ens_ctg->contig_end==$ctg->contig_end
		   ){
		    print "DEBUG: same contig used\n" if $debug_flag;
		    # if first clone, save; else check order is still ok
		    if($first>-1){
			$fail=1;
			# check sequential
			if($i=$last+1){
			    # check consistent direction
			    my $this_dir=-1;
			    if($ens_ctg->contig_strand==$ctg->contig_strand){
				$this_dir=1;
			    }
			    if($first_dir==$this_dir){
				# check agp consecutive
				if($first_dir==1 && $ens_ctg->chr_start==$last_edge+1){
				    $last=$i;
				    $last_edge=$ens_ctg->chr_end;
				    $slice_end=$ens_ctg->chr_end;
				    $fail=0;
				}elsif($first_dir==-1 && $ens_ctg->chr_end==$last_edge-1){
				    # -ve direction not handled...so
				    confess "ERR: should never get here!!";
				}
			    }
			}
		    }else{
			print "DEBUG: saved first $i\n" if $debug_flag;
			$first=$i;
			$last=$i;
			$chr=$ens_ctg->chromosome->name;  
			if($ens_ctg->contig_strand==$ctg->contig_strand){
			    # same direction
			    $last_edge=$ens_ctg->chr_end;
			    $slice_start=$ens_ctg->chr_start;
			    $slice_end=$ens_ctg->chr_end;
			    $first_dir=1;
			}else{
			    $last_edge=$ens_ctg->chr_start;
			    $slice_start=$ens_ctg->chr_end;
			    $slice_end=$ens_ctg->chr_start;
			    $first_dir=-1;
			    # reverse direction

			    # FIXME temporary:
			    print "WARN: agp is in reverse direction";
			    print " - not currently handled\n";
			    $first=-1;

			}
		    }
		}
	    }
	    # right now, if $first not set for $i=0 can't continue
	    if($i==0 && $first==-1){$fail=1;}
	    # once started a slice with first, if fail then no point checking further
	    last if $fail;
	}
	# if something was saved
	if($first>-1){
	    print "DEBUG: Fetching slice $first:$slice_start-$last:$slice_end\n" if $debug_flag;
	    my $slice = $slice_adaptor->fetch_by_chr_start_end($chr, $slice_start, $slice_end);
	    $slice->name($otter_slice_name);
	    print $fh $factory->ace_data_from_slice($slice);
	}
    }
    close $fh;
}


# look for contigs for this sv
sub get_LaceCloneSequence_by_sv{
    my($dba,$ch,$acc,$sv,$type, $debug_flag)=@_;
    print "DEBUG: checking $acc,$sv,$type\n" if $debug_flag;
    my %id_chr = map {$_->chromosome_id, $_} @$ch;
    my $sth = $dba->prepare(q{
        SELECT a.chromosome_id
          , a.chr_start
          , a.chr_end
          , a.contig_start
	  , a.contig_end
          , a.contig_ori
	FROM assembly a
	  , clone cl
	  , contig c
        WHERE cl.embl_acc= ?
          AND cl.embl_version= ?
	  AND cl.clone_id=c.clone_id
	  AND c.contig_id=a.contig_id
          AND a.type = ?
        });
    $sth->execute($acc,$sv,$type);
    my( $chr_id,
	$chr_start, $chr_end,
	$contig_start, $contig_end, $strand );
    $sth->bind_columns( \$chr_id,
			\$chr_start, \$chr_end,
			\$contig_start, \$contig_end, \$strand );
    my $cs = [];
    while ($sth->fetch) {
	my $cl=Bio::Otter::Lace::CloneSequence->new;
	#$cl->accession($acc);
	#$cl->sv($sv);
	#$cl->length($ctg_length);
	$cl->chromosome($id_chr{$chr_id});
	$cl->chr_start($chr_start);
	$cl->chr_end($chr_end);
	$cl->contig_start($contig_start);
	$cl->contig_end($contig_end);
	$cl->contig_strand($strand);
	#$cl->contig_name($ctg_name);
	push(@$cs, $cl);
	print "DEBUG: $chr_start-$chr_end; $contig_start-$contig_end\n" if $debug_flag;
    }
    return $cs;
}


sub get_all_LaceChromosomes {
    my($dba)=@_;
    my($ch);
    my $sth = $dba->prepare(q{
	SELECT chromosome_id
	    , name
	    , length
	FROM chromosome
	});
    $sth->execute;
    my( $chr_id, $name, $length );
    $sth->bind_columns(\$chr_id, \$name, \$length);
        
    while ($sth->fetch) {
	my $chr = Bio::Otter::Lace::Chromosome->new;
	$chr->chromosome_id($chr_id);
	$chr->name($name);
	$chr->length($length);
	push(@$ch, $chr);
    }
    return($ch);
}


sub DESTROY {
    my( $self ) = @_;
    
    my $home = $self->home;
    if ($self->error_flag) {
        warn "Not cleaning up '$home' because error flag is set\n";
        return;
    }

    rmtree($home);
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::AceDatabase

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

