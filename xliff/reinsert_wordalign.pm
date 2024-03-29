#!/usr/bin/perl -w
package reinsert_wordalign;
run() unless caller();

#
# Reinsertion of markup from source InlineText into plain text translated
# with Moses, output and input are expected to be UTF-8 encoded
# (without leading byte-order mark)
#
# Copyright 2011-2012 Digital Silk Road
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Lesser General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#

use strict;
use Getopt::Std;

sub run {
    binmode( STDIN,  ":utf8" );
    binmode( STDOUT, ":utf8" );

    # MTM: Adding a second argument for the word alignment trace (in a separate file)
    # MTM: Please note that the target is no longer traced with phrase alignment
    if ( @ARGV != 2 ) {
        die "Usage: perl $0 source_tokenized_InlineText_file wordalignment_trace < target > target_InlineText_file\n";
    }

    open( my $ifh, "<:utf8", $ARGV[0] );
    open( my $wah, "<:utf8", $ARGV[1] );

    # Read line from InlineText file
    while (<$ifh>) {
        my @elements = extract_inline($_);

        # MTM: Read alignment from wordalignment_trace:
        if ( my $aligntrace = <$wah> ) {
            my @wordalign = extract_wordalign($aligntrace);

            if ( my $target = <STDIN> ) {
                print reinsert_elements( $target, \@elements, \@wordalign );
                print "\n";
            }
            else {
                die "\nTarget file has fewer lines than source file";
            }
        }
        else {
            die "\nWord alignment file has fewer lines than source file";
        }
    }

    close($ifh);
    close($wah);
}

sub extract_inline {
    my $inline = shift;
    my @elements;
    my $i = 0;

    my $inline_tags = "(g|x|bx|ex|lb|mrk)";
    while ( $inline =~ /\G(.*?)<(\/?)$inline_tags(\s|\/?.*?)?>/g ) {
        my @tokens_before = split ' ', $1;
        my $num_tokens = scalar(@tokens_before);
        $i += $num_tokens;
        my $tag_text = defined $4 ? $3 . $4 : $3;

        # opening or isolated tags
        if ( $2 ne '/' ) {
            push @elements, { 'el' => $3, 's' => $i, 'txt' => "<$tag_text>" };
        }

        # closing tags
        else {
            # find the last corresponding opening tag in the list
            for ( my $j = $#elements ; $j >= 0 ; $j-- ) {
                if (   $elements[$j]->{'el'} eq $3 && exists( $elements[$j]->{'s'} ) && !exists( $elements[$j]->{'ct'} ) ) {
                    push @elements, {'el'  => $3,'e'   => $i - 1,'txt' => "</$tag_text>",'ot'  => $j,'gap' => $i - $elements[$j]->{'s'}};
                    $elements[$j]->{'ct'} = $#elements;
                    last;
                }
            }
        }
    }
    return @elements;
}

#	Routine to extract word alignment information from a Moses alignment file; something like: "0-0 0-1 0-2 1-3 1-4 1-5 2-7 2-8"
# 	The alignments are stored in an array with id = source position, start target position, end target position,
# 	in case there are one-to-many alignments
sub extract_wordalign {
    my $inline = shift;
    my @alignment;

    my @raw = split ' ', $inline;

    foreach my $r (@raw) {
        my ( $sourcep, $targetp ) = split( '-', $r, 2 );

        # If the element does not exist, we add it @ id (source position), and start = end (target position)
        if ( !defined $alignment[$sourcep]->{'start'} ) {
            $alignment[$sourcep]->{'start'} = $targetp;
            $alignment[$sourcep]->{'end'}   = $targetp;
        }
        # Otherwise, we need to update 'end' with new alignment.
        else {
            $alignment[$sourcep]->{'end'} = $targetp;
        }
    }
    return @alignment;
}

