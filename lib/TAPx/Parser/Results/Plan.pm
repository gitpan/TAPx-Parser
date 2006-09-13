package TAPx::Parser::Results::Plan;

use strict;
use warnings;
use base 'TAPx::Parser::Results';
use vars qw($VERSION);

=head1 NAME

TAPx::Parser::Results::Plan - Plan result token.

=head1 VERSION

Version 0.22

=cut

$VERSION = '0.22';

=head1 DESCRIPTION

This is a subclass of C<TAPx::Parser::Results>.  A token of this class will be
returned if a plan line is encountered.

 1..1
 ok 1 - woo hooo!

C<1..1> is the plan.  Gotta have a plan.

=head1 OVERRIDDEN METHODS

Mainly listed here to shut up the pitiful screams of the pod coverage tests.
They keep me awake at night.

=over 4

=item * C<as_string>

=item * C<raw>

=back

=cut

##############################################################################

=head2 Instance methods

=head3 C<plan> 

  if ( $result->is_plan ) {
     print $result->plan;
  }

This is merely a synonym for C<as_string>.

=cut

sub plan { shift->{raw} }

##############################################################################

=head3 C<tests_planned>

  my $planned = $result->tests_planned;

Returns the number of tests planned.  For example, a plan of C<1..17> will
cause this method to return '17'.

=cut

sub tests_planned { shift->{tests_planned} }

1;
