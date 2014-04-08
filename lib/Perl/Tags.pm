#!/usr/bin/perl

=head1 NAME

Perl::Tags - Generate (possibly exuberant) Ctags style tags for Perl sourcecode

=head1 SYNOPSIS

        use Perl::Tags;
        my $naive_tagger = Perl::Tags::Naive->new( max_level=>2 );
        $naive_tagger->process(
            files => ['Foo.pm', 'bar.pl'],
            refresh=>1 
        );

        print $naive_tagger; # stringifies to ctags file

Recursively follows C<use> and C<require> statements, up to a maximum
of C<max_level>.

See also L<bin/perl-tags> for a command-line script.

=head1 USAGE

There are several taggers distributed with this distribution, including:

=over 4

=item L<Perl::Tags::Naive> 

This is a more-or-less straight ripoff, slightly updated, of the original
pltags code.  This is a "naive" tagger, in that it makes pragmatic assumptions
about what Perl code usually looks like (e.g. it doesn't actually parse the
code.)  This is fast, lightweight, and often Good Enough.

This has additional subclasses such as L<Perl::Tags::Naive::Moose> to parse
Moose declarations, and L<Perl::Tags::Naive::Lib> to parse C<use lib>.

=item L<Perl::Tags::PPI>

Uses the L<PPI> module to do a deeper analysis and parsing of your Perl code.
This is more accurate, but slower.

=item L<Perl::Tags::Hybrid>

Can run multiple taggers, such as ::Naive and ::PPI, combining the results.

=back

=head1 EXTENDING

Documentation patches are welcome: in the meantime, have a look at
L<Perl::Tags::Naive> and its subclasses for a simple line-by-line method of
tagging files.  Alternatively L<Perl::Tags::PPI> uses L<PPI>'s built in
method of parsing Perl documents.

In general, you will want to override the C<get_tags_for_file> method,
returning a list of C<Perl::Tags::Tag> objects to be registered.

For recursively checking other modules, return a C<Perl::Tags::Tag::Recurse>
object, which does I<not> create a new tag in the resulting perltags file,
but instead processes the next file recursively.

=head1 FEATURES

    * Recursive, incremental tagging.
    * parses `use_ok`/`require_ok` line from Test::More

=head1 DEVELOPING WITH Perl::Tags

C<Perl::Tags> is designed to be integrated into your development
environment.  Here are a few ways to use it:

=head2 With Vim

C<Perl::Tags> was originally designed to be used with vim.  My
C<~/.vim/ftplugin/perl.vim> contains the following:

    setlocal iskeyword+=:  " make tags with :: in them useful

    if ! exists("s:defined_functions")
    function s:init_tags()
        perl <<EOF
            use Perl::Tags;
            $naive_tagger = Perl::Tags::Naive->new( max_level=>2 );
                # only go one level down by default
    EOF
    endfunction

    " let vim do the tempfile cleanup and protection
    let s:tagsfile = tempname()

    function s:do_tags(filename)
        perl <<EOF
            my $filename = VIM::Eval('a:filename');

            $naive_tagger->process(files => $filename, refresh=>1 );

            my $tagsfile=VIM::Eval('s:tagsfile');
            VIM::SetOption("tags+=$tagsfile");

            # of course, it may not even output, for example, if there's
            # nothing new to process
            $naive_tagger->output( outfile => $tagsfile );
    EOF
    endfunction

    call s:init_tags() " only the first time

    let s:defined_functions = 1
    endif

    call s:do_tags(expand('%'))

    augroup perltags
    au!
    autocmd BufRead,BufWritePost *.pm,*.pl call s:do_tags(expand('%'))
    augroup END

Note the following:

=over 4

=item *

You will need to have a vim with perl compiled in it.  Debuntu packages this as
C<vim-perl>. Alternatively you can compile from source (you'll need Perl + the
development headers C<libperl-dev>).

=item *

The C<EOF> in the examples has to be at the beginning of the line (the verbatim
text above has leading whitespace)

=back

=head2 From the Command Line

See the L<bin/perl-tags> script provided.

=head2 From other editors

Any editor that supports ctags should be able to use this output.  Documentation
and code patches on how to do this are welcome.

=head1 METHODS

=cut

package Perl::Tags;

use strict; use warnings;

use Perl::Tags::Tag;
use Data::Dumper;
use File::Spec;

use overload q("") => \&to_string;
our $VERSION = 0.28;

=head2 C<new>

L<Perl::Tags> is an abstract baseclass.  Use a class such as 
L<Perl::Tags::Naive> and instantiate it with C<new>.

    $naive_tagger = Perl::Tags::Naive->new( max_level=>2 );

Accepts the following parameters

    max_level:    levels of "use" statements to descend into, default 2
    do_variables: tag variables?  default 1 (true)
    exts:         use the Exuberant extensions

=cut

sub new {
    my $class = shift;
    my %options = (
        max_level    => 2, # go into next file, but not down the whole tree
        do_variables => 1, 
        @_);

    my $self = \%options;

    return bless $self, $class;
}

=head2 C<to_string>

A L<Perl::Tags> object will stringify to a textual representation of a ctags
file.

    print $tagger;

=cut

sub to_string {
    my $self = shift;
    my $tags = $self->{tags} or return '';
    my %tags = %$tags;

    my $s; # to test

    my @lines;

    # the structure is an HoHoA of
    #
    #   {tag_name}
    #       {file_name}
    #           [ tags ]
    #
    #   where the file_name level is to allow us to prioritize tags from
    #   first-included files (on the basis that they may well be the files we
    #   want to see first.

    my $ord = $self->{order};
    my @names = sort keys %$tags;
    for (@names) {
        my $files = $tags{$_};
        push @lines, map { @{$files->{$_}} } 
            sort { $ord->{$a} <=> $ord->{$b} } keys %$files;
    }
    return join "\n", @lines;
}

