package TAPx::Parser::Grammar;

use strict;
use warnings;
use vars qw($VERSION);

=head1 NAME

TAPx::Parser::Grammar - A grammar for the original TAP version.

=head1 VERSION

Version 0.12

=cut

$VERSION = '0.12';

=head1 DESCRIPTION

C<TAPx::Parser::Gramamr> is actually just a means for identifying individual
chunks (usually lines) of TAP.  Many of the actual grammar rules are embedded
in C<TAPx::Parser>.

Do not attempt to use this class directly.  It won't make sense.  It's mainly
here to ensure that we will be able to have pluggable grammars when TAP is
expanded at some future date (plus, this stuff was really cluttering the
parser).

=cut

##############################################################################

=head2 Class Methods


=head3 C<new>

  my $grammar = TAPx::Grammar->new;

Returns TAP grammar object.  Future versions may accept a version number.

=cut

sub new {
    my ($class) = @_;
    bless {}, $class;
}

# XXX the 'not' and 'ok' might be on separate lines in VMS ...

my $ok          = qr/(?:not )?ok\b/;
my $num         = qr/\d+/;
my $description = qr/[^\d#](?:(?:\\\\)*\\#|[^#])*/;    # escaped # is allowed
my $directive   = qr/
                    (?i:
                        \#\s+
                        (TODO|SKIP)\s*
                        (.*)
                    )?
                    /x;

#
# Ooh, bad Ovid, no biscuit.
#
# Each token, when generated, should have a 'type' key.  That will simplify
# the result class generation.  I'll fix this later.
#

my %token_for = (
    plan => {
        syntax  => qr/^1\.\.(\d+)/,
        handler => sub {
            my ( $self, $line ) = @_;
            my $tests_planned = $1;
            return $self->_make_plan_token( $line, $tests_planned );
        },
    },
    test => {
        syntax => qr/^
            ($ok)
            \s*
            ($num)?
            \s*
            ($description)?
            $directive    # $4 = directive, $5 = explanation
        \z/x,
        handler => sub {
            my ( $self, $line ) = @_;
            my ( $ok, $num, $desc, $dir, $explanation )
              = ( $1, $2, $3, $4, $5 );
            return $self->_make_test_token(
                $line,
                $ok,
                $num,
                $desc,
                uc $dir,
                $explanation
            );
        },
    },
    comment => {
        syntax  => qr/^#(.*)/,
        handler => sub {
            my ( $self, $line ) = @_;
            my $comment = $1;
            return $self->_make_comment_token( $line, $comment );
        },
    },
    bailout => {
        syntax  => qr/^Bail out!\s*(.*)/,
        handler => sub {
            my ( $self, $line ) = @_;
            my $explanation = $1;
            return $self->_make_bailout_token( $line, $explanation );
        },
    }
);

##############################################################################

=head2 Instance methods

=head3 C<token_types>

  my @types = $grammar->token_types;

Returns the different types of tokens which this grammar can parse.

=cut

sub token_types { keys %token_for }

##############################################################################

=head3 C<syntax_for>

  my $syntax = $grammar->syntax_for($token_type);

Returns a pre-compiled regular expression which will match a chunk of TAP
corresponding to the token type.  For example (not that you should really pay
attention to this, C<< $grammar->syntax_for('comment') >> will return
C<< qr/^#(.*)/ >>.

=cut

sub syntax_for {
    my ( $proto, $type ) = @_;
    return $token_for{$type}{syntax};
}

##############################################################################

=head3 C<handler_for>

  my $handler = $grammar->handler_for($token_type);

Returns a code reference which, when passed an appropriate line of TAP,
returns the lexed token corresponding to that line.  As a result, the basic
TAP parsing loop looks similar to the following:

 my @tokens;
 my $grammar = TAPx::Grammar->new;
 LINE: while ( defined( my $line = $parser->_next_chunk_of_tap ) ) {
     foreach my $type ( $grammar->token_types ) {
         my $syntax  = $grammar->syntax_for($type);
         if ( $line =~ $syntax ) {
             my $handler = $grammar->handler_for($type);
             push @tokens => $grammar->$handler($line);
             next LINE;
         }
     }
     push @tokens => $grammar->_make_unknown_token($line);
 }

=cut

sub handler_for {
    my ( $proto, $type ) = @_;
    return $token_for{$type}{handler};
}

sub _make_plan_token {
    my ( $self, $line, $tests_planned ) = @_;
    return {
        type          => 'plan',
        raw           => $line,
        tests_planned => $tests_planned,
    };
}

sub _make_test_token {
    my ( $self, $line, $ok, $num, $desc, $dir, $explanation ) = @_;
    my %test;
    @test{qw<ok test_num description directive explanation>}
      = map { _trim($_) } ( $ok, $num, $desc, uc($dir), $explanation );
    $test{raw}  = $line;
    $test{type} = 'test';
    return \%test;
}

sub _make_unknown_token {
    my ( $self, $line ) = @_;
    return {
        raw  => $line,
        type => 'unknown',
    };
}

sub _make_comment_token {
    my ( $self, $line, $comment ) = @_;
    return {
        type    => 'comment',
        raw     => $line,
        comment => _trim($1)
    };
}

sub _make_bailout_token {
    my ( $self, $line, $explanation ) = @_;
    return {
        type    => 'bailout',
        raw     => $line,
        bailout => _trim($1)
    };
}

sub _trim {
    my $data = shift || '';
    $data =~ s/^\s+//;
    $data =~ s/\s+$//;
    return $data;
}

1;
