package TAPx::Parser::Streamed;

use strict;

use TAPx::Parser;
use TAPx::Parser::Results;

use vars qw($VERSION @ISA);
@ISA = 'TAPx::Parser';

=head1 NAME

TAPx::Parser::Streamed - Parse TAP output from a stream

=head1 VERSION

Version 0.30

=cut

$VERSION = '0.30';

=head1 DESCRIPTION

C<TAPx::Parser::Streamed> is a subclass of C<TAPx::Parser>.  Do not
instantiate this class directly.  C<TAPx::Parser> will do that for you.

=cut

sub _initialize {
    my ( $self, $arg_for ) = @_;
    my $stream = delete $arg_for->{stream};
    $self->SUPER::_initialize($arg_for);
    $self->_stream($stream);
    $self->_start_tap(undef);
    $self->_end_tap(undef);
    return $self;
}

sub _lex {
    my ( $self, $tap ) = @_;
    my @remaining_tap = defined $tap
         ? $tap !~ /\n/ ? $tap : split /\n/, $tap
         : ();

    my @tokens;
    my $grammar = $self->_grammar;
    LINE: while ( defined( my $line = shift @remaining_tap ) ) {

        # XXX this is going to cause issues with streams
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
    return @tokens;
}

sub next {
    my $self   = shift;
    my $stream = $self->_stream;
    return if $stream->is_last;
    my $next = $stream->next;
    $self->_start_tap( $stream->is_first ? 1 : 0 );

    my @tokens = $self->_lex($next);
    my $token;
    if (@tokens) {
        $token = TAPx::Parser::Results->new( @tokens );
    }

    # must set _end_tap first or else _validate chokes on ending plans
    if ( $stream->is_last || ! $token ) {
        $self->_end_tap(1);
        $self->exit($stream->exit);
        $self->wait($stream->wait);
    }
    $self->_validate($token);

    # must call _finish after _validate
    if ( $stream->is_last || ! $token ) {
        $self->_finish;
    }
    return $token;
}

=head1 OVERRIDDEN METHODS

C<TAPx::Parser::Streamed> is a subclass of C<TAPx::Parser>.  The following
methods have been overridden.  This information is here mainly to silence the
screams of the pod coverage tests.

=over 4

=item * C<_initialize>

=item * C<_lex>

=item * C<next>

=back

=head1 AUTHOR

Curtis "Ovid" Poe, C<< <ovid@cpan.org> >>

=head1 BUGS

Please report any bugs or feature requests to
C<bug-tap-parser@rt.cpan.org>, or through the web interface at
L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=TAP-Parser>.
I will be notified, and then you'll automatically be notified of progress on
your bug as I make changes.

=head1 ACKNOWLEDGEMENTS

=head1 COPYRIGHT & LICENSE

Copyright 2006 Curtis "Ovid" Poe, all rights reserved.

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself.

=cut

1;

__END__
(* 
    For the time being, I'm cheating on the EBNF by allowing 
    certain terms to be defined by POSIX character classes by
    using the following syntax:

      digit ::= [:digit:];

    As far as I am away, that's not valid EBNF.  Sue me.  I
    didn't know how to write "char" otherwise (Unicode issues).  
    Suggestions welcome.
*)

(* POSIX character classes and other terminals *)

digit          ::= [:digit:];
character      ::= [:print:];
positiveNumber ::= (digit - '0') {digit};

(* And on to the real grammar ... *)

(* "plan => $num" versus "no_plan" *)

tap    ::= plan tests | tests plan;

plan   ::= '1..' positiveNumber;

(* Gotta have at least one test *)

tests  ::= test {test};

(* 
    The "positiveNumber" is the test number and should 
    always be one greater than the previous test number.
*)
   
test   ::= status (positiveNumber description)? directive?

status ::= 'not '? 'ok ';

(*
    Description must not begin with a digit or contain a 
    hash mark.
*)

description ::= (character - (digit '#')) {character - '#'}

directive   ::= ( 'TODO' | 'SKIP' ) ' ' {character}
