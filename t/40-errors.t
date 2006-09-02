#!/usr/bin/perl -T
use warnings;
use strict;

use lib 'lib';
#use Test::More 'no_plan';

use Test::More tests => 18;
use TAPx::Parser;

my $plan_line = 'TAPx::Parser::Results::Plan';
my $test_line = 'TAPx::Parser::Results::Test';

my $parser = TAPx::Parser->new;

# validate that plan!

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 3 - read the rest of the file
1..3
# yeah, yeah, I know.
END_TAP

can_ok $parser, 'parse_errors';
is scalar $parser->parse_errors, 1, '... and we should have one parse error';
is [ $parser->parse_errors ]->[0],
  'Plan (1..3) must be at the beginning or end of the TAP output',
  '... telling us that our plan was misplaced';

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 3 - read the rest of the file
#1..3
# yo quiero tests!
1..3
END_TAP
ok !$parser->parse_errors, '... but test plan-like data can be in a comment';

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 3 - read the rest of the file 1..5
# yo quiero tests!
1..3
END_TAP
ok !$parser->parse_errors, '... or a description';

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
not ok 2 - first line of the input valid # todo 1..4
ok 3 - read the rest of the file
# yo quiero tests!
1..3
END_TAP
ok !$parser->parse_errors, '... or a directive';

# test numbers included?

$parser->_tap(<<'END_TAP');
1..3
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok read the rest of the file
# this is ...
END_TAP
my $expected;
eval { $expected = $parser->_lex };
ok !$@, 'We can mix and match the presence of test numbers';

$parser->_parse(<<'END_TAP');
1..3
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 2 read the rest of the file
END_TAP

is + ( $parser->parse_errors )[0],
  'Tests out of sequence.  Found (2) but expected (3)',
  '... and if the numbers are there, they cannot be out of sequence';

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 2 read the rest of the file
END_TAP

is $parser->parse_errors, 2,
  'Having two errors in the TAP should result in two errors (duh)';
$expected = [
    'Tests out of sequence.  Found (2) but expected (3)',
    'No plan found in TAP output'
];
is_deeply [ $parser->parse_errors ], $expected,
  '... and they should be the correct errors';

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 3 read the rest of the file
END_TAP

is $parser->parse_errors, 1, 'Having no plan should cause an error';
is + ( $parser->parse_errors )[0], 'No plan found in TAP output',
  '... with a correct error message';

$parser->_parse(<<'END_TAP');
1..3
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 3 read the rest of the file
1..3
END_TAP

is $parser->parse_errors, 1,
  'Having more than one plan should cause an error';
is + ( $parser->parse_errors )[0], 'More than one plan found in TAP output',
  '... with a correct error message';

can_ok $parser, 'good_plan';
$parser->_parse(<<'END_TAP');
1..2
ok 1 - input file opened
not ok 2 - first line of the input valid # todo some data
ok 3 read the rest of the file
END_TAP

ok !$parser->parse_errors,
  'Having a planned and actual tests differ is not a parse error';
ok ! $parser->good_plan, '... but good_plan() should return false';

$parser->_parse(<<'END_TAP');
ok 1 - input file opened
1..1
END_TAP

ok $parser->good_plan, '... and it should return true if the plan is correct';
