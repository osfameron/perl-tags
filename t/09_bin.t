use strict; use warnings;
use Test::More;

use FindBin;

use Capture::Tiny 'capture';

subtest 'Command line ok' => sub {
    my ($stdout, $stderr, $exit) = capture {
        system "$FindBin::Bin/../bin/perl-tags";
    };
    ok ! $exit, 'command successful';
    like $stdout, qr/Usage: perl-tags <options>/, 'Usage displayed as expected';
    is $stderr, '', 'No stderr';

    ($stdout, $stderr, $exit) = capture {
        system "$FindBin::Bin/../bin/perl-tags -v";
    };
    ok ! $exit, 'command successful';
    is $stderr, '', 'No stderr';
    like $stdout, qr/perl-tags v. [0-9.]+ \(Perl Tags v. [0-9.]+\)/, 'Version command as expected';
};

subtest 'check get_files method' => sub {
    use lib "$FindBin::Bin/../lib";
    require App::Perl::Tags;

    my $app = App::Perl::Tags->new( paths => [ $FindBin::Bin ] );
    my @files = $app->get_files;
    is_deeply $app->{prune}, ['.git', '.svn'], 'Expected value for --prune';
    ok @files > 10, 'Sufficient number of files returned';
    ok ((scalar grep /Moosy/, @files), 'Contains expected files');
    ok ((scalar grep /\.t$/, @files), 'Contains expected files');

    $app = App::Perl::Tags->new( paths => [ $FindBin::Bin ], prune => [ 'Moosy' ] );
    my @pruned_files = $app->get_files;
    ok @pruned_files > 10, 'Sufficient number of files returned';
    ok ((! scalar grep /Moosy/, @pruned_files), 'Pruned Moosy files');

    is_deeply
        [ grep ! /Moosy/, sort @files ],
        [ sort @pruned_files ],
        'Expected files after pruning';
};

done_testing;
