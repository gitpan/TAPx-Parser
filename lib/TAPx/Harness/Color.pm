package TAPx::Harness::Color;

use strict;
use warnings;

use TAPx::Parser;
use TAPx::Harness;

use vars qw($VERSION @ISA);
@ISA = 'TAPx::Harness';

use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );

my $NO_COLOR;

BEGIN {
    $NO_COLOR = 0;

    if (IS_WIN32) {
        eval 'use Win32::Console';
        if ($@) {
            $NO_COLOR = $@;
        }
        else {
            my $console = Win32::Console->new( STD_OUTPUT_HANDLE() );

            # eval here because we might not know about these variables
            my $fg = eval '$FG_LIGHTGRAY';
            my $bg = eval '$BG_BLACK';

            *_set_color = sub {
                my $self  = shift;
                my $color = shift;

                my $var;
                if ( $color eq 'reset' ) {
                    $fg = eval '$FG_LIGHTGRAY';
                    $bg = eval '$BG_BLACK';
                }
                elsif ( $color =~ /^on_(.+)$/ ) {
                    $bg = eval '$BG_' . uc($1);
                }
                else {
                    $fg = eval '$FG_' . uc($color);
                }

                # In case of colors that aren't defined
                $self->_set_color('reset')
                  unless defined $bg && defined $fg;

                $console->Attr( $bg | $fg );
            };

           # Not sure if we'll have buffering problems using print instead
           # of $console->Write(). Don't want to override output unnecessarily
           # though and it /seems/ to work OK.
           #
           # *output = sub {
           #     my $self = shift;
           #     $console->Write($_) for @_;
           #     #print @_;
           # };
        }
    }
    else {
        eval 'use Term::ANSIColor';
        if ($@) {
            $NO_COLOR = $@;
        }
        else {
            *_set_color = sub {
                my $self  = shift;
                my $color = shift;
                $self->output( color($color) );
            };
        }
    }

    if ($NO_COLOR) {
        *_set_color = sub { };
    }
}

=head1 NAME

TAPx::Harness::Color - Run Perl test scripts with color

=head1 VERSION

Version 0.50_07

=cut

$VERSION = '0.50_07';

=head1 DESCRIPTION

Note that this harness is I<experimental>.  You may not like the colors I've
chosen and I haven't yet provided an easy way to override them.

This test harness is the same as C<TAPx::Harness>, but test results are output
in color.  Passing tests are printed in green.  Failing tests are in red.
Skipped tests are blue on a white background and TODO tests are printed in
white.

If C<Term::ANSIColor> cannot be found or if running under Windows, tests will
be run without color.

=head1 SYNOPSIS

 use TAPx::Harness::Color;
 my $harness = TAPx::Harness::Color->new( \%args );
 $harness->runtests(@tests);

=head1 METHODS

=head2 Class methods

=head3 C<new>

 my %args = (
    verbose => 1,
    lib     => [ 'lib', 'blib/lib' ],
    shuffle => 0,
 )
 my $harness = TAPx::Harness::Color->new( \%args );

The constructor returns a new C<TAPx::Harness::Color> object.  If
C<Term::ANSIColor> is not installed, returns a C<TAPx::Harness> object.  See
C<TAPx::Harness> for more details.

=cut

sub new {
    my $class = shift;
    if ($NO_COLOR) {
        warn "Cannot run tests in color: $NO_COLOR";
        return TAPx::Harness->new(@_);
    }
    return $class->SUPER::new(@_);
}

##############################################################################

=head3 C<failure_output>

  $harness->failure_output(@list_of_strings_to_output);

Overrides L<TAPx::Harness> C<failure_output> to output failure information in
red.

=cut

sub failure_output {
    my $self = shift;
    $self->_set_colors('red');
    my $out = join( '', @_ );
    my $has_newline = chomp $out;
    $self->output($out);
    $self->_set_colors('reset');
    $self->output($/)
      if $has_newline;
}

# Set terminal color
sub _set_colors {
    my $self = shift;
    for my $color (@_) {
        $self->_set_color($color);
    }
}

sub _process {
    my ( $self, $parser, $result ) = @_;
    $self->_set_colors('reset');
    return unless $self->_should_display( $parser, $result );

    if ( $result->is_test ) {
        if ( !$result->is_ok ) {    # even if it's TODO
            $self->_set_colors('red');
        }
        elsif ( $result->has_skip ) {
            $self->_set_colors( 'white', 'on_blue' );

        }
        elsif ( $result->has_todo ) {
            $self->_set_colors('white');
        }
    }
    $self->output( $result->as_string );
    $self->_set_colors('reset');
    $self->output("\n");
}

1;
