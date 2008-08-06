use strict;
use warnings;
use inc::Module::Install;

name        'Perl-Tags';
all_from    'lib/Perl/Tags.pm';

license     'perl';
author      'osfameron';

requires        'File::Spec';
requires        'File::Temp';
requires        'Module::Locate';
build_requires  'Test::More' => 0.42;

recommends      'PPI';

auto_install;
WriteAll;
