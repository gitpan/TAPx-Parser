# -*- Mode: cperl; cperl-indent-level: 4 -*-
package TAPx::Harness::Compatible::Point;

use strict;
use vars qw($VERSION);
$VERSION = '0.50_07';

=head1 NAME

TAPx::Harness::Compatible::Point - object for tracking a single test point

=head1 SYNOPSIS

One TAPx::Harness::Compatible::Point object represents a single test point.

=head1 CONSTRUCTION

=head2 new()

    my $point = new TAPx::Harness::Compatible::Point;

Create a test point object.

=cut

sub new {
    my $class = shift;
    my $self = bless {}, $class;

    return $self;
}

=head1 from_test_line( $line )

Constructor from a TAP test line, or empty return if the test line
is not a test line.

=cut

sub from_test_line {
    my $class = shift;
    my $line = shift or return;

    # We pulverize the line down into pieces in three parts.
    my ( $not, $number, $extra )
      = ( $line =~ /^(not )?ok\b(?:\s+(\d+))?\s*(.*)/ )
      or return;

    my $point = $class->new;
    $point->set_number($number);
    $point->set_ok( !$not );

    if ($extra) {
        my ( $description, $directive ) = split( /(?:[^\\]|^)#/, $extra, 2 );
        $description =~ s/^- //;    # Test::More puts it in there
        $point->set_description($description);
        if ($directive) {
            $point->set_directive($directive);
        }
    }    # if $extra

    return $point;
}    # from_test_line()

=head1 ACCESSORS

Each of the following fields has a getter and setter method.

=over 4

=item * ok

=item * number

=back

=cut

sub ok { my $self = shift; $self->{ok} }

sub set_ok {
    my $self = shift;
    my $ok   = shift;
    $self->{ok} = $ok ? 1 : 0;
}

sub pass {
    my $self = shift;

    return ( $self->ok || $self->is_todo || $self->is_skip ) ? 1 : 0;
}

sub number { my $self = shift; $self->{number} }
sub set_number { my $self = shift; $self->{number} = shift }

sub description { my $self = shift; $self->{description} }

sub set_description {
    my $self = shift;
    $self->{description} = shift;
    $self->{name}        = $self->{description};    # history
}

sub directive { my $self = shift; $self->{directive} }

sub set_directive {
    my $self      = shift;
    my $directive = shift;

    $directive =~ s/^\s+//;
    $directive =~ s/\s+$//;
    $self->{directive} = $directive;

    my ( $type, $reason ) = ( $directive =~ /^\s*(\S+)(?:\s+(.*))?$/ );
    $self->set_directive_type($type);
    $reason = "" unless defined $reason;
    $self->{directive_reason} = $reason;
}

sub set_directive_type {
    my $self = shift;
    $self->{directive_type} = lc shift;
    $self->{type}           = $self->{directive_type};    # History
}

sub set_directive_reason {
    my $self = shift;
    $self->{directive_reason} = shift;
}
sub directive_type   { my $self = shift; $self->{directive_type} }
sub type             { my $self = shift; $self->{directive_type} }
sub directive_reason { my $self = shift; $self->{directive_reason} }
sub reason           { my $self = shift; $self->{directive_reason} }

sub is_todo {
    my $self = shift;
    my $type = $self->directive_type;
    return $type && ( $type eq 'todo' );
}

sub is_skip {
    my $self = shift;
    my $type = $self->directive_type;
    return $type && ( $type eq 'skip' );
}

sub diagnostics {
    my $self = shift;
    return @{ $self->{diagnostics} } if wantarray;
    return join( "\n", @{ $self->{diagnostics} } );
}
sub add_diagnostic { my $self = shift; push @{ $self->{diagnostics} }, @_ }

1;

=head1 TO DOCUMENT

=over

=item add_diagnostic

TODO: Document add_diagnostic

=item description

TODO: Document description

=item diagnostics

TODO: Document diagnostics

=item directive

TODO: Document directive

=item directive_reason

TODO: Document directive_reason

=item directive_type

TODO: Document directive_type

=item from_test_line

TODO: Document from_test_line

=item is_skip

TODO: Document is_skip

=item is_todo

TODO: Document is_todo

=item pass

TODO: Document pass

=item reason

TODO: Document reason

=item set_description

TODO: Document set_description

=item set_directive

TODO: Document set_directive

=item set_directive_reason

TODO: Document set_directive_reason

=item set_directive_type

TODO: Document set_directive_type

=item set_number

TODO: Document set_number

=item set_ok

TODO: Document set_ok

=item type

TODO: Document type

=back
