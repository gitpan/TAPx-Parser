package TAPx::Parser;

use strict;
use vars qw($VERSION @ISA);

use TAPx::Base;
use TAPx::Parser::Grammar;
use TAPx::Parser::Result;
use TAPx::Parser::Source;
use TAPx::Parser::Source::Perl;
use TAPx::Parser::Iterator;

@ISA = qw(TAPx::Base);

=head1 NAME

TAPx::Parser - Parse L<TAP|Test::Harness::TAP> output

=head1 VERSION

Version 0.50_07

=cut

$VERSION = '0.50_07';

BEGIN {
    foreach my $method (
        qw<
        _can_ignore_output
        _end_tap
        _plan_found
        _start_tap
        _stream
        _spool
        _grammar
        _end_plan_error
        _plan_error_found
        exec
        exit
        is_good_plan
        plan
        tests_planned
        tests_run
        wait
        in_todo
        >
      )
    {
        no strict 'refs';

        # another tiny performance hack
        if ( $method =~ /^_/ ) {
            *$method = sub {
                my $self = shift;
                return $self->{$method} unless @_;
                unless ( ( ref $self ) =~ /^TAPx::Parser/ )
                {    # trusted methods
                    $self->_croak("$method() may not be set externally");
                }
                $self->{$method} = shift;
            };
        }
        else {
            *$method = sub {
                my $self = shift;
                return $self->{$method} unless @_;
                $self->{$method} = shift;
            };
        }
    }
}

##############################################################################

=head3 C<good_plan>

Deprecated.  Use C<is_good_plan> instead.

=cut

sub good_plan {
    warn 'good_plan() is deprecated.  Please use "is_good_plan()"';
    goto &is_good_plan;
}

=head1 SYNOPSIS

    use TAPx::Parser;

    my $parser = TAPx::Parser->new( { source => $source } );
    
    while ( my $result = $parser->next ) {
        print $result->as_string;
    }

=head1 DESCRIPTION

C<TAPx::Parser> is designed to produce a proper parse of TAP output.  It is
ALPHA code and should be treated as such.  The interface is now solid, but it
is still subject to change.

For an example of how to run tests through this module, see the simple
harnesses C<examples/>. 

=head1 METHODS

=head2 Class methods

=head3 C<new>

 my $parser = TAPx::Parser->new(\%args);

Returns a new C<TAPx::Parser> object.

The arguments should be a hashref with I<one> of the following keys:

=over 4

=item * C<source>

This is the preferred method of passing arguments to the constructor.  To
determine how to handle the source, the following steps are taken.

If the source contains a newline, it's assumed to be a string of raw TAP
output.

If the source is a reference, it's assumed to be something to pass to the
C<TAPx::Parser::Iterator> constructor.  This is used internally and you should
not use it.

Otherwise, the parser does a C<-e> check to see if the source exists.  If so,
it attempts to execute the source and read the output as a stream.  This is by
far the preferred method of using the parser.

 foreach my $file ( @test_files ) {
     my $parser = TAPx::Parser->new( { source => $file } );
     # do stuff with the parser
 }

=item * C<tap>

The value should be the complete TAP output.

=item * C<exec>

If passed an array reference, will attempt to create the iterator by passing a
C<TAPx::Parser::Source> object to C<TAPx::Parser::Iterator>, using the array
reference strings as the command arguments to C<&IPC::Open3::open3>:

 exec => [ '/usr/bin/ruby', 't/my_test.rb' ]

Note that C<source> and C<exec> are mutually exclusive.

=back

The following keys are optional.

=over 4

=item * C<callback>

If present, each callback corresponding to a given result type will be called
with the result as the argument if the C<run> method is used:

 my %callbacks = (
     test    => \&test_callback,
     plan    => \&plan_callback,
     comment => \&comment_callback,
     bailout => \&bailout_callback,
     unknown => \&unknown_callback,
 );
 
 my $aggregator = TAPx::Parser::Aggregator->new;
 foreach my $file ( @test_files ) {
     my $parser = TAPx::Parser->new(
         {
             source    => $file,
             callbacks => \%callbacks,
         }
     );
     $parser->run;
     $aggregator->add( $file, $parser );
 }

=item * C<switches>

If using a Perl file as a source, optional switches may be passed which will
be used when invoking the perl executable.

 my $parser = TAPx::Parser->new( {
     source   => $test_file,
     switches => '-Ilib',
 } );

=item * C<spool>

If passed a filehandle will write a copy of all parsed TAP to that handle.

=back

=cut

# new implementation supplied by TAPx::Base

##############################################################################

=head2 Instance methods

