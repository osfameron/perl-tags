#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper;

use Test::More tests => 11;
use FindBin qw($Bin);

use lib ($Bin);
use_ok( 'TodoTagger' ); # test class

my $todo_tagger = TodoTagger->new( max_level=>1 );
ok (defined $todo_tagger, 'created Perl::Tags' );
isa_ok ($todo_tagger, 'TodoTagger' );
isa_ok ($todo_tagger, 'Perl::Tags::Naive' );
isa_ok ($todo_tagger, 'Perl::Tags' );

my $result = 
    $todo_tagger->process(
        files => [ "$Bin/Test.pm" ],
        refresh=> 1
    );
ok ($result, 'processed successfully' ) or diag "RESULT $result";

like ($todo_tagger, qr{Test\t\S+/Test.pm\t/package Test;/}       , 'package line');
like ($todo_tagger, qr{bar\t\S+/Test.pm\t/my \(\$foo, \$bar\);/} , 'variable 1');
like ($todo_tagger, qr{foo\t\S+/Test.pm\t/my \(\$foo, \$bar\);/} , 'variable 2');
like ($todo_tagger, qr{wibble\t\S+/Test.pm\t/sub wibble \{/}     , 'subroutine');
like ($todo_tagger, qr{TODO\t\S+/Test.pm\t/# TODO: test this line/}, "subclass's TODO tag");
