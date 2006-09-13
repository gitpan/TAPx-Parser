package TAPx::Parser::Iterator;

use strict;
use vars qw($VERSION);

=head1 NAME

TAPx::Parser::Iterator - Internal TAPx::Parser Iterator

=head1 VERSION

Version 0.22

=cut

$VERSION = '0.22';

=head1 SYNOPSIS

  use TAPx::Parser::Iterator;
  my $it = TAPx::Parser::Iterator->new(\*TEST);
  my $it = TAPx::Parser::Iterator->new(\@array);

  my $line = $it->next;
  if ( $it->first ) { ... }
  if ( $it->last ) { ... }

Originally ripped off from C<Test::Harness>.

=head1 DESCRIPTION

B<FOR INTERNAL USE ONLY!>

This is a simple iterator wrapper for arrays and filehandles.

=head2 new()

Create an iterator.

=head2 next()

Iterate through it, of course.

=head2 first()

Returns true if on the first line.  Must be called I<after> C<next()>.

=head2 last()

Returns true if on or after the last line.  Must be called I<after> C<next()>.

=cut

sub new {
    my ( $proto, $thing ) = @_;

    my $self = {};
    if ( ref $thing eq 'GLOB' ) {
        return TAPx::Parser::Iterator::FH->new($thing);
    }
    elsif ( ref $thing eq 'ARRAY' ) {
        return TAPx::Parser::Iterator::ARRAY->new($thing);
    }
    else {
        warn "Can't iterate with a ", ref $thing;
    }

    return $self;
}

package TAPx::Parser::Iterator::FH;

@TAPx::Parser::Iterator::FH::ISA = 'TAPx::Parser::Iterator';

sub new {
    my ( $class, $thing ) = @_;
    bless {
        fh    => $thing,
        first => undef,
        next  => undef,
        last  => undef,
    }, $class;
}

sub first { $_[0]->{first} }
sub last  { $_[0]->{last} }

sub next {
    my $self = shift;
    my $fh   = $self->{fh};

    local $/ = "\n";
    if ( defined $self->{next} ) {
        my $line = $self->{next};
        if ( defined ( my $next = <$fh> ) ) {
            chomp ( $self->{next} = $next );
            $self->{first} = 0;
        }
        else {
            $self->{last} = 1;
            $self->{next} = undef;
        }
        return $line;
    }
    else {
        $self->{first} = 1 unless $self->last;
        local $^W;   # Don't want to chomp undef values
        chomp( my $line = <$fh> );
        chomp( $self->{next} = <$fh> );
        return $line;
    }
}

package TAPx::Parser::Iterator::ARRAY;

@TAPx::Parser::Iterator::ARRAY::ISA = 'TAPx::Parser::Iterator';

sub new {
    my ( $class, $thing ) = @_;
    chomp @$thing;
    bless {
        idx   => 0,
        array => $thing,
    }, $class;
}

sub first { 1 == $_[0]->{idx} }
sub last  { @{ $_[0]->{array} } <= $_[0]->{idx} }

sub next {
    my $self = shift;
    return $self->{array}->[ $self->{idx}++ ];
}

"Steve Peters, Master Of True Value Finding, was here.";