=head3 C<next>

  my $parser = TAPx::Parser->new( { source => $file } );
  while ( my $result = $parser->next ) {
      print $result->as_string, "\n";
  }

This method returns the results of the parsing, one result at a time.  Note
that it is destructive.  You can't rewind and examine previous results.

If callbacks are used, they will be issued before this call returns.

Each result returned is a subclass of C<TAPx::Parser::Result>.  See that
module and related classes for more information on how to use them.

=cut

sub _next {
    my $self   = shift;
    my $stream = $self->_stream;
    return if $stream->is_last;

    my $result = $self->_grammar->tokenize( $stream->next );
    $self->_start_tap( $stream->is_first );    # must be after $stream->next

    # we still have to test for $result because of all sort of strange TAP
    # edge cases (such as '1..0' plans for skipping everything)
    if ( $result && $result->is_test ) {
        $self->in_todo( $result->has_todo );
        $self->tests_run( $self->tests_run + 1 );
        if ( defined ( my $tests_planned = $self->tests_planned ) ) {
            if ( $self->tests_run > $tests_planned ) {
                $result->is_unplanned(1);
            }
        }
    }

    # must set _end_tap first or else _validate chokes on ending plans
    $self->_validate($result);
    if ( $stream->is_last ) {
        $self->_end_tap(1);
        $self->exit( $stream->exit );
        $self->wait( $stream->wait );
        $self->_finish;
    }
    elsif ( !$result->is_unknown && !$result->is_comment ) {
        $self->_can_ignore_output(0);
    }
    return $result;
}

sub next {
    my $self   = shift;
    my $result = $self->_next;

    if ( defined $result ) {
        my $code;
        if ( $code = $self->_callback_for( $result->type ) ) {
            $code->($result);
        }
        else {
            $self->_make_callback( 'ELSE', $result );
        }
        $self->_make_callback( 'ALL', $result );

        # Echo TAP to spool file
        $self->_write_to_spool($result);
    }

    return $result;
}

sub _write_to_spool {
    my ( $self, $result ) = @_;
    my $spool = $self->_spool or return;
    print $spool $result->raw, "\n";
}

##############################################################################

=head3 C<run>

  $parser->run;

This method merely runs the parser and parses all of the TAP.

=cut

sub run {
    my $self = shift;
    while ( defined( my $result = $self->next ) ) {

        # do nothing
    }
}

