#!/usr/bin/perl -T
use warnings;
use strict;

use lib 'lib';

#use Test::More 'no_plan';

use Test::More tests => 121;

BEGIN {
    use_ok 'TAPx::Parser' or die;
}

sub _get_results {
    my $parser = shift;
    my @results;
    while ( my $result = $parser->results ) {
        push @results => $result;
    }
    return @results;
}

my ( $PARSER, $PLAN, $TEST, $COMMENT, $BAILOUT, $UNKNOWN );

BEGIN {
    $PARSER  = 'TAPx::Parser';
    $PLAN    = 'TAPx::Parser::Results::Plan';
    $TEST    = 'TAPx::Parser::Results::Test';
    $COMMENT = 'TAPx::Parser::Results::Comment';
    $BAILOUT = 'TAPx::Parser::Results::Bailout';
    $UNKNOWN = 'TAPx::Parser::Results::Unknown';
    foreach my $class ( $PARSER, $PLAN, $TEST, $COMMENT, $BAILOUT, $UNKNOWN )
    {
        use_ok $class or die;
    }
}

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

can_ok $PARSER, 'new';
ok my $parser = $PARSER->new( { tap => $tap } ),
  '... and calling it should succeed';
isa_ok $parser, $PARSER, '... and the object it returns';

# results() is sane?

ok my @results = _get_results($parser), 'The parser should return results';
is scalar @results, 8, '... and there should be one for each line';

# check the test plan

my $result = shift @results;
isa_ok $result, $PLAN;
can_ok $result, 'type';
is $result->type, 'plan', '... and it should report the correct type';
ok $result->is_plan,   '... and it should identify itself as a plan';
is $result->plan,      '1..5', '... and identify the plan';
is $result->as_string, '1..5',
  '... and have the correct string representation';
is $result->raw, '1..5', '... and raw() should return the original line';

# a normal, passing test

my $test = shift @results;
isa_ok $test, $TEST;
is $test->type, 'test', '... and it should report the correct type';
ok $test->is_test, '... and it should identify itself as a test';
is $test->ok,      'ok', '... and it should have the correct ok()';
ok $test->passed,  '... and the correct boolean version of passed()';
ok $test->actual_passed,
  '... and the correct boolean version of actual_passed()';
is $test->number, 1, '... and have the correct test number';
is $test->description, '- input file opened',
  '... and the correct description';
ok !$test->directive,   '... and not have a directive';
ok !$test->explanation, '... or a directive explanation';
ok !$test->has_skip,    '... and it is not a SKIPped test';
ok !$test->has_todo,    '... nor a TODO test';
is $test->as_string, 'ok 1 - input file opened',
  '... and its string representation should be correct';
is $test->raw, 'ok 1 - input file opened',
  '... and raw() should return the original line';

# junk lines should be preserved

my $unknown = shift @results;
isa_ok $unknown, $UNKNOWN;
is $unknown->type, 'unknown', '... and it should report the correct type';
ok $unknown->is_unknown, '... and it should identify itself as unknown';
is $unknown->as_string,  '... this is junk',
  '... and its string representation should be returned verbatim';
is $unknown->raw, '... this is junk',
  '... and raw() should return the original line';

# a failing test, which also happens to have a directive

my $failed = shift @results;
isa_ok $failed, $TEST;
is $failed->type, 'test', '... and it should report the correct type';
ok $failed->is_test, '... and it should identify itself as a test';
is $failed->ok,      'not ok', '... and it should have the correct ok()';
ok $failed->passed,  '... and TODO tests should reverse the sense of passing';
ok !$failed->actual_passed,
  '... and the correct boolean version of actual_passed ()';
is $failed->number, 2, '... and have the correct failed number';
is $failed->description, 'first line of the input valid',
  '... and the correct description';
is $failed->directive, 'TODO', '... and should have the correct directive';
is $failed->explanation, 'some data',
  '... and the correct directive explanation';
ok !$failed->has_skip, '... and it is not a SKIPped failed';
ok $failed->has_todo, '... but it is a TODO succeeded';
is $failed->as_string,
  'not ok 2 first line of the input valid # TODO some data',
  '... and its string representation should be correct';
is $failed->raw, 'not ok first line of the input valid # todo some data',
  '... and raw() should return the original line';

# comments

my $comment = shift @results;
isa_ok $comment, $COMMENT;
is $comment->type, 'comment', '... and it should report the correct type';
ok $comment->is_comment, '... and it should identify itself as a comment';
is $comment->comment,    'this is a comment',
  '... and you should be able to fetch the comment';
