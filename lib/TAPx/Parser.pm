package TAPx::Parser;

use warnings;
use strict;
use vars qw($VERSION);

use TAPx::Parser::Grammar;
use TAPx::Parser::Results;

=head1 NAME

TAPx::Parser - Parse TAP output

=head1 VERSION

Version 0.12

=cut

$VERSION = '0.12';

BEGIN {
    foreach my $method (
        qw<
        _end_tap
        _plan_found
        _start_tap
        _stream
        _stream_started
        _grammar
        good_plan
        plan
        tests_planned
        tests_run
        >
      )
    {
        no strict 'refs';
        *$method = sub {
            my $self = shift;
            return $self->{$method} unless @_;
            unless ( ( ref $self ) =~ /^TAPx::Parser/ ) {    # trusted methods
                $self->_croak("$method() may not be set externally");
            }
            $self->{$method} = shift;
        };
    }
}

=head1 SYNOPSIS

    use TAPx::Parser;

    my $parser = TAPx::Parser->new( { tap    => $string_o_tap } );
    # or
    my $parser = TAPx::Parser->new( { stream => $stream_o_tap } );
    
    while ( my $result = $parser->next ) {
        print $result->as_string;
    }

=head1 DESCRIPTION

C<TAPx::Parser> is designed to produce a proper parse of TAP output.  It is
ALPHA code and should be treated as such.  The interface is now solid, but it
is still subject to change.

For an example of how to run tests through this module, see the primitive
harness in C<examples/tprove>.  That harness will likely fail on a few obscure
systems such as VMS and Windows (fixing it for the latter should be easy.
Patches welcome).

See the code of C<examples/tprove> to understand how to extend this.

=head1 METHODS

=head2 Class methods

=head3 C<new>

 my $parser = TAPx::Parser->new(\%args);

Returns a new C<TAPx::Parser> object.

The arguments should be a hashref with I<one> of the following keys:

=over 4

=item * C<tap>

The value should be the complete TAP output.

=item * C<stream>

The value should be a code ref.  Every every time the reference is called, it
should return a chunk of TAP.  When no more tap is available, it should return
C<undef>.

=back

Optionally, a "callback" key may be added.  If present, each callback
corresponding to a given result type will be called with the result as the
argument if the C<run> method is used:

 my %callbacks = (
     test    => \&test_callback,
     plan    => \&plan_callback,
     comment => \&comment_callback,
     bailout => \&bailout_callback,
     unknown => \&unknown_callback,
 );
 
 my $aggregator = TAPx::Parser::Aggregator->new;
 foreach my $file ( @test_files ) {
     my $stream = TAPx::Parser::Source::Perl->new($file);
     my $parser = TAPx::Parser->new(
         {
             stream    => $stream,
             callbacks => \%callbacks,
         }
     );
     $parser->run;
     $aggregator->add( $file, $parser );
 }

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    $self->_initialize(@_);
}

##############################################################################

=head2 Instance methods

=head3 C<next>

  my $parser = TAPx::Parser->new( { stream => $stream } );
  while ( my $result = $parser->next ) {
      print $result->as_string, "\n";
  }

This method returns the results of the parsing, one result at a time.  Note
that it is destructive.  You can't rewind and examine previous results.

Each result returned is a subclass of C<TAPx::Parser::Results>.  See that
module and related classes for more information on how to use them.

=cut

sub next {
    my $self = shift;
    return shift @{ $self->{results} };
}

##############################################################################

=head3 C<run>

  $parser->run;

This method merely runs the parser and parses all of the TAP.  If callbacks
are used, it will attempt to call the appropriate callback with the TAP result
as the argument.

=cut

sub run {
    my $self = shift;
    while ( defined (my $result = $self->next) ) {
        if ( my $code = $self->_callback_for($result->type) ) {
            $code->($result);
        }
    }
}

