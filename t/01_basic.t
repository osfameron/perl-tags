#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper;

use Test::More;
use FindBin qw($Bin);

use Perl::Tags;
use Perl::Tags::Naive;

my $naive_tagger = Perl::Tags::Naive->new( max_level=>1 );
ok (defined $naive_tagger, 'created Perl::Tags' );
isa_ok ($naive_tagger, 'Perl::Tags::Naive' );
isa_ok ($naive_tagger, 'Perl::Tags' );

my $result = 
    $naive_tagger->process(
        files => [ "$Bin/Test.pm" ],
        refresh=> 1
    );
ok ($result, 'processed successfully' ) or diag "RESULT $result";

like ($naive_tagger, qr{Test\t\S+[\\/]Test.pm\t/package Test;/}       , 'package line');
like ($naive_tagger, qr{bar\t\S+[\\/]Test.pm\t/my \(\$foo, \$bar\);/} , 'variable 1');
like ($naive_tagger, qr{foo\t\S+[\\/]Test.pm\t/my \(\$foo, \$bar\);/} , 'variable 2');
like ($naive_tagger, qr{wibble\t\S+[\\/]Test.pm\t/sub wibble \{/}     , 'subroutine');

done_testing;