{

    # of the following, anything beginning with an underscore is strictly
    # internal and should not be exposed.
    my %initialize = (
        _can_ignore_output => 1,
        _end_tap           => 0,
        _plan_found        => 0,     # how many plans were found
        _start_tap         => 0,
        plan               => '',    # the test plan (e.g., 1..3)
        tap                => '',    # the TAP
        tests_run          => 0,     # actual current test numbers
        results            => [],    # TAP parser results
        skipped            => [],    #
        todo               => [],    #
        passed             => [],    #
        failed             => [],    #
        actual_failed      => [],    # how many tests really failed
        actual_passed      => [],    # how many tests really passed
        todo_passed        => [],    # tests which unexpectedly succeed
        parse_errors       => [],    # perfect TAP should have none
    );

    # We seem to have this list hanging around all over the place. We could
    # probably get it from somewhere else to avoid the repetition.
    my @legal_callback = qw(
      test
      plan
      comment
      bailout
      unknown
      ALL
      ELSE
    );

    sub _initialize {
        my ( $self, $arg_for ) = @_;

        # everything here is basically designed to convert any TAP source to a
        # stream.
        $arg_for ||= {};

        $self->SUPER::_initialize( $arg_for, \@legal_callback );

        my $stream = delete $arg_for->{stream};
        my $tap    = delete $arg_for->{tap};
        my $source = delete $arg_for->{source};
        my $exec   = delete $arg_for->{exec};
        my $merge  = delete $arg_for->{merge};
        my $spool  = delete $arg_for->{spool};
        if ( 1 < grep {defined} $stream, $tap, $source ) {
            $self->_croak(
                "You may only choose one of 'stream', 'tap', or'source'");
        }
        if ( $source && $exec ) {
            $self->_croak(
                '"source" and "exec" are mutually exclusive options');
        }
        if ($tap) {
            $stream = TAPx::Parser::Iterator->new( [ split "\n" => $tap ] );
        }
        elsif ($exec) {
            my $source = TAPx::Parser::Source->new;
            $source->source($exec);
            $stream = $source->get_stream;
            if ( defined $stream ) {
                if ( defined $stream->exit ) {
                    $self->exit( $stream->exit );
                }
                if ( defined $stream->wait ) {
                    $self->wait( $stream->wait );
                }
            }
        }
        elsif ($source) {
            if ( ref $source ) {
                $stream = TAPx::Parser::Iterator->new($source);
            }
            elsif ( -e $source ) {

                my $perl = TAPx::Parser::Source::Perl->new;
                $perl->switches( $arg_for->{switches} )
                  if $arg_for->{switches};

                $stream = $perl->source($source)->get_stream;
                if ( defined $stream ) {
                    if ( defined $stream->exit ) {
                        $self->exit( $stream->exit );
                    }
                    if ( defined $stream->wait ) {
                        $self->wait( $stream->wait );
                    }
                }
            }
            else {
                $self->_croak("Cannot determine source for $source");
            }
        }

        unless ($stream) {
            $self->_croak("PANIC:  could not determine stream");
        }

        $self->_stream($stream);
        $self->_start_tap(undef);
        $self->_end_tap(undef);
        $self->_grammar( TAPx::Parser::Grammar->new($self) )
          ;    # eventually pass a version
        $self->_spool($spool);

        while ( my ( $k, $v ) = each %initialize ) {
            $self->{$k} = 'ARRAY' eq ref $v ? [] : $v;
        }

        return $self;
    }
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
their type.  Sometimes a type method may be overridden in a subclass, but its
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

=head3 C<is_ok>

  if ( $result->is_ok ) { ... }

Reports whether or not a given result has passed.  Anything which is B<not> a
test result returns true.  This is merely provided as a convenient shortcut
which allows you to do this:

 my $parser = TAPx::Parser->new( { source => $source } );
 while ( my $result = $parser->next ) {
     # only print failing results
     print $result->as_string unless $result->is_ok;
 }

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

=head3 C<directive>

 my $directive = $result->directive; 

If a SKIP directive is included with the plan, this method will return it.

 1..0 # SKIP: why bother?

=head3 C<explanation>

 my $explanation = $result->explanation;

If a SKIP directive was included with the plan, this method will return the
explanation, if any.

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

=head3 C<is_ok>

  if ( $result->is_ok ) { ... }

Returns a boolean value indicating whether or not the test passed.  Remember
that for TODO tests, the test always passes.

B<Note:>  this was formerly C<passed>.  The latter method is deprecated and
will issue a warning.

=head3 C<is_actual_ok>

  if ( $result->is_actual_ok ) { ... }

Returns a boolean value indicating whether or not the test passed, regardless
of its TODO status.

B<Note:>  this was formerly C<actual_passed>.  The latter method is deprecated
and will issue a warning.

=head3 C<is_unplanned>

  if ( $test->is_unplanned ) { ... }

If a test number is greater than the number of planned tests, this method will
return true.  Unplanned tests will I<always> return false for C<is_ok>,
regardless of whether or not the test C<has_todo> (see
L<TAPx::Parser::Result::Test> for more information about this).

=head3 C<has_skip>

  if ( $result->has_skip ) { ... }

Returns a boolean value indicating whether or not this test had a SKIP
directive.

=head3 C<has_todo>

  if ( $result->has_todo ) { ... }

Returns a boolean value indicating whether or not this test had a TODO
directive.

Note that TODO tests I<always> pass.  If you need to know whether or not
they really passed, check the C<is_actual_ok> method.

=head3 C<in_todo>

  if ( $parser->in_todo ) { ... }
  
True while the most recent result was a TODO. Becomes true before the
TODO result is returned and stays true until just before the next non-
TODO test is returned.

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
*actual_ok = \&actual_passed;

=head3 C<actual_ok>

This method is a synonym for C<actual_passed>.

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

=head3 C<todo_passed>

 # the test numbers which unexpectedly succeeded
 my @todo_passed = $parser->todo_passed;
 # the number of tests which unexpectedly succeeded 
 my $todo_passed = $parser->todo_passed;

This method lets you know which (or how many) tests actually passed but were
declared as "TODO" tests.

=cut

sub todo_passed { @{ shift->{todo_passed} } }

##############################################################################

=head3 C<todo_failed>

  # deprecated in favor of 'todo_passed'.  This method was horribly misnamed.

This was a badly misnamed method.  It indicates which TODO tests unexpectedly
succeeded.  Will now issue a warning and call C<todo_passed>.

=cut

sub todo_failed {
    warn
      '"todo_failed" is deprecated.  Please use "todo_passed".  See the docs.';
    goto &todo_passed;
}

=head3 C<skipped>

 my @skipped = $parser->skipped; # the test numbers with SKIP directives
 my $skipped = $parser->skipped; # the number of tests with SKIP directives

This method lets you know which (or how many) tests had SKIP directives.

=cut

sub skipped { @{ shift->{skipped} } }

##############################################################################

=head3 C<has_problems>

  if ( $parser->has_problems ) {
      ...
  }

This is a 'catch-all' method which returns true if any tests have currently
failed, any TODO tests unexpectedly succeeded, or any parse errors.

=cut

sub has_problems {
    my $self = shift;
    return $self->failed
      || $self->todo_passed
      || $self->parse_errors
      || $self->wait
      || $self->exit;
}

##############################################################################

=head3 C<is_good_plan>

  if ( $parser->is_good_plan ) { ... }

Returns a boolean value indicating whether or not the number of tests planned
matches the number of tests run.

B<Note:>  this was formerly C<good_plan>.  The latter method is deprecated and
will issue a warning.

And since we're on that subject ...

=head3 C<tests_planned>

  print $parser->tests_planned;

Returns the number of tests planned, according to the plan.  For example, a
plan of '1..17' will mean that 17 tests were planned.

=head3 C<tests_run>

  print $parser->tests_run;

Returns the number of tests which actually were run.  Hopefully this will
match the number of C<< $parser->tests_planned >>.


=head3 C<exit>

  $parser->exit;

Once the parser is done, this will return the exit status.  If the parser ran
an executable, it returns the exit status of the executable.

=head3 C<wait>

  $parser->wait;

Once the parser is done, this will return the wait status.  If the parser ran
an executable, it returns the wait status of the executable.  Otherwise, this
mererely returns the C<exit> status.

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

    my $num = $test->number;

    push @{ $self->{todo} }          => $num if $test->has_todo;
    push @{ $self->{todo_passed} }   => $num if $test->todo_passed;
    push @{ $self->{passed} }        => $num if $test->is_ok;
    push @{ $self->{actual_passed} } => $num if $test->is_actual_ok;
    push @{ $self->{skipped} }       => $num if $test->has_skip;

    push @{ $self->{actual_failed} } => $num if !$test->is_actual_ok;
    push @{ $self->{failed} }        => $num if !$test->is_ok;
}

