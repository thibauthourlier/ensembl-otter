package Bio::Otter::AnnotatedGene;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Gene;

@ISA = qw(Bio::EnsEMBL::Gene);

sub new {
  my($class,@args) = @_;

  my $self = $class->SUPER::new(@args);
  
  my ($gene_info)  = $self->_rearrange([qw(
					   INFO
					   )],@args);
  
  $self->gene_info($gene_info);

  return $self;
}

=head2 gene_info

 Title   : gene_info
 Usage   : $obj->gene_info($newval)
 Function: 
 Example : 
 Returns : value of gene_info
 Args    : newvalue (optional)


=cut

sub gene_info {
   my ($obj,$value) = @_;

   if( defined $value) {

       if ($value->isa("Bio::Otter::GeneInfo")) {
	   $obj->{'gene_info'} = $value;
       } else {
	   $obj->throw("Argument to gene_info must be a Bio::Otter::GeneInfo object.  Currently is [$value]");
       }
    }
    return $obj->{'gene_info'};

}

=head2 toXMLString

 Title   : toXMLString
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub toXMLString{
    my ($self) = shift;


# determine if gene is on a slice
    my $exons = $self->get_all_Exons;
    my $offset = 0;

    if (scalar(@$exons)) {
      my $contig = $exons->[0]->contig;
      if (defined($contig) && $contig->isa("Bio::EnsEMBL::Slice")) {
        $offset = $contig->chr_start-1;
      }
    }



    my $str = "<locus>\n";
    my $stableid = "";

    if (defined($self->stable_id)) { $stableid = $self->stable_id;}
   
    $str .= "  <stable_id>" . $stableid . "</stable_id>\n";

    my $info = $self->gene_info;

    if (defined($info)) {
        my $name = "";
        if (my $n = $info->name) {
            $name = $n->name;
        }
	$str .= "  <name>"      . $name      . "</name>\n";

        $str .= "  <known>" . $info->known_flag . "</known>\n";
        $str .= "  <truncated>" . $info->truncated_flag . "</truncated>\n";

	my @syn = $info->synonym;

	@syn = sort {$a->name cmp $b->name} @syn;

	foreach my $syn (@syn) {
	    $str .= "  <synonym>" . $syn->name . "<\/synonym>\n";
	}

        my @rem = $info->remark;
        @rem = sort {$a->remark cmp $b->remark} @rem;

	foreach my $rem (@rem) {
            my $remstr = $rem->remark;
            $remstr =~ s/\n/ /g;
	    $str .= "  <remark>" . $remstr . "</remark>\n";
	}

        if (my $author = $info->author) {
            $str .= $author->toXMLString;
        }
    }

    my @tran = @{$self->get_all_Transcripts};

    @tran = sort by_stable_id_or_name @tran;

    foreach my $tran (@tran) {
        my $tranid = "";
        if (defined($tran->stable_id)) {
           $tranid = $tran->stable_id;
        }
	$str .= "  <transcript>\n";
	$str .= "    <stable_id>$tranid</stable_id>\n";
	
	my $tinfo = $tran->transcript_info;

	if (defined($tinfo)) {

            if (my $author = $info->author) {
                $str .= $author->toXMLString;
            }

	    foreach my $remstr (sort map $_->remark, $tinfo->remark) {
                $remstr =~ s/\n/ /g;
		$str .= "    <remark>$remstr</remark>\n";
	    }
	   
            my $classname = "";
	    my $tname    = "";

            if (defined($tinfo->class)) {
               if (defined($tinfo->class->name)) {
                  $classname = $tinfo->class->name;
               }
            }
 
	    if (defined($tinfo->name)) {
		$tname = $tinfo->name;
	    }

            foreach my $method (qw{
                cds_start_not_found
                cds_end_not_found
                mRNA_start_not_found
                mRNA_end_not_found
                })
            {
                $str .= "  <$method>" . ($tinfo->$method() || 0) . "</$method>\n";
            }
	    
	    $str .= "    <transcript_class>$classname</transcript_class>\n";
	    $str .= "    <name>$tname</name>\n";
	    
            $str .= "    <evidence_set>\n";

            my @evidence = $tinfo->evidence;
            @evidence = sort {$a->name cmp $b->name} @evidence;

            foreach my $ev (@evidence) {
              $str .= "      <evidence>\n";
              $str .= "        <name>" . $ev->name . "</name>\n";
              $str .= "        <type>" . $ev->type . "</type>\n";
              $str .= "      </evidence>\n";
            }
            $str .= "    </evidence_set>\n";
	}


        my $tran_low  = undef;
        my $tran_high = undef;
        if (my $tl = $tran->translation) {
          my $strand = $tl->start_Exon->strand;
          $tran_low  = $tran->coding_region_start;
          $tran_high = $tran->coding_region_end;
          $str .= "    <translation_start>" . (($strand == 1) ? ($tran_low  + $offset) : ($tran_high + $offset)) . "</translation_start>\n";
          $str .= "    <translation_end>"   . (($strand == 1) ? ($tran_high + $offset) : ($tran_low  + $offset)) . "</translation_end>\n";
            if (my $tl_id = $tl->stable_id) {
                $str .= "    <translation_stable_id>$tl_id</translation_stable_id>\n";
            }
        }

	$str .= "    <exon_set>\n";

        my @exon = @{$tran->get_all_Exons;};

        @exon = sort {$a->start <=> $b->start} @exon;

        my $cds_snf = "";
        if (defined($tinfo->cds_start_not_found)) {
          $cds_snf = $tinfo->cds_start_not_found;
        }
	foreach my $ex (@exon) {
            my $stable_id = "";
            if (defined($ex->stable_id)) {
               $stable_id = $ex->stable_id;
            }
	    $str .= "      <exon>\n";
	    $str .= "        <stable_id>" . $stable_id . "</stable_id>\n";
	    $str .= "        <start>"     . ($ex->start+$offset)     . "</start>\n";
	    $str .= "        <end>"       . ($ex->end+$offset)       . "</end>\n";
	    $str .= "        <strand>"    . $ex->strand    . "</strand>\n";
            # Only coding exons have frame set
            ### Do we need to test for translation region - why not
            ### just rely on phase of exon, which will be -1 if non-coding?
            if (defined($tran_low) && defined($tran_high) && 
                $ex->end >= $tran_low && $ex->start <= $tran_high)
            {
                my $frame = (3 - $ex->phase) % 3;
                $str .= "        <frame>" . $frame . "</frame>\n";
            }
	    $str .= "      </exon>\n";
	}
	$str .= "    </exon_set>\n";

	$str .= "  </transcript>\n";
    }
    $str .= "</locus>\n";
    
    return $str;
}

