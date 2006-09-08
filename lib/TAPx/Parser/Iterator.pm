package TAPx::Parser::Iterator;

use strict;
use vars qw($VERSION);

=head1 NAME

TAPx::Parser::Iterator - Internal TAPx::Parser Iterator

=head1 VERSION

Version 0.21

=cut

$VERSION = '0.21';

=head1 SYNOPSIS

  use TAPx::Parser::Iterator;
  my $it = TAPx::Parser::Iterator->new(\*TEST);
  my $it = TAPx::Parser::Iterator->new(\@array);

  my $line = $it->next;

Gratuitously ripped off from C<Test::Harness>.

=head1 DESCRIPTION

B<FOR INTERNAL USE ONLY!>

This is a simple iterator wrapper for arrays and filehandles.

=head2 new()

Create an iterator.

=head2 next()

Iterate through it, of course.

=cut

sub new {
    my($proto, $thing) = @_;

    my $self = {};
    if( ref $thing eq 'GLOB' ) {
        bless $self, 'TAPx::Parser::Iterator::FH';
        $self->{fh} = $thing;
    }
    elsif( ref $thing eq 'ARRAY' ) {
        bless $self, 'TAPx::Parser::Iterator::ARRAY';
        $self->{idx}   = 0;
        chomp @$thing;
        $self->{array} = $thing;
    }
    else {
        warn "Can't iterate with a ", ref $thing;
    }

    return $self;
}

package TAPx::Parser::Iterator::FH;
sub next {
    my $fh = $_[0]->{fh};

    # readline() doesn't work so good on 5.5.4.
    local $/ = "\n";
    my $line = scalar <$fh> or return;
    chomp $line;
    return $line;
}


package TAPx::Parser::Iterator::ARRAY;
sub next {
    my $self = shift;
    return $self->{array}->[$self->{idx}++];
}

"Steve Peters, Master Of True Value Finding, was here.";
