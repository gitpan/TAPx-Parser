#!/usr/bin/perl -T

use Test::More tests => 24;

BEGIN {
    my @classes = qw(
      TAPx::Parser
      TAPx::Parser::Aggregator
      TAPx::Parser::Grammar
      TAPx::Parser::Iterator
      TAPx::Parser::Streamed
      TAPx::Parser::Results
      TAPx::Parser::Results::Comment
      TAPx::Parser::Results::Plan
      TAPx::Parser::Results::Test
      TAPx::Parser::Results::Unknown
      TAPx::Parser::Results::Bailout
      TAPx::Parser::Source::Perl
    );

    foreach my $class (@classes) {
        use_ok $class;
        is $class->VERSION, TAPx::Parser->VERSION,
            "... and it should have the correct version";
    }
    diag("Testing TAPx::Parser $TAPx::Parser::VERSION, Perl $], $^X");
}
