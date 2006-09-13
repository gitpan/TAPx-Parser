#!/usr/bin/perl
use warnings;
use strict;

use Test::More tests => 46;
use TAPx::Parser;

use TAPx::Parser::Iterator;
use TAPx::Parser::Streamed;

sub array_ref_from {
    my $string = shift;
    my @lines = split /\n/ => $string;
    return \@lines;
}

# we slurp __DATA__ and then reset it so we don't have to duplicate out TAP
my $offset = tell DATA;
my $tap = do { local $/; <DATA> };
seek DATA, $offset, 0;

foreach my $source ( array_ref_from($tap), \*DATA ) {
    ok my $iter = TAPx::Parser::Iterator->new($source),
      'We should be able to create a new iterator';
    isa_ok $iter, 'TAPx::Parser::Iterator', '... and the object it returns';
    my $subclass =
        'ARRAY' eq ref $source
      ? 'TAPx::Parser::Iterator::ARRAY'
      : 'TAPx::Parser::Iterator::FH';
    isa_ok $iter, , $subclass, '... and the object it returns';

    can_ok $iter, 'first';
    can_ok $iter, 'last';

    foreach my $method (qw<first last>) {
        ok !$iter->$method,
          "... $method() should not return true for a new iter";
    }

    can_ok $iter, 'next';
    is $iter->next, 'one', 'next() should return the first result';
    ok $iter->first, '... and first() should now return true';
    ok !$iter->last, '... and last() should now return false';

    is $iter->next, 'two', 'next() should return the second result';
    ok !$iter->first, '... and first() should now return false';
    ok !$iter->last,  '... and last() should now return false';

    is $iter->next, '', 'next() should return the third result';
    ok !$iter->first, '... and first() should now return false';
    ok !$iter->last,  '... and last() should now return false';

    is $iter->next, 'three', 'next() should return the fourth result';
    ok !$iter->first, '... and first() should now return false';
    ok $iter->last, '... and last() should now return true';

    ok !defined $iter->next, 'next() should return undef after it is empty';
    ok !$iter->first, '... and first() should now return false';
    ok $iter->last, '... and last() should now return true';
}

__DATA__
one
two

three
