#!/usr/bin/env perl
use 5.006;
use strict; use warnings;

package App::Perl::Tags;
use Getopt::Long ();
use Pod::Usage qw/pod2usage/;
use File::Find ();

use Perl::Tags;
use Perl::Tags::Hybrid;
use Perl::Tags::PPI;
use Perl::Tags::Naive::Moose; # includes ::Naive

our $VERSION = '0.02';

=head1 SYNOPSIS

  Usage: perl-tags <options> <input files or dirs...>
  Generates "perltags" files for use with your editor of choice.
  
  Options:
  -o/--outfile   Set the path/name of the output file (default: perltags)
  -d/--depth     Set the max recursion depth (recursion into "use Module", etc)
                 (default: 100 (~ infinity))
  --vars/--no-vars/--variables/--no-variables
                 Set whether variables should be indexed. (Default: yes)

=cut

sub run {
    our $Outfile = 'perltags';
    our $RecursionDepth = 100;
    our $IndexVars = 1;

    # more control is TODO
    Getopt::Long::GetOptions(
      'h|help'          => sub {pod2usage();},
      'o|outfile=s'     => \$Outfile,
      'd|depth=i'       => \$RecursionDepth,
      'vars|variables!' => \$IndexVars,
    );

    pod2usage() unless @ARGV;

    my %opts = (
      max_level    => $RecursionDepth,
      exts         => 1,
      do_variables => $IndexVars,
    );

    main($Outfile, %opts);
    exit();
}

sub main {
  my ($Outfile, %opts) = @_;

  my $ptag = Perl::Tags::Hybrid->new(
    %opts,
    taggers => [
      Perl::Tags::Naive::Moose->new( %opts ),
      Perl::Tags::PPI->new( %opts ),
    ],
  );

  my @files;
  File::Find::find(
    sub { push @files, $File::Find::name if -f $_ },
    @ARGV
  );

  $ptag->process(files => \@files);
  $ptag->output(outfile => $Outfile); 
  return;
}

=head1 AUTHOR

Copyright 2009-2014, Steffen Mueller, with contributions from osfameron

=cut

1;
