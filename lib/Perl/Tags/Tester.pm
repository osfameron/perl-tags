package Perl::Tags::Tester;
use parent 'Test::Builder::Module';
use Path::Tiny 'path';

our @EXPORT = qw(tag_ok);

sub tag_ok {
    my ($tagger, $symbol, $path, $bookmark, $description) = @_;

    my $canonpath = path($path)->absolute->canonpath;

    my $tag = join "\t",
        $symbol,
        $canonpath,
        "/$bookmark/";

    my $ok = $tagger =~ /
            ^
            \Q$tag\E
            $
            /mx;

    __PACKAGE__->builder->ok( $ok, $description );
}

1;
