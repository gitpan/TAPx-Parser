#!/usr/bin/perl 
use warnings;
use strict;

use lib 'lib';
use TAPx::Parser;
use TAPx::Parser::Iterator;

#use Test::More 'no_plan';

use Test::More tests => 3;

my $tap = <<'END_TAP';
1..5
ok 1 - input file opened
... this is junk
not ok first line of the input valid # todo some data
# this is a comment
ok 3 - read the rest of the file
not ok 4 - this is a real failure
ok 5 # skip we have no description
END_TAP

my @tests;
my $plan_output;
my $todo      = 0;
my $skip      = 0;
my %callbacks = (
    test => sub {
        my $test = shift;
        push @tests => $test;
        $todo++ if $test->has_todo;
        $skip++ if $test->has_skip;
    },
    plan => sub {
        my $plan = shift;
        $plan_output = $plan->as_string;
    }
);

my $stream = TAPx::Parser::Iterator->new( [ split /\n/ => $tap ] );
my $parser = TAPx::Parser->new(
    {   stream    => $stream,
        callbacks => \%callbacks,
    }
);

can_ok $parser, 'run';
$parser->run;
is $plan_output, '1..5',
   'Plan callbacks should succeed';
is scalar @tests, $parser->tests_run,
    '... as should the test callbacks';
