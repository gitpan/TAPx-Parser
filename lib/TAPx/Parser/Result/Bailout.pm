package TAPx::Parser::Result::Bailout;

use strict;

use vars qw($VERSION @ISA);
use TAPx::Parser::Result;
@ISA = 'TAPx::Parser::Result';

=head1 NAME

TAPx::Parser::Result::Bailout - Bailout result token.

=head1 VERSION

Version 0.50_07

=cut

$VERSION = '0.50_07';

=head1 DESCRIPTION

This is a subclass of C<TAPx::Parser::Result>.  A token of this class will be
returned if a bail out line is encountered.

 1..5
 ok 1 - woo hooo!
 Bail out! Well, so much for "woo hooo!"

=head1 OVERRIDDEN METHODS

Mainly listed here to shut up the pitiful screams of the pod coverage tests.
They keep me awake at night.

=over 4

=item * C<as_string>

=back

=cut

##############################################################################

=head2 Instance methods

=head3 C<explanation>

  if ( $result->is_bailout ) {
      my $explanation = $result->explanation;
      print "We bailed out because ($explanation)";
  }

If, and only if, a token is a bailout token, you can get an "explanation" via
this method.  The explanation is the text after the mystical "Bail out!" words
which appear in the tap output.

=cut

sub explanation { shift->{bailout} }
sub as_string   { shift->{bailout} }

1;