{

    # of the following, anything beginning with an underscore is strictly
    # internal and should not be exposed.
    my %initialize = (
        _end_tap      => 0,
        _plan_found   => 0,     # how many plans were found
        _start_tap    => 0,
        plan          => '',    # the test plan (e.g., 1..3)
        tap           => '',    # the TAP
        tests_run     => 0,     # actual current test numbers
        results       => [],    # TAP parser results
        skipped       => [],    #
        todo          => [],    #
        passed        => [],    #
        failed        => [],    #
        actual_failed => [],    # how many tests really failed
        actual_passed => [],    # how many tests really passed
        todo_failed   => [],    # tests which unexpectedly succeed
        parse_errors  => [],    # perfect TAP should have none
    );

    sub _initialize {
        my ( $self, $arg_for ) = @_;

        $arg_for ||= {};
        my $stream = $arg_for->{stream};
        my $tap    = $arg_for->{tap};
        if ( $stream && $tap ) {
            $self->_croak("You may not have both a stream and a tap parser");
        }
        if ($stream) {
            require TAPx::Parser::Streamed;
            return TAPx::Parser::Streamed->new($arg_for);
        }
        $self->_grammar( TAPx::Parser::Grammar->new($self) )
          ;    # eventually pass a version
        while ( my ( $k, $v ) = each %initialize ) {
            $self->{$k} = 'ARRAY' eq ref $v ? [] : $v;
        }
        if ($tap) {
            $self->_tap($tap);
            $self->_parse;
        }
        $arg_for->{callbacks} ||= {};
        $self->{code_for} = $arg_for->{callbacks};
        $self->good_plan(1);    # will be reset at the end of parsing, if bad
        return $self;
    }
}

sub _callback_for {
    my ($self, $callback) = @_;
    return $self->{code_for}{$callback};
}

{
    my @tokens;
    my $first_token = 1;

    sub _tokens {
        my $self  = shift;
        my $token = shift @tokens;
        if ($first_token) {
            $self->_start_tap(1);
            $first_token = 0;
        }
        else {
            $self->_start_tap(0);
        }
        unless (@tokens) {
            $self->_end_tap(1);
        }
        return $token;
    }

    sub _lex {
        my $self = shift;
        $first_token = 1;
        @tokens      = ();
        my @remaining_tap = split /\n/, $self->_tap;

        my $grammar = $self->_grammar;
        LINE: while ( defined( my $line = shift @remaining_tap ) ) {
            foreach my $type ( $grammar->token_types ) {
                my $syntax = $grammar->syntax_for($type);
                if ( $line =~ $syntax ) {
                    my $handler = $grammar->handler_for($type);
                    push @tokens => $grammar->$handler($line);
                    next LINE;
                }
            }
            push @tokens => $grammar->_make_unknown_token($line);
        }
        return $self;
    }
}

sub _tap {
    my $self = shift;
    return $self->{tap} unless @_;
    $self->_initialize;    # reset state
    $self->{tap} = shift;
    return $self;
}

=head1 INDIVIDUAL RESULTS

If you've read this far in the docs, you've seen this:

    while ( my $result = $parser->next ) {
        print $result->as_string;
    }

Each result returned is a C<TAPx::Parser::Result> subclass, referred to as
I<result types>.

=head2 Result types

Basically, you fetch individual results from the TAP.  The five types, with
examples of each, are as follows:

=over 4

=item * Plan

 1..42

=item * Test

 ok 3 - We should start with some foobar!

=item * Comment

 # Hope we don't use up the foobar.

=item * Bailout

 Bail out!  We ran out of foobar!

=item * Unknown

 ... yo, this ain't TAP! ...

=back

Each result fetched is a result object of a different type.  There are common
methods to each result object and different types may have methods unique to
their type.  Sometimes a type method may be overridden in a subclass, but it's
use is guaranteed to be identical.

=head2 Common type methods

=head3 C<type>

Returns the type of result, such as C<comment> or C<test>.

=head3 C<as_string>

Prints a string representation of the token.  This might not be the exact
output, however.  Tests will have test numbers added if not present, TODO and
SKIP directives will be capitalized and, in general, things will be cleaned
up.  If you need the original text for the token, see the C<raw> method.

=head3  C<raw>

Returns the original line of text which was parsed.

=head3 C<is_plan>

Indicates whether or not this is the test plan line.

=head3 C<is_test>

Indicates whether or not this is a test line.

=head3 C<is_comment>

Indicates whether or not this is a comment.

=head3 C<is_bailout>

Indicates whether or not this is bailout line.

=head3 C<is_unknown>

Indicates whether or not the current line could be parsed.

=head2 C<plan> methods

 if ( $result->is_plan ) { ... }

If the above evaluates as true, the following methods will be available on the
C<$result> object.

=head3 C<plan> 

  if ( $result->is_plan ) {
     print $result->plan;
  }