sub reinsert_elements {
    # MTM: Passing two arrays instead of just one
    my $traced_target = shift;
    my ( $x1, $x2 ) = @_;
    my @elements  = @$x1;
    my @wordalign = @$x2;

    my %added;

    my $target = "";
    my $i;
    my %pending_close;

    # MTM: We'll work with an array of tokens, insted of phrases
    my @phrase = split ' ', $traced_target;
    $phrase[0] = "" if ( $#phrase == -1 );

    # MTM: We should probably calculate all the starting and ending positions well before iterating
    @wordalign = recalculate_pos( \@phrase, \@elements, \@wordalign );

    for my $u ( 0 .. $#phrase ) {
        my $content = $phrase[$u];
        my @trace_elements = ();

        # Determine which inline elements are opened or closed in the current trace
        foreach $i ( 0 .. $#elements ) {
            if ( exists $elements[$i]->{s} ) {
                if ( $u eq $elements[$i]->{wa} ) {
                    push @trace_elements, $i;
                    $added{$i} = 1;

                    # Check if corresponding closing element is expecting close
                    if ( exists $elements[$i]->{ct} && $pending_close{ $elements[$i]->{ct} } ) {
                        push @trace_elements, $elements[$i]->{ct};
                        $added{ $elements[$i]->{ct} } = 1;

                        # Eliminate gap for closing elements emitted late
                        $elements[ $elements[$i]->{ct} ]->{gap} = 0;
                        delete $pending_close{ $elements[$i]->{ct} };
                    }
                }
            } else {
                if ( $u eq $elements[$i]->{wa} ) {

                    # Corresponding opening tag already emmitted?
                    if ( $added{ $elements[$i]->{ot} } ) {
                        push @trace_elements, $i;
                        $added{$i} = 1;
                    }
                    else {
                        $pending_close{$i} = 1;
                    }
                }
            }
        }

        # Emit tags and content for trace
        my $content_emitted = 0;
        foreach $i (@trace_elements) {
            if (   !$content_emitted && exists $elements[$i]->{gap} && $elements[$i]->{gap} ){
                $target .= $content . " ";
                $content_emitted = 1;
            }
            $target .= $elements[$i]->{txt} . " ";
        }
        if ( !$content_emitted ) {
            $target .= $content . " ";
        }
    }

    # Emit the elements that weren't added yet to the end of the target
    # TBD: This really should not be necessary, if the algorithm is working
    foreach $i ( grep( !$added{$_}, 0 .. $#elements ) ) {
        $target .= $elements[$i]->{txt} . " ";
    }

    $target =~ s/\s$//;
    return $target;
}

sub recalculate_pos {

    my ( $x1, $x2, $x3 ) = @_;
    my @phrase    = @$x1;
    my @elements  = @$x2;
    my @wordalign = @$x3;

    foreach my $i ( 0 .. $#elements ) {
        # Opening pair tag AND correspoding closing tag at once
		# Calculate the lowest and highest insertion point considering all the words inside the pair
        if ( exists $elements[$i]->{ct} ) {
            my $ss = $elements[$i]->{s};
            my $se = $elements[ $elements[$i]->{ct} ]->{e};

			# Initialize with first source token alignment
            my ( $ts, $te ) = findalign( $ss, @wordalign );
            
            if ( $elements[ $elements[$i]->{ct} ]->{gap} > 0 ){
            	# Iterate through the tokens in the tag pair
            	for my $j ( $ss .. $se ) {
	                my ( $temps, $tempe ) = findalign( $j, @wordalign );
                	if ( $temps < $ts ) { $ts = $temps; }
                	if ( $tempe > $te ) { $te = $tempe; }
	            }
            } else {
            	$te = $ts;
            }
			
			# Update 'wordalignment' with lower/higher alignments
            $elements[$i]->{'wa'} = $ts;
            $elements[ $elements[$i]->{ct} ]->{'wa'} = $te;
        }

        # Normal standalone tag
        elsif ( exists $elements[$i]->{s} ) {
            my ( $temps, $tempe ) = findalign( $elements[$i]->{s}, @wordalign );
            $elements[$i]->{'wa'} = $temps;
        }
    }
    return @wordalign;
}

# findalign($source, @wordaling) will return a valid start/end position for the provided source token
# If there is no existing word alignment, it will return the next valid word alignment
sub findalign {
    my $source_token = shift;
    my @wordalign    = @_;

    my $target_start;
    my $target_end;

    if ( $source_token <= $#wordalign ) {
        if ( defined $wordalign[$source_token]->{start} ) {
            $target_start = $wordalign[$source_token]->{start};
            $target_end   = $wordalign[$source_token]->{end};
        } else {
            # This is a case where a token has no alignment information. Move on to the next one.
            ( $target_start, $target_end ) = findalign( $source_token + 1, @wordalign );
        }
    } else {
        # This should force reinsert sub to put elements out of wordalign at the very end
        $target_start = -1;
        $target_end   = -1;
    }
    return ( $target_start, $target_end );
}

1;

__END__

=head1 NAME

reinsert_wordalign.pm: Reinsert markup from source InlineText into translation - using word alignment information

=head1 USAGE

    perl reinsert_wordalign.pm source_tokenized_InlineText_file traced_wordalignment < target > target_tokenized_InlineText_file

Script to reinsert markup from source InlineText into plain text Moses output
with traces (traces are phrase alignment information). 

C<source_tokenized_InlineText_file> is expected to be a tokenized version of the 
InlineText file format output by the Moses Text Filter of 
L<Okapi|http://okapi.opentag.com>. 

C<traced_wordalignment> is an additional output output file from the Moses decoder
invoked with the C<-alignment-output-file> option. It contains the word alignment for
the decoded translation, one segment per line, aligned with source and target output.
C<reinsert.pm> uses this information to insert XLIFF inline elements roughly at the 
correct positions in the target text.

C<target> is the output of the Moses decoder invoked with the C<-t> 
option. 

The output C<target_tokenized_InlineText_file> is a tokenized version of the
target text with XLIFF inline elements inserted. Detokenization still needs
to be applied where appropriate.

The script follows these principles when reinserting inline elements:

=over

=item 1. All inline elements that are present in the source text have to be placed in the target text

=item 2. For paired inline elements the closing tag always has to be placed after the opening tag

=item 3. Multiple paired inline elements can only enclose each other, they cannot overlap (this is required by XML) 

=item 4. Opening tags of inline elements are to be placed as close as possible before the correct target word token

=item 5. Closing tags of inline elements are to be placed as close as possible after the correct target word token (unless this violates constraint 2.)

=back

Input is expected to be UTF-8 encoded (without a leading byte-order 
mark U+FEFF) and output will be UTF-8 encoded as well. 