sub by_stable_id_or_name {

  my $astableid = "";
  my $bstableid = "";

  if (defined($a->stable_id)) {$astableid = $a->stable_id;}
  if (defined($b->stable_id)) {$bstableid = $b->stable_id;}
  
  my $cmpVal = ($astableid cmp $bstableid);

  if (!$cmpVal) {
    if (!defined($b->transcript_info->name) && !defined($a->transcript_info->name)) {
      $cmpVal = 0;
    } elsif (!defined($a->transcript_info->name)) {
      $cmpVal = 1;
    } elsif (!defined($b->transcript_info->name)) {
      $cmpVal = -1;
    } else {
      $cmpVal = ($a->transcript_info->name cmp $b->transcript_info->name);
    }
  }
  return $cmpVal;
}

sub stable_id {
  my ($self,$arg) = @_;

  if (defined($arg)) {
    $self->SUPER::stable_id($arg);
    $self->gene_info->gene_stable_id($arg);
  }

  return $self->SUPER::stable_id($arg);
}



sub equals {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::AnnotatedGene")) {
	$self->throw("[$obj] not a Bio::Otter::AnnotatedGene");
    }
    
    if ($self->gene_info->equals($obj->gene_info) == 0 ) {
	print "Gene info different\n";
    } else {
	print " - Equal gene info\n";
    }
}

=head1 set_gene_type_from_transcript_classes

    $gene->set_gene_type_from_transcript_classes;

See the section on transcript classes in the
otter XML documentation.

Sets the C<type> on the gene using a decision
tree based on a list of known transcript classes.

If there is an transcript class which is unknown
by the method, but this is the only class in the
gene, then this class name is used as the gene
C<type>.  If, however, the gene contains a mix of
unknown transcript classes the method throws an
exception.

Exceptions are also thrown when the gene contains
more than one class of pseudogene transcript, and
when there are no transcript in the gene.

=cut

sub set_gene_type_from_transcript_classes {
    my( $self ) = @_;
    
    my( %class_set );
    my $pseudo_count = 0;
    my $transcripts = $self->get_all_Transcripts;
    $self->throw('No transcripts') unless @$transcripts;
    foreach my $transcript (@$transcripts) {
        my $class = $transcript->transcript_info->class->name;
        $class_set{$class}++;
        $pseudo_count++ if $class =~ /pseudo/i;
    }
    
    my @class_list = keys %class_set;
    # If there are any Pseudogene transcripts, the gene is either
    # a Pseudogene, or it is a Polymorphic locus if there are other
    # classes of transcripts present.
    if ($pseudo_count) {
        if ($pseudo_count == @$transcripts) {
            if (@class_list > 1) {
                $self->throw("Have mix of pseudogene classes in gene:\n"
                    . join('', map "  $_\n", @class_list));
            } else {
                $self->type(@class_list);
            }
        } else {
            $self->type('Polymorphic');
        }
    }
    # All genes containing protein coding transcripts are either Known or Novel_CDS
    elsif ($class_set{'Coding'}) {
        # Check for the known_flag flag on the GeneInfo object
        if ($self->gene_info->known_flag) {
            $self->type('Known');
        }
        else {
            $self->type('Novel_CDS');
        }
    }
    # Gene type is Novel_Transcript if any of these are present
    elsif ($class_set{'Transcript'}
        or $class_set{'Non_coding'}
        or $class_set{'Ambiguous_ORF'}
        or $class_set{'Immature'}
        or $class_set{'Antisense'}
        )
    {
        $self->type('Novel_Transcript');
    }
    # All remaining gene types are only expected to have one class of transcript
    elsif (@class_list != 1) {
        $self->throw("Have mix of transcript classes in gene where not expected:\n"
            . join('', map "  $_\n", @class_list));
    }
    else {
        # Gene type is the same as the transcript type
        $self->type(@class_list);
    }
}

=head1 detach_DBAdaptors

    $gene_adaptor->attach_to_Slice($gene, $slice);
    $gene->detach_DBAdaptors;
    $gene_adaptor->store($gene);

Call after C<attach_to_Slice()> and before the
C<store> gene adaptor methods so that lazy
loading methods in the gene components don't
attempt to do lazy loading during the store due
to the presence of adaptors.

=cut

sub detach_DBAdaptors {
    my( $self ) = @_;
    
    # Removes adaptors from genes, transcripts,
    # exons and translations.  May need to add
    # more components it removes adaptors from
    # if we find more lazy loading problems.

    $self->adaptor(undef);
    foreach my $tran (@{$self->get_all_Transcripts}) {
        $tran->adaptor(undef);
        foreach my $exon (@{$self->get_all_Exons}) {
            $exon->adaptor(undef);
        }
        if (my $transl = $tran->translation) {
            $transl->adaptor(undef);
        }
    }
}

1;
