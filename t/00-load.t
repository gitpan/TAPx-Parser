#!/usr/bin/perl -T

use Test::More tests => 1;

BEGIN {
	use_ok( 'TAPx::Parser' );
}

diag( "Testing TAPx::Parser $TAPx::Parser::VERSION, Perl $], $^X" );
