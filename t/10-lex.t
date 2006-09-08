#!/usr/bin/perl -T
use warnings;
use strict;

use lib 'lib';

#use Test::More 'no_plan';

use Test::More tests => 11;
use TAPx::Parser;

my $plan_line = 'TAPx::Parser::Results::Plan';
my $test_line = 'TAPx::Parser::Results::Test';

sub _get_tokens {
    my $parser = shift;
    my @tokens;
    while ( my $token = $parser->_tokens ) {
        push @tokens => $token;
    }
    return \@tokens;
}

my $parser = TAPx::Parser->new;

# test valid TAP

$parser->_tap(<<'END_TAP');
1..3
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
# this is a comment
ok 3 - read the rest of the file
END_TAP

can_ok $parser, '_lex';
ok my $tokens = _get_tokens( $parser->_lex ),
  '... we should be able to lex proper tap';
my $expected = [
    {   raw           => '1..3',
        tests_planned => 3,
        type          => 'plan',
    },
    {   ok          => 'ok',
        test_num    => '1',
        description => '- input file opened',
        directive   => '',
        explanation => '',
        raw         => 'ok 1 - input file opened',
        type        => 'test',
    },
    {   ok          => 'not ok',
        test_num    => '2',
        description => '- first line of the input valid',
        directive   => 'TODO',
        explanation => 'some data',
        raw  => 'not ok 2 - first line of the input valid # todo some data',
        type => 'test',
    },
    {   raw     => '# this is a comment',
        comment => 'this is a comment',
        type    => 'comment',
    },
    {   ok          => 'ok',
        test_num    => '3',
        description => '- read the rest of the file',
        directive   => '',
        explanation => '',
        raw         => 'ok 3 - read the rest of the file',
        type        => 'test',
    },
];
is_deeply $tokens, $expected, '... the returned tokens should be correct';

$parser->_tap(<<'END_TAP');
1..1
not ok 1 - first line of the \# todo input valid # todo some data
END_TAP

ok $tokens = _get_tokens( $parser->_lex ),
  '... we should be able to lex proper tap';
$expected = [
    {   raw           => '1..1',
        tests_planned => 1,
        type          => 'plan',
    },
    {   ok          => 'not ok',
        test_num    => '1',
        description => '- first line of the \\# todo input valid',
        directive   => 'TODO',
        explanation => 'some data',
        raw         =>
          'not ok 1 - first line of the \# todo input valid # todo some data',
        type => 'test',
    },
];
is_deeply $tokens, $expected, '... even if it has an escaped directive';

# note that these "apparent" escapes are literal characters in a HEREDOC.
$parser->_tap(<<'END_TAP');
1..1
not ok 1 - first line of the \\\# todo input valid # todo some data
END_TAP

ok $tokens = _get_tokens( $parser->_lex ),
  '... we should be able to lex proper tap';
$expected = [
    {   raw           => '1..1',
        tests_planned => 1,
        type          => 'plan',
    },
    {   ok          => 'not ok',
        test_num    => '1',
        description => '- first line of the \\\\\# todo input valid',
        directive   => 'TODO',
        explanation => 'some data',
        raw         =>
          'not ok 1 - first line of the \\\\\# todo input valid # todo some data',
        type => 'test',
    },
];
is_deeply $tokens, $expected, '... or a balanced number of escapes';

$parser->_tap(<<'END_TAP');
TAP VERSION 7
1..3
ok 1 - Input file opened
not ok 2 - First line of the input valid # TODO some data
... lots of junk
# this is another comment
ok 3 - Read the rest of the file
END_TAP

ok $tokens = _get_tokens( $parser->_lex ),
  '... even if it has unrecognized lines';
$expected = [
    {   raw  => 'TAP VERSION 7',
        type => 'unknown',
    },
    {   raw           => '1..3',
        tests_planned => 3,
        type          => 'plan',
    },
    {   ok          => 'ok',
        test_num    => '1',
        description => '- Input file opened',
        directive   => '',
        explanation => '',
        raw         => 'ok 1 - Input file opened',
        type        => 'test',
    },
    {   ok          => 'not ok',
        test_num    => '2',
        description => '- First line of the input valid',
        directive   => 'TODO',
        explanation => 'some data',
        raw  => 'not ok 2 - First line of the input valid # TODO some data',
        type => 'test',
    },
    {   raw  => '... lots of junk',
        type => 'unknown',

    },
    {   raw     => '# this is another comment',
        comment => 'this is another comment',
        type    => 'comment',
    },
    {   ok          => 'ok',
        test_num    => '3',
        description => '- Read the rest of the file',
        directive   => '',
        explanation => '',
        raw         => 'ok 3 - Read the rest of the file',
        type        => 'test',
    },
];
is_deeply $tokens, $expected, '... even if the plan is at the end';

$parser->_tap(<<'END_TAP');
TAP VERSION 7
1..3
ok 1 - Input file opened
not ok 2 - First line of the input valid # todo some data
... lots of junk
#   this is yet another comment
ok 3 - Read the rest of the file # SKIP IT!
END_TAP

ok $tokens = _get_tokens( $parser->_lex ),
  '... even if it has unrecognized lines';
$expected = [
    {   raw  => 'TAP VERSION 7',
        type => 'unknown',
    },
    {   raw           => '1..3',
        tests_planned => 3,
        type          => 'plan',
    },
    {   ok          => 'ok',
        test_num    => '1',
        description => '- Input file opened',
        directive   => '',
        explanation => '',
        raw         => 'ok 1 - Input file opened',
        type        => 'test',
    },
    {   ok          => 'not ok',
        test_num    => '2',
        description => '- First line of the input valid',
        directive   => 'TODO',
        explanation => 'some data',
        raw  => 'not ok 2 - First line of the input valid # todo some data',
        type => 'test',
    },
    {   raw  => '... lots of junk',
        type => 'unknown',
    },
    {   raw     => '#   this is yet another comment',
        comment => 'this is yet another comment',
        type    => 'comment',
    },
    {   ok          => 'ok',
        test_num    => '3',
        description => '- Read the rest of the file',
        directive   => 'SKIP',
        explanation => 'IT!',
        raw         => 'ok 3 - Read the rest of the file # SKIP IT!',
        type        => 'test',
    },
];
is_deeply $tokens, $expected, '... or the directives are in a different case';