This is merely a synonym for C<as_string>.

=head3 C<tests_planned>

  my $planned = $result->tests_planned;

Returns the number of tests planned.  For example, a plan of C<1..17> will
cause this method to return '17'.

=head2 C<commment> methods

 if ( $result->is_comment ) { ... }

If the above evaluates as true, the following methods will be available on the
C<$result> object.

=head3 C<comment> 

  if ( $result->is_comment ) {
      my $comment = $result->comment;
      print "I have something to say:  $comment";
  }

=head2 C<bailout> methods

 if ( $result->is_bailout ) { ... }

If the above evaluates as true, the following methods will be available on the
C<$result> object.

=head3 C<explanation>

  if ( $result->is_bailout ) {
      my $explanation = $result->explanation;
      print "We bailed out because ($explanation)";
  }

If, and only if, a token is a bailout token, you can get an "explanation" via
this method.  The explanation is the text after the mystical "Bail out!" words
which appear in the tap output.

=head2 C<unknown> methods

 if ( $result->is_unknown ) { ... }

There are no unique methods for unknown results.

=head2 C<test> methods

 if ( $result->is_test ) { ... }

If the above evaluates as true, the following methods will be available on the
C<$result> object.

=head3 C<ok>

  my $ok = $result->ok;

Returns the literal text of the C<ok> or C<not ok> status.

=head3 C<number>

  my $test_number = $result->number;

Returns the number of the test, even if the original TAP output did not supply
that number.

=head3 C<description>

  my $description = $result->description;

Returns the description of the test, if any.  This is the portion after the
test number but before the directive.

=head3 C<directive>

  my $directive = $result->directive;

Returns either C<TODO> or C<SKIP> if either directive was present for a test
line.

=head3 C<explanation>

  my $explanation = $result->explanation;

If a test had either a C<TODO> or C<SKIP> directive, this method will return
the accompanying explantion, if present.

  not ok 17 - 'Pigs can fly' # TODO not enough acid

For the above line, the explanation is I<not enough acid>.

=head3 C<passed>

  if ( $result->passed ) { ... }

Returns a boolean value indicating whether or not the test passed.  Remember
that for TODO tests, the sense of passing and failing is reversed.

=head3 C<actual_passed>

  if ( $result->actual_passed ) { ... }

Returns a boolean value indicating whether or not the test passed, regardless
of its TODO status.

=head3 C<has_skip>

  if ( $result->has_skip ) { ... }

Returns a boolean value indicating whether or not this test had a SKIP
directive.

=head3 C<has_todo>

  if ( $result->has_todo ) { ... }

Returns a boolean value indicating whether or not this test had a TODO
directive.

=head1 TOTAL RESULTS

After parsing the TAP, there are many methods available to let you dig through
the results and determine what is meaningful to you.

=head3 C<plan>

 my $plan = $parser->plan;

Returns the test plan, if found.

=head3 C<passed>

 my @passed = $parser->passed; # the test numbers which passed
 my $passed = $parser->passed; # the number of tests which passed

This method lets you know which (or how many) tests passed.  If a test failed
but had a TODO directive, it will be counted as a passed test.

=cut

sub passed { @{ shift->{passed} } }

=head3 C<failed>

 my @failed = $parser->failed; # the test numbers which failed
 my $failed = $parser->failed; # the number of tests which failed

This method lets you know which (or how many) tests failed.  If a test passed
but had a TODO directive, it will be counted as a failed test.

=cut

sub failed { @{ shift->{failed} } }

=head3 C<actual_passed>

 # the test numbers which actually passed
 my @actual_passed = $parser->actual_passed;

 # the number of tests which actually passed
 my $actual_passed = $parser->actual_passed;

This method lets you know which (or how many) tests actually passed,
regardless of whether or not a TODO directive was found.

=cut

sub actual_passed { @{ shift->{actual_passed} } }

=head3 C<actual_failed>

 # the test numbers which actually failed
 my @actual_failed = $parser->actual_failed;
 # the number of tests which actually failed
 my $actual_failed = $parser->actual_failed;

This method lets you know which (or how many) tests actually failed,
regardless of whether or not a TODO directive was found.

=cut

sub actual_failed { @{ shift->{actual_failed} } }

##############################################################################

