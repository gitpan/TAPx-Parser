#!/usr/bin/perl -wT

use strict;

use lib 'lib';

use Test::More 'no_plan';    # tests => 33;
use TAPx::Harness;
use TAPx::Harness::Color;

foreach my $HARNESS (qw<TAPx::Harness TAPx::Harness::Color>) {
    can_ok $HARNESS, 'new';

    eval { $HARNESS->new( { no_such_key => 1 } ) };
    like $@, qr/\QUnknown arguments to TAPx::Harness::new (no_such_key)/,
      '... and calling it with bad keys should fail';

    foreach my $test_args ( get_arg_sets() ) {
        my %args = %$test_args;
        foreach my $key ( keys %args ) {
            $args{$key} = $args{$key}[0];
        }
        ok my $harness = $HARNESS->new( {%args} ),
          'Calling new() with valid arguments should succeed';
        isa_ok $harness, $HARNESS, '... and the object it returns';

        while ( my ( $property, $test ) = each %$test_args ) {
            my $value = $test->[1];
            can_ok $harness, $property;
            is $harness->$property, $value,
              "... and $property() should return the correct value";
        }
    }
}

sub get_arg_sets {

    # keys are keys to new()
    # values are [ "value to constructor", "value from property()" ]
    return {
        lib     => [ 'lib', '-Ilib' ],
        verbose => [ 1,     1 ],
      },
      { lib => [ [ 'lib', 't' ], '-Ilib -It' ],  # silly, but it works
        verbose => [ 0, 0 ],
      };
}