=head2 C<clean_file>

Delete all tags, but without touching the "order" seen, that way, if the tags
are recreated, they will remain near the top of the "interestingness" tree

=cut

sub clean_file {
    my ($self, $file) = @_;
    
    my $tags = $self->{tags} or die "Trying to clean '$file', but there's no tags";
    
    for my $name (keys %$tags) {
        delete $tags->{$name}{$file};
    }
    delete $self->{seen}{$file};
    # we don't delete the {order} though
}

=head2 C<output>

Save the file to disk if it has changed.  (The private C<{is_dirty}> attribute
is used, as the tags object may be made up incrementally and recursively within
your IDE.

=cut

sub output {
    my $self = shift;
    my %options = @_;
    my $outfile = $options{outfile} or die "No file to write to";

    return unless $self->{is_dirty} || ! -e $outfile;

    open (my $OUT, '>', $outfile) or die "Couldn't open $outfile for write: $!";
	binmode STDOUT, ":encoding(UTF-8)";
    print $OUT $self;
    close $OUT or die "Couldn't close $outfile for write: $!";

    $self->{is_dirty} = 0;
}

=head2 C<process>

Scan one or more Perl file for tags

    $tagger->process( 
        files => [ 'Module.pm',  'script.pl' ] 
    );
    $tagger->process(
        files   => 'script.pl',
        refresh => 1,
    );

=cut

sub process {
    my $self = shift;
    my %options = @_;
    my $files = $options{files} || die "No file passed to process";
    my @files = ref $files ? @$files : ($files);

    $self->queue( map { 
                          { file=>$_, level=>1, refresh=>$options{refresh} } 
                      } @files);

    while (my $file = $self->popqueue) {
        $self->process_item( %options, %$file );
    }
    return 1;
}

=head2 C<queue>, C<popqueue>

Internal methods managing the processing

=cut

sub queue {
    my $self = shift;
    for (@_) {
        push @{$self->{queue}}, $_ unless $_->{level} > $self->{max_level};
    }
}

sub popqueue {
    my $self = shift;
    return pop @{$self->{queue}};
}

=head2 C<process_item>, C<process_file>, C<get_tags_for_file>

Do the heavy lifting for C<process> above.  

Taggers I<must> override the abstract method C<get_tags_for_file>.

=cut

sub process_item {
    my $self = shift;
    my %options = @_;
    my $file  = $options{file} || die "No file passed to proces";

    # make filename absolute, (this could become an option if appropriately
    # refactored) but because of my usage (tags_$PID file in /tmp) I need the
    # absolute path anyway, and it prevents the file being included twice under
    # slightly different names (unless you have 2 hardlinked copies, as I do
    # for my .vim/ directory... bah)

    $file = File::Spec->rel2abs( $file ) ;

    if ($self->{seen}{$file}++) {
        return unless $options{refresh};
        $self->clean_file( $file );
    }

    $self->{is_dirty}++; # we haven't yet been written out

    $self->{order}{$file} = $self->{curr_order}++ || 0;

    $self->{current} = {
        file          => $file,
        package_name  => '',
        has_subs      => 0,
        var_continues => 0,
        level         => $options{level},
    };

    $self->process_file( $file );

    return $self->{tags};
}

sub process_file {
    my ($self, $file) = @_;

    my @tags = $self->get_tags_for_file( $file );

    $self->register( $file, @tags );
}

sub get_tags_for_file {
    use Carp 'confess';
    confess "Abstract method get_tags_for_file called";
}

=head2 C<register>

The parsing is done by a number of lightweight objects (parsers) which look for
subroutine references, variables, module inclusion etc.  When they are
successful, they call the C<register> method in the main tags object.

Note that if your tagger wants to register not a new I<declaration> but rather
a I<usage> of another module, then your tagger should return a
C<Perl::Tags::Tag::Recurse> object.  This is a pseudo-tag which causes the linked
module to be scanned in turn.  See L<Perl::Tags::Naive>'s handling of C<use>
statements as an example!

=cut

sub register {
    my ($self, $file, @tags) = @_;
    for my $tag (@tags) {
        $tag->on_register( $self ) or next;
        $tag->{pkg} ||=  $self->{current}{package_name};
        $tag->{exts} ||= $self->{exts};

        # and copy absolute file if requested
        # $tag->{file} = $file if $self->{absolute};

        my $name = $tag->{name};
        push @{ $self->{tags}{$name}{$file} }, $tag;
    }
}

##
1;

=head1 SEE ALSO

L<bin/perl-tags>

=head1 CONTRIBUTIONS

Contributions are always welcome.  The repo is in git:

    http://github.com/osfameron/perl-tags

Please fork and make pull request.  Maint bits available on request.

=over 4

=item wolverian

::PPI subclass

=item Ian Tegebo

patch to use File::Temp

=item DMITRI

patch to parse constant and label declarations

=item drbean

::Naive::Moose, ::Naive::Spiffy and ::Naive::Lib subclasses

=item Alias

prodding me to make repo public

=item nothingmuch

::PPI fixes

=item tsee

Command line interface, applying patches

=back

=head1 AUTHOR and LICENSE

    osfameron (2006-2009) - osfameron@cpan.org
                            and contributors, as above

For support, try emailing me or grabbing me on irc #london.pm on irc.perl.org

This was originally ripped off pltags.pl, as distributed with vim
and available from L<http://www.mscha.com/mscha.html?pltags#tools>
Version 2.3, 28 February 2002
Written by Michael Schaap <pltags@mscha.com>. 

This is licensed under the same terms as Perl itself.  (Or as Vim if you prefer).

=cut
