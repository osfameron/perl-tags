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

=item L<Perl::Tags::Naive::Lib>

Also parse C<use lib> lines.

=item L<Perl::Tags::PPI>

Uses the L<PPI> module to do a deeper analysis and parsing of your Perl code.

=item L<Perl::Tags::Naive::Moose>

Parse L<Moose> declarations

=back

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

=head1 METHODS

=cut

package Perl::Tags;
use strict; use warnings;
use Data::Dumper;
use File::Spec;

use overload q("") => \&to_string;
our $VERSION = 0.28;

{
    # Tags that start POD:
    my @start_tags = qw(pod head1 head2 head3 head4 over item back begin
                        end for encoding);
    my @end_tags = qw(cut);

    my $startpod = '^=(?:' . join('|', @start_tags) . ')\b';
    my $endpod = '^=(?:' . join('|', @end_tags) . ')\b';

    sub STARTPOD { qr/$startpod/ }
    sub ENDPOD { qr/$endpod/ }
}

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

=head2 C<process_item>, C<process_file>

Do the heavy lifting for C<process> above.

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

    my @parsers = $self->get_parsers(); # function refs
    
    $self->process_file( $file, @parsers );

    return $self->{tags};
}

sub process_file {
    my ($self, $file, @parsers) = @_;

    # SUPER dirty workaround for the fact that Perl::Tags::PPI simply
    # doesn't cooperate with any other parsers. This whole system
    # is flawed because you can't use several parsers together. But
    # I may be misunderstanding things. --Steffen

    my $ppi_parser;
    if (Perl::Tags::PPI->can('ppi_all')) {
        my $ppisub = Perl::Tags::PPI->can('ppi_all');
        my @tmpparsers = @parsers;
        @parsers = ();
        foreach my $parser (@tmpparsers) {
            if ("$parser" ne "$ppisub") {
                push @parsers, $parser;
            }
            else {
                $ppi_parser = $parser;
            }
        }
    }

    open (my $IN, '<', $file) or die "Couldn't open file `$file`: $!\n";

    # default line by line parsing.  Or override it

    my $start = STARTPOD;
    my $end = ENDPOD;

    while (<$IN>) {
        next if (/$start/o .. /$end/o);     # Skip over POD.
        chomp;
        my $statement = my $line = $_;
        PARSELOOP: for my $parser (@parsers) {
            my @tags = $parser->( $self, 
                                  $line, 
                                  $statement,
                                  $file );
            $self->register( $file, @tags );
        }
    }

    if (defined $ppi_parser) {
        my @tags = $ppi_parser->( $self, $file );
        $self->register( $file, @tags );
    }
}

=head2 C<register>

The parsing is done by a number of lightweight objects (parsers) which look for
subroutine references, variables, module inclusion etc.  When they are
successful, they call the C<register> method in the main tags object.

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

=head2 C<get_parsers>

Return the parses for this object.  Abstract, see L<Perl::Tags::Naive> below.

=cut

sub get_parsers {
    die "Tried to call get_parsers in virtual superclass\n";
}

package Perl::Tags::Naive;
our @ISA = qw/Perl::Tags/;

=head1 C<Perl::Tags::Naive>

A naive implementation.  That is to say, it's based on the classic C<pltags.pl>
script distributed with Perl, which is by and large a better bet than the
results produced by C<ctags>.  But a "better" approach may be to integrate this
with PPI.

=head2 Subclassing

See L<TodoTagger> in the C<t/> directory of the distribution for a fully
working example (tested in <t/02_subclass.t>).  You may want to reuse parsers
in the ::Naive package, or use all of the existing parsers and add your own.

    package My::Tagger;
    use Perl::Tags;
    our @ISA = qw( Perl::Tags::Naive );

    sub get_parsers {
        my $self = shift;
        return (
            $self->can('todo_line'),     # a new parser
            $self->SUPER::get_parsers(), # all ::Naive's parsers
            # or maybe...
            $self->can('variable'),      # one of ::Naive's parsers
        );
    }

    sub todo_line { 
        # your new parser code here!
    }
    sub package_line {
        # override one of ::Naive's parsers
    }

Because ::Naive uses C<can('parser')> instead of C<\&parser>, you
can just override a particular parser by redefining in the subclass. 

=head2 C<get_parsers>

The following parsers are defined by this module.

=over 4

=cut

sub get_parsers {
    my $self = shift;
    return (
        $self->can('trim'),
        $self->can('variable'),
        $self->can('package_line'),
        $self->can('sub_line'),
        $self->can('use_constant'),
        $self->can('use_line'),
        $self->can('label_line'),
    );
}

