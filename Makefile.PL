use strict;
use warnings;
use inc::Module::Install;

name        'Perl-Tags';
all_from    'lib/Perl/Tags.pm';

license     'perl';
author      'osfameron';

requires        'File::Spec';
requires        'File::Temp';
requires        'File::Find';
requires        'Module::Locate';
requires        'PPI';
build_requires  'Test::More' => 0.42;
build_requires  'Data::Dumper';

install_script  'bin/perl-tags';


auto_install;
WriteAll;