=head3 C<todo>

 my @todo = $parser->todo; # the test numbers with todo directives
 my $todo = $parser->todo; # the number of tests with todo directives

This method lets you know which (or how many) tests had TODO directives.

=cut

sub todo { @{ shift->{todo} } }

=head3 C<todo_failed>

 # the test numbers which unexpectedly succeeded
 my @todo_failed = $parser->todo_failed;
 # the number of tests which unexpectedly succeeded 
 my $todo_failed = $parser->todo_failed;

This method lets you know which (or how many) tests actually passed but were
declared as "TODO" tests.

=cut

sub todo_failed { @{ shift->{todo_failed} } }

=head3 C<skipped>

 my @skipped = $parser->skipped; # the test numbers with SKIP directives
 my $skipped = $parser->skipped; # the number of tests with SKIP directives

This method lets you know which (or how many) tests had SKIP directives.

=cut

sub skipped { @{ shift->{skipped} } }

##############################################################################

=head3 C<good_plan>

  if ( $parser->good_plan ) { ... }

Returns a boolean value indicating whether or not the number of tests planned
matches the number of tests run.

And since we're on that subject ...

=head3 C<tests_planned>

  print $parser->tests_planned;

Returns the number of tests planned, according to the plan.  For example, a
plan of '1..17' will mean that 17 tests were planned.

=head3 C<tests_run>

  print $parser->tests_run;

Returns the number of tests which actually were run.  Hopefully this will
match the number of C<< $parser->tests_planned >>.

=cut

=head3 C<parse_errors>

 my @errors = $parser->parse_errors; # the parser errors
 my $errors = $parser->parse_errors; # the number of parser_errors

Fortunately, all TAP output is perfect.  In the event that it is not, this
method will return parser errors.  Note that a junk line which the parser does
not recognize is C<not> an error.  This allows this parser to handle future
versions of TAP.  The following are all TAP errors reported by the parser:

=over 4

=item * Misplaced plan

The plan (for example, '1..5'), must only come at the beginning or end of the
TAP output.

=item * No plan

Gotta have a plan!

=item * More than one plan

 1..3
 ok 1 - input file opened
 not ok 2 - first line of the input valid # todo some data
 ok 3 read the rest of the file
 1..3

Right.  Very funny.  Don't do that.

=item * Test numbers out of sequence

 1..3
 ok 1 - input file opened
 not ok 2 - first line of the input valid # todo some data
 ok 2 read the rest of the file

That last test line above should have the number '3' instead of '2'.

Note that it's perfectly acceptable for some lines to have test numbers and
others to not have them.  However, when a test number is found, it must be in
sequence.  The following is also an error:
 
 1..3
 ok 1 - input file opened
 not ok - first line of the input valid # todo some data
 ok 2 read the rest of the file

But this is not:

 1..3
 ok  - input file opened
 not ok - first line of the input valid # todo some data
 ok 3 read the rest of the file

=back

=cut

sub parse_errors { @{ shift->{parse_errors} } }

sub _add_error {
    my ( $self, $error ) = @_;
    push @{ $self->{parse_errors} } => $error;
    return $self;
}

sub _aggregate_results {
    my ( $self, $test ) = @_;

    my ( $actual, $status );
    if ( $test->actual_passed ) {
        $actual = 'actual_passed';
        $status = 'TODO' eq $test->directive ? 'failed' : 'passed';
    }
    else {
        $actual = 'actual_failed';
        $status = 'TODO' eq $test->directive ? 'passed' : 'failed';
    }
    my $num = $test->number;
    push @{ $self->{todo} }        => $num if $test->has_todo;
    push @{ $self->{skipped} }     => $num if $test->has_skip;
    push @{ $self->{todo_failed} } => $num if $test->todo_failed;
    push @{ $self->{$actual} }     => $num;
    push @{ $self->{$status} }     => $num;
    return $self;
}

