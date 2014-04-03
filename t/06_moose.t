#!/usr/bin/perl
use strict; use warnings;
use Data::Dumper;

use Test::More;
use FindBin qw($Bin);
use lib "$FindBin::Bin";

use Perl::Tags;
use Perl::Tags::Naive::Moose;

my $naive_tagger = Perl::Tags::Naive::Moose->new( max_level=>2 );
ok (defined $naive_tagger, 'created Perl::Tags' );
isa_ok ($naive_tagger, 'Perl::Tags::Naive::Moose' );
isa_ok ($naive_tagger, 'Perl::Tags' );

my $result = 
    $naive_tagger->process(
        files => [ "$Bin/Moosy/Class.pm" ],
        refresh=> 1
    );
ok ($result, 'processed successfully' ) or diag "RESULT $result";

diag "TODO: proper test";
diag $naive_tagger;

# Moosy::Class  /home/fms/perl-tags/t/Moosy/Class.pm    /package Moosy::Class;/
# Moosy::Parent /home/fms/perl-tags/t/Moosy/Parent.pm   /package Moosy::Parent;/
# Moosy::Role1  /home/fms/perl-tags/t/Moosy/Role1.pm    /package Moosy::Role1;/
# Moosy::Role2  /home/fms/perl-tags/t/Moosy/Role2.pm    /package Moosy::Role2;/
# Moosy::Role3  /home/fms/perl-tags/t/Moosy/Role3.pm    /package Moosy::Role3;/
# bar   /home/fms/perl-tags/t/Moosy/Parent.pm   /has bar => (/
# foo   /home/fms/perl-tags/t/Moosy/Class.pm    /has foo => (/

done_testing;
