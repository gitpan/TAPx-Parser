package TAPx::Parser::Results;

use strict;
use warnings;
use vars qw($VERSION);

use TAPx::Parser::Results::Plan;
use TAPx::Parser::Results::Test;
use TAPx::Parser::Results::Comment;
use TAPx::Parser::Results::Bailout;
use TAPx::Parser::Results::Unknown;

BEGIN {
    no strict 'refs';
    foreach my $token (qw<plan comment test bailout unknown>) {
        my $method = "is_$token";
        *$method = sub { return $token eq shift->type };
    }
}

##############################################################################

=head1 NAME

TAPx::Parser::Results - TAPx::Parser output

=head1 VERSION

Version 0.21

=cut

$VERSION = '0.21';

=head2 DESCRIPTION

This is merely a factory class which returns an object representing the
current bit of test data from TAP (usually a line).  It's for internal use
only and should not be relied upon.

=cut

# note that this is bad.  Makes it very difficult to subclass, but then, it
# would be a lot of work to subclass this system.
my %class_for = (
    plan    => 'TAPx::Parser::Results::Plan',
    test    => 'TAPx::Parser::Results::Test',
    comment => 'TAPx::Parser::Results::Comment',
    bailout => 'TAPx::Parser::Results::Bailout',
    unknown => 'TAPx::Parser::Results::Unknown',
);

##############################################################################

=head2 METHODS

=head3 C<new>

  my $result = TAPx::Parser::Result->new($token);

Returns an instance the appropriate class for the test token passed in.

=cut

sub new {
    my ( $class, $token ) = @_;
    my $type = $token->{type};
    return bless $token => $class_for{$type}
      if exists $class_for{$type};
    require Carp;
    require Data::Dumper;
    $Data::Dumper::Indent = 1;
    $Data::Dumper::Terse  = 1;
    $token                = Data::Dumper::Dumper($token);

    # this should never happen!
    Carp::croak "Could not determine class for\n$token";
}

=head3 Boolean methods

The following methods all return a boolean value and are to be overridden in
the appropriate subclass.

=over 4

=item * C<is_plan>

Indicates whether or not this is the test plan line.

 1..3

=item * C<is_test>

Indicates whether or not this is a test line.

 is $foo, $bar, $description;

=item * C<is_comment>

Indicates whether or not this is a comment.

 # this is a comment

=item * C<is_bailout>

Indicates whether or not this is bailout line.

 Bail out! We're out of dilithium crystals.

=item * C<is_unknown>

Indicates whether or not the current line could be parsed.

 ... this line is junk ...

=back

=cut

##############################################################################

=head3 C<raw>

  print $result->raw;

Returns the original line of text which was parsed.

=cut

sub raw { shift->{raw} }

##############################################################################

=head3 C<type>

  my $type = $result->type;

Returns the "type" of a token, such as C<comment> or C<test>.

=cut

sub type { shift->{type} }

##############################################################################

=head3 C<as_string>

  print $result->as_string;

Prints a string representation of the token.  This might not be the exact
output, however.  Tests will have test numbers added if not present, TODO and
SKIP directives will be capitalized and, in general, things will be cleaned
up.  If you need the original text for the token, see the C<raw> method.

=cut

sub as_string { shift->{raw} }

1;
