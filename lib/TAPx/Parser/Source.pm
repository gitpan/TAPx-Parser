package TAPx::Parser::Source;

use strict;
use vars qw($VERSION);

use IPC::Open3;
use IO::Select;
use IO::Handle;

use constant IS_WIN32 => ( $^O =~ /^(MS)?Win32$/ );
use constant IS_MACOS => ( $^O eq 'MacOS' );
use constant IS_VMS   => ( $^O eq 'VMS' );

use TAPx::Parser::Iterator;

$SIG{CHLD} = sub { wait };

=head1 NAME

TAPx::Parser::Source - Stream output from some source

=head1 VERSION

Version 0.50_05

=cut

$VERSION = '0.50_05';

=head1 DESCRIPTION

Takes a command and hopefully returns a stream from it.

=head1 SYNOPSIS

 use TAPx::Parser::Source;
 my $source = TAPx::Parser::Source->new;
 my $stream = $source->source(['/usr/bin/ruby', 'mytest.rb'])->get_stream;

=head1 METHODS

=head2 Class methods

=head3 C<new>

 my $source = TAPx::Parser::Source->new;

Returns a new C<TAPx::Parser::Source> object.

=cut

sub new {
    my $class = shift;
    _autoflush( \*STDOUT );
    _autoflush( \*STDERR );
    bless { switches => [] }, $class;
}

##############################################################################

=head2 Instance methods

=head3 C<source>

 my $source = $source->source;
 $source->source(['./some_prog some_test_file']);

 # or
 $source->source(['/usr/bin/ruby', 't/ruby_test.rb']);

Getter/setter for the source.  The source should generally consist of an array
reference of strings which, when executed via C<&IPC::Open3::open3>, should
return a filehandle which returns successive rows of TAP.

=cut

sub source {
    my $self = shift;
    return $self->{source} unless @_;
    unless ( 'ARRAY' eq ref $_[0] ) {
        $self->_croak("Argument to &source must be an array reference"); 
    }
    $self->{source} = shift;
    return $self;
}

##############################################################################

=head3 C<get_stream>

 my $stream = $source->get_stream;

Returns a stream of the output generated by executing C<source>.

=cut

sub get_stream {
    my ($self) = @_;
    my @command = $self->_get_command
        or $self->_croak("No command found!");

    # redirecting STDERR to STDOUT seems to keep them in sync
    # but I lose a bit of formatting for some reason
    my $stdout        = IO::Select->new();
    my $stdout_handle = IO::Handle->new();
    $stdout_handle->autoflush(1);
    $stdout->add( \*STDOUT );
    $stdout->add($stdout_handle);

    if ( my $pid = open3( undef, $stdout_handle, undef, @command ) ) {
        my $iter = TAPx::Parser::Iterator->new($stdout_handle);
        $iter->pid($pid);
        return $iter;
    }
    else {
        $self->exit( $? >> 8 );
        $self->error("Could not execute (@command): $!");
        return;
    }
}

sub _get_command { @{ shift->source } }

##############################################################################

=head3 C<error>

 unless ( my $stream = $source->get_stream ) {
     die $source->error;
 }

If a stream cannot be created, this method will return the error.

=cut

sub error {
    my $self = shift;
    return $self->{error} unless @_;
    $self->{error} = shift;
    return $self;
}

##############################################################################

=head3 C<exit>

  my $exit = $source->exit;

Returns the exit status of the process I<if and only if> an error occurs in
opening the file.

=cut

sub exit {
    my $self = shift;
    return $self->{exit} unless @_;
    $self->{exit} = shift;
    return $self;
}

##############################################################################

=head3 C<pid>

  my $pid = $source->pid;

Returns the pid of the command being used to execute the tests.

=cut

sub pid {
    my $self = shift;
    return $self->{pid} unless @_;
    $self->{pid} = shift;
    return $self;
}

# Turns on autoflush for the handle passed
sub _autoflush {
    my $flushed = shift;
    my $old_fh  = select $flushed;
    $| = 1;
    select $old_fh;
}

sub _croak {
    my $self = shift;
    require Carp;
    Carp::croak(@_);
}

1;