is $comment->as_string, '# this is a comment',
  '... and have the correct string representation';
is $comment->raw, '# this is a comment',
  '... and raw() should return the original line';

# another normal, passing test

$test = shift @results;
isa_ok $test, $TEST;
is $test->type, 'test', '... and it should report the correct type';
ok $test->is_test, '... and it should identify itself as a test';
is $test->ok,      'ok', '... and it should have the correct ok()';
ok $test->passed,  '... and the correct boolean version of passed()';
ok $test->actual_passed,
  '... and the correct boolean version of actual_passed()';
is $test->number, 3, '... and have the correct test number';
is $test->description, '- read the rest of the file',
  '... and the correct description';
ok !$test->directive,   '... and not have a directive';
ok !$test->explanation, '... or a directive explanation';
ok !$test->has_skip,    '... and it is not a SKIPped test';
ok !$test->has_todo,    '... nor a TODO test';
is $test->as_string, 'ok 3 - read the rest of the file',
  '... and its string representation should be correct';
is $test->raw, 'ok 3 - read the rest of the file',
  '... and raw() should return the original line';

# a failing test

$failed = shift @results;
isa_ok $failed, $TEST;
is $failed->type, 'test', '... and it should report the correct type';
ok $failed->is_test, '... and it should identify itself as a test';
is $failed->ok, 'not ok', '... and it should have the correct ok()';
ok !$failed->passed, '... and the tests should not have passed';
ok !$failed->actual_passed,
  '... and the correct boolean version of actual_passed ()';
is $failed->number, 4, '... and have the correct failed number';
is $failed->description, '- this is a real failure',
  '... and the correct description';
ok !$failed->directive,   '... and should have no directive';
ok !$failed->explanation, '... and no directive explanation';
ok !$failed->has_skip,    '... and it is not a SKIPped failed';
ok !$failed->has_todo,    '... and not a TODO test';
is $failed->as_string, 'not ok 4 - this is a real failure',
  '... and its string representation should be correct';
is $failed->raw, 'not ok 4 - this is a real failure',
  '... and raw() should return the original line';

# ok 5 # skip we have no description
# skipped test

$test = shift @results;
isa_ok $test, $TEST;
is $test->type, 'test', '... and it should report the correct type';
ok $test->is_test, '... and it should identify itself as a test';
is $test->ok,      'ok', '... and it should have the correct ok()';
ok $test->passed,  '... and the correct boolean version of passed()';
ok $test->actual_passed,
  '... and the correct boolean version of actual_passed()';
is $test->number, 5, '... and have the correct test number';
ok !$test->description, '... and skipped tests have no description';
is $test->directive, 'SKIP', '... and teh correct directive';
is $test->explanation, 'we have no description',
  '... but we should have an explanation';
ok $test->has_skip, '... and it is a SKIPped test';
ok !$test->has_todo, '... but not a TODO test';
is $test->as_string, 'ok 5 # SKIP we have no description',
  '... and its string representation should be correct';
is $test->raw, 'ok 5 # skip we have no description',
  '... and raw() should return the original line';

# test parse results

can_ok $parser, 'passed';
is $parser->passed, 4,
  '... and we should have the correct number of passed tests';
is_deeply [ $parser->passed ], [ 1, 2, 3, 5 ],
  '... and get a list of the passed tests';

can_ok $parser, 'failed';
is $parser->failed, 1, '... and the correct number of failed tests';
is_deeply [ $parser->failed ], [4], '... and get a list of the failed tests';

can_ok $parser, 'actual_passed';
is $parser->actual_passed, 3,
  '... and we shold have the correct number of actually passed tests';
is_deeply [ $parser->actual_passed ], [ 1, 3, 5 ],
  '... and get a list of the actually passed tests';

can_ok $parser, 'actual_failed';
is $parser->actual_failed, 2,
  '... and the correct number of actually failed tests';
is_deeply [ $parser->actual_failed ], [ 2, 4 ],
  '... or get a list of the actually failed tests';

can_ok $parser, 'todo';
is $parser->todo, 1,
  '... and we should have the correct number of TODO tests';
is_deeply [ $parser->todo ], [2], '... and get a list of the TODO tests';

can_ok $parser, 'skipped';
is $parser->skipped, 1,
  '... and we should have the correct number of skipped tests';
is_deeply [ $parser->skipped ], [5],
  '... and get a list of the skipped tests';

# check the plan

can_ok $parser, 'plan';
is $parser->plan,          '1..5', '... and we should have the correct plan';
is $parser->tests_planned, 5,      '... and the correct number of tests';