=item C<trim>

A filter rather than a parser, removes whitespace and comments.

=cut

sub trim {
    shift;
    # naughtily work on arg inplace
    $_[1] =~ s/#.*//;  # remove comment.  Naively
    $_[1] =~ s/^\s*//; # Trim spaces
    $_[1] =~ s/\s*$//;

    return;
}

=item C<variable>

Tags definitions of C<my>, C<our>, and C<local> variables.

Returns a L<Perl::Tags::Tag::Var> if found

=cut

sub variable {
    # don't handle continuing thingy for now
    my ($self, $line, $statement, $file) = @_;

    return unless $self->{do_variables}; 
        # I'm not sure I see this as all that useful

    if ($self->{var_continues} || $statement =~/^(my|our|local)\b/) {

        $self->{current}{var_continues} = ! ($statement=~/;$/);
        $statement =~s/=.*$//; 
            # remove RHS with extreme prejudice
            # and also not accounting for things like
            # my $x=my $y=my $z;

        my @vars = $statement=~/[\$@%]((?:\w|:)+)\b/g;

        # use Data::Dumper;
        # print Dumper({ vars => \@vars, statement => $statement });

        return map { 
            Perl::Tags::Tag::Var->new(
                name => $_,
                file => $file,
                line => $line,
                linenum => $.,
            ); 
        } @vars;
    }
    return;
}

=item C<package_line>

Parse a package declaration, returning a L<Perl::Tags::Tag::Package> if found.

=cut

sub package_line {
    my ($self, $line, $statement, $file) = @_;

    if ($statement=~/^package\s+((?:\w|:)+)\b/) {
        return (
            Perl::Tags::Tag::Package->new(
                name => $1,
                file => $file,
                line => $line,
                linenum => $.,
            )
        );
    }
    return;
}

=item C<sub_line>

Parse the declaration of a subroutine, returning a L<Perl::Tags::Tag::Sub> if found.

=cut

sub sub_line {
    my ($self, $line, $statement, $file) = @_;
    if ($statement=~/sub\s+(\w+)\b/) {
        return (
            Perl::Tags::Tag::Sub->new(
                name => $1,
                file => $file,
                line => $line,
                linenum => $.,
            )
        );
    }

    return;
}

=item C<use_constant>

Parse a use constant directive

=cut

sub use_constant {
    my ($self, $line, $statement, $file) = @_;
    if ($statement =~/^\s*use\s+constant\s+([^=[:space:]]+)/) {
        return (
            Perl::Tags::Tag::Constant->new(
                name    => $1,
                file    => $file,
                line    => $line,
                linenum => $.,
            )
        );
    }
    return;
}

=item C<use_line>

Parse a use, require, and also a use_ok line (from Test::More).
Uses a dummy tag (L<Perl::Tags::Tag::Recurse> to do so).

=cut