{
    my %validation_for = (
        test => sub {
            my ( $self, $test ) = @_;
            local *__ANON__ = '__ANON__test_validation';
            $self->tests_run( $self->tests_run + 1 );

            if ( $test->number ) {
                if ( $test->number != $self->tests_run ) {
                    my $number = $test->number;
                    my $count  = $self->tests_run;
                    $self->_add_error(
                        "Tests out of sequence.  Found ($number) but expected ($count)"
                    );
                }
            }
            else {
                $test->_number( $self->tests_run );
            }
            $self->_aggregate_results($test);
        },
        plan => sub {
            my ( $self, $plan ) = @_;
            local *__ANON__ = '__ANON__plan_validation';
            $self->tests_planned( $plan->tests_planned );
            $self->plan( $plan->as_string );
            $self->_plan_found( $self->_plan_found + 1 );
            unless ( $self->_start_tap || $self->_end_tap ) {
                my $line = $plan->as_string;
                $self->_add_error(
                    "Plan ($line) must be at the beginning or end of the TAP output"
                );
            }
        },
        bailout => sub { },
        unknown => sub { },
        comment => sub { },
    );

    sub _validate {
        my ( $self, $token ) = @_;
        my $type     = $token->type;
        my $validate = $validation_for{$type};
        unless ($validate) {

            # should never happen
            # We could simply leave off keys for which no validation is
            # required, but that means that new token types in the future are
            # easily skipped here.
            $self->_croak("Don't know how how to validate '$type'");
        }
        $self->$validate($token);
    }
}

sub _parse {
    my ( $self, $tap ) = @_;
    $tap ||= $self->_tap;
    $self->_tap($tap);
    $self->{results} = [];
    $self->_lex;
    while ( my $token = $self->_tokens ) {
        my $result = TAPx::Parser::Results->new($token);
        $self->_validate($result);
        push @{ $self->{results} } => $result;
    }
    $self->_finish;
    return $self;
}

sub _finish {
    my $self = shift;

    # sanity checks
    if ( !$self->_plan_found ) {
        $self->_add_error("No plan found in TAP output");
    }
    elsif ( $self->_plan_found > 1 ) {
        $self->_add_error("More than one plan found in TAP output");
    }
    if ( $self->tests_run != $self->tests_planned ) {
        $self->good_plan(0);
    }
    if ( $self->tests_run != ( $self->passed + $self->failed ) ) {

        # this should never happen
        my $actual = $self->tests_run;
        my $passed = $self->passed;
        my $failed = $self->failed;
        $self->_croak(
            "Panic: planned test count ($actual) did not equal sum of passed ($passed) and failed ($failed) tests!"
        );
    }
    return $self;
}

sub _croak {
    my ( $self, $message ) = @_;
    require Carp;
    Carp::croak($message);
}

##############################################################################

=head1 TAP GRAMMAR

The C<TAPx::Parser> does not use a formal grammar because TAP is essentiall a
stream-based protocol.  In fact, it's quite legal to have an infinite stream.
For the same reason that we don't apply regexes to streams, we're not using a
formal grammar here.  Instead, we parse the TAP in lines (referred to
internally as "chunks").

A formal grammar would look similar to the following:

 (* 
     For the time being, I'm cheating on the EBNF by allowing 
     certain terms to be defined by POSIX character classes by
     using the following syntax:
 
       digit ::= [:digit:]
 
     As far as I am away, that's not valid EBNF.  Sue me.  I
     didn't know how to write "char" otherwise (Unicode issues).  
     Suggestions welcome.
 *)
 
 (* POSIX character classes and other terminals *)
 
 digit           ::= [:digit:]
 character       ::= [:print:]
 positiveInteger ::= (digit - '0') {digit}
 
 (* And on to the real grammar ... *)
 
 (* "plan => $num" versus "no_plan" *)
 
 tap    ::= plan tests | tests plan 
 
 plan   ::= '1..' positiveInteger "\n"
 
 (* Gotta have at least one test *)
 
 tests  ::= test {test}
 
 (* 
     The "positiveNumber" is the test number and should 
     always be one greater than the previous test number.
 *)
    
 test   ::= status (positiveNumber description)? directive? "\n"
 
 status ::= 'not '? 'ok '
 
 (*
     Description must not begin with a digit or contain a 
     hash mark.
 *)
 
 description ::= (character - (digit '#')) {character - '#'}
 
 directive   ::= '#' ( 'TODO' | 'SKIP' ) ' ' {character}

=head1 ACKNOWLEDGEMENTS

Far too many for me to remember all of them, but let me just say 'thanks' to
the members of the perl-qa list for answering most of my silly questions about
strange areas of TAP.

=head1 AUTHOR

Curtis "Ovid" Poe, C<< <ovid@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-tapx-parser@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=TAPx-Parser>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Curtis "Ovid" Poe, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
