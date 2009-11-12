#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper;

use Test::More tests => 9;
use FindBin qw($Bin);

SKIP: {
    eval { require 'PPI' };
    skip "PPI not installed", 9 if $@;

    use_ok("Perl::Tags::PPI") or skip "Couldn't use Perl::Tags::PPI $@", 8;

    my $ppi_tagger = Perl::Tags::PPI->new( max_level=>1 );
    ok (defined $ppi_tagger, 'created Perl::Tags' );
    isa_ok ($ppi_tagger, 'Perl::Tags::PPI' );
    isa_ok ($ppi_tagger, 'Perl::Tags' );

    my $result = 
        $ppi_tagger->process(
            files => [ "$Bin/Test.pm" ],
            refresh=> 1
        );
    ok ($result, 'processed successfully' ) or diag "RESULT $result";

    like ($ppi_tagger, qr{Test\t\S+[\\/]Test.pm\t/package Test;/}       , 'package line');
    like ($ppi_tagger, qr{\$?bar\t\S+[\\/]Test.pm\t/my \(\\?\$foo, \\?\$bar\);/} , 'variable 1');
    like ($ppi_tagger, qr{\$?foo\t\S+[\\/]Test.pm\t/my \(\\?\$foo, \\?\$bar\);/} , 'variable 2');
    like ($ppi_tagger, qr{wibble\t\S+[\\/]Test.pm\t/sub wibble \{/}     , 'subroutine');

}
