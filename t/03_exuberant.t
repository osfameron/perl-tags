#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper;

use Test::More tests => 9;
use FindBin qw($Bin);

BEGIN {
  use_ok( 'Perl::Tags' );
}

# a naive, yet exuberant tagger
my $naive_tagger = Perl::Tags::Naive->new( 
    max_level=>1,
    exts     =>1,
);
ok (defined $naive_tagger, 'created an exuberant tagger' );
isa_ok ($naive_tagger, 'Perl::Tags::Naive' );
isa_ok ($naive_tagger, 'Perl::Tags' );

my $result = 
    $naive_tagger->process(
        files => [ "$Bin/Test.pm" ],
        refresh=> 1
    );
ok ($result, 'processed successfully' ) or diag "RESULT $result";

like ($naive_tagger, qr{Test\t\S+[\\/]Test.pm\t/package Test;/;"\tp\tline:3\tclass:Test}       , 'package line');
like ($naive_tagger, qr{bar\t\S+[\\/]Test.pm\t/my \(\$foo, \$bar\);/;"\tv\tline:8\tfile:\tclass:Test} , 'variable 1');
like ($naive_tagger, qr{foo\t\S+[\\/]Test.pm\t/my \(\$foo, \$bar\);/;"\tv\tline:8\tfile:\tclass:Test} , 'variable 2');
like ($naive_tagger, qr{wibble\t\S+[\\/]Test.pm\t/sub wibble \{/;"\ts\tline:10\tclass:Test}     , 'subroutine');