{
    my %validation_for = (
        test => sub {
            my ( $self, $test ) = @_;
            local *__ANON__ = '__ANON__test_validation';

            $self->_check_ending_plan;
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
            $self->plan( $plan->plan );
            $self->_plan_found( $self->_plan_found + 1 );
            if ( !$self->_start_tap && !$self->_end_tap ) {
                if ( !$self->_end_plan_error && !$self->_can_ignore_output ) {
                    my $line = $plan->as_string;
                    $self->_end_plan_error(
                        "Plan ($line) must be at the beginning or end of the TAP output"
                    );
                }
            }
        },
        bailout => sub {
            my ( $self, $bailout ) = @_;
            local *__ANON__ = '__ANON__bailout_validation';
            $self->_check_ending_plan;
        },
        unknown => sub { },
        comment => sub { },
    );

    sub _check_ending_plan {
        my $self = shift;
        if ( !$self->_plan_error_found
            && ( my $error = $self->_end_plan_error ) )
        {

            # test output found after ending plan
            $self->_add_error($error);
            $self->_plan_error_found(1);
            $self->is_good_plan(0);
        }
        return $self;
    }

    sub _validate {
        my ( $self, $token ) = @_;
        return unless $token;    # XXX edge case for 'no output'
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

sub _finish {
    my $self = shift;

    # sanity checks
    if ( !$self->_plan_found ) {
        $self->_add_error("No plan found in TAP output");
    }
    elsif ( $self->_plan_found > 1 ) {
        $self->_add_error("More than one plan found in TAP output");
    }
    else {
        $self->is_good_plan(1) unless defined $self->is_good_plan;
    }
    if ( $self->tests_run != ( $self->tests_planned || 0 ) ) {
        $self->is_good_plan(0);
        if ( defined( my $planned = $self->tests_planned ) ) {
            my $ran = $self->tests_run;
            $self->_add_error(
                "Bad plan.  You planned $planned tests but ran $ran.");
        }
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

    $self->is_good_plan(0) unless defined $self->is_good_plan;
    return $self;
}

##############################################################################

=head2 CALLBACKS

As mentioned earlier, a "callback" key may be added may be added to the
C<TAPx::Parser> constructor.  If present, each callback corresponding to a
given result type will be called with the result as the argument if the C<run>
method is used.  The callback is expected to be a subroutine reference (or
anonymous subroutine) which is invoked with the parser result as its argument.

 my %callbacks = (
     test    => \&test_callback,
     plan    => \&plan_callback,
     comment => \&comment_callback,
     bailout => \&bailout_callback,
     unknown => \&unknown_callback,
 );
 
 my $aggregator = TAPx::Parser::Aggregator->new;
 foreach my $file ( @test_files ) {
     my $parser = TAPx::Parser->new(
         {
             source    => $file,
             callbacks => \%callbacks,
         }
     );
     $parser->run;
     $aggregator->add( $file, $parser );
 }

Callbacks may also be added like this:

 $parser->callback( test => \&test_callback );
 $parser->callback( plan => \&plan_callback );

There are, at the present time, seven keys allowed for callbacks.  These keys
are case-sensitive.

=over 4

=item 1 C<test>

Invoked if C<< $result->is_test >> returns true.

=item 2 C<plan>

Invoked if C<< $result->is_plan >> returns true.

=item 3 C<comment>

Invoked if C<< $result->is_comment >> returns true.

=item 4 C<bailout>

Invoked if C<< $result->is_unknown >> returns true.

=item 5 C<unknown>

Invoked if C<< $result->is_unknown >> returns true.

=item 6 C<ELSE>

If a result does not have a callback defined for it, this callback will be
invoked.  Thus, if all five of the previous result types are specified as
callbacks, this callback will I<never> be invoked.

=item 7 C<ALL>

This callback will always be invoked and this will happen for each result
after one of the above six callbacks is invoked.  For example, if
C<Term::ANSIColor> is loaded, you could use the following to color your test
output:

 my %callbacks = (
     test => sub {
         my $test = shift;
         if ( $test->is_ok && not $test->directive ) {
             # normal passing test
             print color 'green';
         }
         elsif ( !$test->is_ok ) {    # even if it's TODO
             print color 'white on_red';
         }
         elsif ( $test->has_skip ) {
             print color 'white on_blue';
 
         }
         elsif ( $test->has_todo ) {
             print color 'white';
         }
     },
     ELSE => sub {
         # plan, comment, and so on (anything which isn't a test line)
         print color 'black on_white';
     },
     ALL => sub {
         # now print them
         print shift->as_string;
         print color 'reset';
         print "\n";
     },
 );

See C<examples/tprove_color> for an example of this.

=back

=head1 TAP GRAMMAR

If you're looking for an EBNF grammar, see L<TAPx::Parser::Grammar>.

=head1 BACKWARDS COMPATABILITY

The Perl-QA list attempted to ensure backwards compatability with
L<Test::Harness>.  However, there are some minor differences.

=head2 Differences

=over 4

=item * TODO plans

A little-known feature of C<Test::Harness> is that it supported TODO lists in
the plan:

 1..2 todo 2
 ok 1 - We have liftoff
 not ok 2 - Anti-gravity device activated

Under L<Test::Harness>, test number 2 would I<pass> because it was listed as a
TODO test on the plan line.  However, we are not aware of anyone actually
using this feature and hard-coding test numbers is discouraged because it's
very easy to add a test and break the test number sequence.  This makes test
suites very fragile.  Instead, the following should be used:

 1..2
 ok 1 - We have liftoff
 not ok 2 - Anti-gravity device activated # TODO

=item * 'Missing' tests

It rarely happens, but sometimes a harness might encounter 'missing tests:

 ok 1
 ok 2
 ok 15
 ok 16
 ok 17

L<Test::Harness> would report tests 3-14 as having failed.  For the
C<TAPx::Parser>, these tests are not considered failed because they've never
run.  They're reported as parse failures (tests out of sequence).

=back

=head1 ACKNOWLEDGEMENTS

All of the following have helped.  Bug reports, patches, (im)moral support, or
just words of encouragement have all been forthcoming.

=over 4

=item * Michael Schwern

=item * Andy Lester

=item * chromatic

=item * GEOFFR

=item * Shlomi Fish
         
=item * Torsten Schoenfeld

=item * Jerry Gay

=item * Aristotle

=item * Adam Kennedy

=item * Yves Orton

=item * Adrian Howard

=item * Sean & Lil

=item * Andreas J. Koenig

=item * Florian Ragwitz

=item * Corion

=item * Mark Stosberg

=item * Andy Armstrong

=item * Matt Kraai

=back

=head1 AUTHOR

Curtis "Ovid" Poe, C<< <ovid@cpan.org> >>
Andy Armstong, C<< <andy@hexten.net> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-tapx-parser@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=TAPx-Parser>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

Obviously, bugs which include patches are best.  If you prefer, you can patch
against bleed by via anonymous checkout of the latest version:

 svn checkout http://svn.hexten.net/tapx

=head1 COPYRIGHT & LICENSE

Copyright 2006 Curtis "Ovid" Poe, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;
