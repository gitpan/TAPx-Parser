package TAPx::Parser::Builder;

##############################################################################

=head1 NAME

TAPx::Parser::Builder - Make Test::Builder redirect STDERR to STDOUT

=head1 VERSION

Version 0.50_01

=cut

$VERSION = '0.50_01';

=head2 DESCRIPTION

This is only for internal use when running test scripts written in Perl.  Do
not use this code.

=cut

use strict;

{
    local $^W;

    my $overridden;

    sub Test::Builder::failure_output {
        my ( $self, $fh ) = @_;

        if ( defined $fh ) {
            $self->{Fail_FH} = $self->_new_fh($fh);
            $overridden = 1;
        }
        return $overridden ? $self->{Fail_FH} : $self->output;
    }
}

1;
