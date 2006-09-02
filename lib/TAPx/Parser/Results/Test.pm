package TAPx::Parser::Results::Test;

use strict;
use warnings;
use base 'TAPx::Parser::Results';
use vars qw($VERSION);

=head1 NAME

TAPx::Parser::Results::Test - Test result token.

=head1 VERSION

Version 0.20

=cut

$VERSION = '0.20';

=head1 DESCRIPTION

This is a subclass of C<TAPx::Parser::Results>.  A token of this class will be
returned if a test line is encountered.

 1..1
 ok 1 - woo hooo!

=head1 OVERRIDDEN METHODS

This class is the workhorse of the TAPx::Parser system.  Most TAP lines will
be test lines and if C<< $result->is_test >>, then you have a bunch of methods
at your disposal.

=head2 Instance methods

=cut

##############################################################################

=head3 C<ok>

  my $ok = $result->ok;

Returns the literal text of the C<ok> or C<not ok> status.

=cut

sub ok          { shift->{ok} }

##############################################################################

=head3 C<number>

  my $test_number = $result->number;

Returns the number of the test, even if the original TAP output did not supply
that number.

=cut

sub number      { shift->{test_num} }

sub _number {
    my ($self, $number) = @_;
    $self->{test_num} = $number;
}

##############################################################################

=head3 C<description>

  my $description = $result->description;

Returns the description of the test, if any.  This is the portion after the
test number but before the directive.

=cut


sub description { shift->{description} }

##############################################################################

=head3 directive

  my $directive = $result->directive;

Returns either C<TODO> or C<SKIP> if either directive was present for a test
line.

=cut

sub directive   { shift->{directive} }

##############################################################################

=head3 explanation 

  my $explanation = $result->explanation;

If a test had either a C<TODO> or C<SKIP> directive, this method will return
the accompanying explantion, if present.

  not ok 17 - 'Pigs can fly' # TODO not enough acid

For the above line, the explanation is I<not enough acid>.

=cut

sub explanation { shift->{explanation} }

##############################################################################

=head3 passed

  if ( $result->passed ) { ... }

Returns a boolean value indicating whether or not the test passed.  Remember
that for TODO tests, the sense of passing and failing is reversed.

=cut

sub passed {
    my $self = shift;

    # TODO directives reverse the sense of a test.
    return $self->has_todo ? $self->ok =~ /not/ : $self->ok !~ /not/;
}

##############################################################################

=head3 C<actual_passed>

  if ( $result->actual_passed ) { ... }

Returns a boolean value indicating whether or not the test passed, regardless
of its TODO status.

=cut

sub actual_passed {
    my $self = shift;
    return $self->{ok} !~ /not/;
}

##############################################################################

=head3 C<todo_failed>

  if ( $test->todo_failed ) {
     # test unexpectedly succeeded
  }

If this is a TODO test and an 'ok' line, this method returns true.
Otherwise, it will always return false (regardless of passing status on
non-todo tests).

This is used to track which tests unexpectedly succeeded.

=cut

sub todo_failed {
    my $self = shift;
    return $self->has_todo && $self->actual_passed;
}

##############################################################################

=head3 C<has_skip>

  if ( $result->has_skip ) { ... }

Returns a boolean value indicating whether or not this test has a SKIP
directive.

=cut

sub has_skip { 'SKIP' eq shift->{directive} }

##############################################################################

=head3 C<has_todo>

  if ( $result->has_todo ) { ... }

Returns a boolean value indicating whether or not this test has a TODO
directive.

=cut

sub has_todo { 'TODO' eq shift->{directive} }

##############################################################################

=head3 as_string

  print $result->as_string;

This method prints the test as a string.  It will probably be similar, but
not necessarily identical, to the original test line.  Directives are
capitalized, some whitespace may be trimmed and a test number will be added if
it was not present in the original line.  If you need the original text of the
test line, use the C<raw> method.

=cut

sub as_string {
    my $self   = shift;
    my $string = $self->ok;
    if ( my $number = $self->number ) {
        $string .= " $number";
    }
    if ( my $description = $self->description ) {
        $string .= " $description";
    }
    if ( my $directive = $self->directive ) {
        my $explanation = $self->explanation;
        $string .= " # $directive $explanation";
    }
    return $string;
}

1;