sub use_line {
    my ($self, $line, $statement, $file) = @_;

    my @ret;
    if ($statement=~/^(?:use|require)(_ok\(?)?\s+(.*)/) {
        my @packages = split /\s+/, $2; # may be more than one if base
        @packages = ($packages[0]) if $1; # if use_ok ecc. from Test::More

        for (@packages) {
            s/^q[wq]?[[:punct:]]//;
            /((?:\w|:)+)/;
            $1 and push @ret, Perl::Tags::Tag::Recurse->new( 
                name => $1, 
                line=>'dummy' );
        }
    }
    return @ret;
}

=item C<label_line>

Parse label declaration

=cut

sub label_line {
    my ($self, $line, $statement, $file) = @_;
    if ($statement=~/^\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:(?:[^:]|$)/) {
        return (
            Perl::Tags::Tag::Label->new(
                name    => $1,
                file    => $file,
                line    => $line,
                linenum => $.,
            )
        );
    }
    return;
}

=back

=head1 C<Perl::Tags::Tag>

A superclass for tags

=cut

package Perl::Tags::Tag;

use overload q("") => \&to_string;

=head2 C<new>

Returns a new tag object

=cut

sub new {
    my $class = shift;
    my %options = @_;

    $options{type} = $class->type;

    # chomp and escape line
    chomp (my $line = $options{line});

    $line =~ s{\\}{\\\\}g;
    $line =~ s{/}{\\/}g;
    # $line =~ s{\$}{\\\$}g;

    my $self = bless {
        name   => $options{name},
        file   => $options{file},
        type   => $options{type},
        is_static => $options{is_static},
        line   => $line,
        linenum => $options{linenum},
        exts   => $options{exts}, # exuberant?
        pkg    => $options{pkg},  # package name
    }, $class;

    $self->modify_options();
    return $self;
}

=head2 C<type>, C<modify_options>

Abstract methods

=cut

sub type {
    die "Tried to call 'type' on virtual superclass";
}

sub modify_options { return } # no change

=head2 C<to_string>

A tag stringifies to an appropriate line in a ctags file.

=cut

sub to_string {
    my $self = shift;

    my $name = $self->{name} or die;
    my $file = $self->{file} or die;
    my $line = $self->{line} or die;
    my $linenum = $self->{linenum};
    my $pkg  = $self->{pkg} || '';

    my $tagline = "$name\t$file\t/$line/";

    # Exuberant extensions
    if ($self->{exts}) {
        $tagline .= qq(;"\t$self->{type});
        $tagline .= "\tline:$linenum";
        $tagline .= ($self->{is_static} ? "\tfile:" : '');
        $tagline .= ($self->{pkg} ? "\tclass:$self->{pkg}" : '');
    }
    return $tagline;
}

=head2 C<on_register>

Allows tag to meddle with process when registered with the main tagger object.
Return false if want to prevent registration (true normally).`

=cut

sub on_register {
    # my $self = shift;
    # my $tags = shift;
    # .... do stuff in subclasses

    return 1;  # or undef to prevent registration
}

=head1 C<Perl::Tags::Tag::Package>

=head2 C<type>: p

=head2 C<modify_options>

Sets static=0

=head2 C<on_register>

Sets the package name

=cut

package Perl::Tags::Tag::Package;
our @ISA = qw/Perl::Tags::Tag/;

    # QUOTE:
        # Make a tag for this package unless we're told not to.  A
        # package is never static.

sub type { 'p' }

sub modify_options {
    my $self = shift;
    $self->{is_static} = 0;
}

sub on_register {
    my ($self, $tags) = @_;
    $tags->{current}{package_name} = $self->{name};
}

=head1 C<Perl::Tags::Tag::Var>

=head2 C<type>: v

=head2 C<on_register>

        Make a tag for this variable unless we're told not to.  We
        assume that a variable is always static, unless it appears
        in a package before any sub.  (Not necessarily true, but
        it's ok for most purposes and Vim works fine even if it is
        incorrect)
            - pltags.pl comments

=cut

package Perl::Tags::Tag::Var;
our @ISA = qw/Perl::Tags::Tag/;

sub type { 'v' }

    # QUOTE:

sub on_register {
    my ($self, $tags) = @_;
    $self->{is_static} = ( $tags->{current}{package_name} || $tags->{current}{has_subs} ) ? 1 : 0;

    return 1;
}
=head1 C<Perl::Tags::Tag::Sub>

=head2 C<type>: s

=head2 C<on_register>

        Make a tag for this sub unless we're told not to.  We assume
        that a sub is static, unless it appears in a package.  (Not
        necessarily true, but it's ok for most purposes and Vim works
        fine even if it is incorrect)
            - pltags comments

=cut

package Perl::Tags::Tag::Sub;
our @ISA = qw/Perl::Tags::Tag/;

sub type { 's' }

sub on_register {
    my ($self, $tags) = @_;
    $tags->{current}{has_subs}++ ;
    $self->{is_static}++ unless $tags->{current}{package_name};

    return 1;
} 

=head1 C<Perl::Tags::Tag::Constant>

=head2 C<type>: c

=cut

package Perl::Tags::Tag::Constant;
our @ISA = qw/Perl::Tags::Tag/;

sub type { 'c' }

=head1 C<Perl::Tags::Tag::Label>

=head2 C<type>: l

=cut

package Perl::Tags::Tag::Label;
our @ISA = qw/Perl::Tags::Tag/;

sub type { 'l' }

=head1 C<Perl::Tags::Tag::Recurse>

=head2 C<type>: dummy

=head2 C<on_register>

Recurse adding this new module to the queue.

=cut

package Perl::Tags::Tag::Recurse;
our @ISA = qw/Perl::Tags::Tag/;

use Module::Locate qw/locate/;

sub type { 'dummy' }

sub on_register {
    my ($self, $tags) = @_;

    my $name = $self->{name};
    my $path;
    eval {
        $path = locate( $name ); # or warn "Couldn't find path for $module";
    };
    # return if $@;
    return unless $path;
    $tags->queue( { file=>$path, level=>$tags->{current}{level}+1 , refresh=>0} );
    return; # don't get added
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
