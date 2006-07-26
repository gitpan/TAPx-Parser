use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name       => 'TAPx::Parser',
    license           => 'perl',
    dist_author       => 'Curtis "Ovid" Poe <ovid@cpan.org>',
    dist_version_from => 'lib/TAPx/Parser.pm',
    requires          => {
        'Test::More'          => 0,
    },
    add_to_cleanup     => ['TAPx-Parser-*'],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
