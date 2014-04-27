use strict;
use warnings;
use inc::Module::Install;

name        'Perl-Tags';
all_from    'lib/Perl/Tags.pm';

license     'perl';
author      'osfameron';

requires        'File::Spec';
requires        'File::Temp';
requires        'File::Find::Rule';
requires        'Module::Locate';
requires        'PPI';
requires        'Path::Tiny';
test_requires  'Test::More' => 0.42;
test_requires  'Test::Strict';
test_requires  'Test::Exception';
test_requires  'Test::LongString';
test_requires  'Test::Builder' => 0.42;
build_requires  'Data::Dumper';
build_requires  'Capture::Tiny';
# feature 'develop' => 'App::FatPacked' # TODO

install_script  'bin/perl-tags';
install_script  'bin/require-perl-tags';
install_script  'bin/require-perl-tags-packed';

auto_install;
WriteAll;
