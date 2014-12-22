#!/usr/bin/perl

package MemcachedInst; {
    use base BaseInst;

    use strict;
    use warnings;

    use Cache::Memcached;

    sub new {
        my $class = shift;

        my $self = BaseInst::new($self);

        $self->_create_conn();
        return $self;
    }

    sub _create_conn {
        my $self = shift;

        my $memd = Cache::Memcached->new({
            servers             => [ '127.0.0.1:11211' ],
            debug               => 1,
            compress_threshold  => 10_000,  # data larger then 10kb will be compressed
        });

        $self->{conn} = $memd;
    }

    sub insert {
        my $self = shift;
        my %args = (
            name    => undef,   # String expected
            tuple   => undef,   # array reference expected
            @_,
        );

        $self->{conn}->set($args{name}, { complex => $args{tuple} });
    }

    sub select {
        my $self = shift;
        my $name = shift;

        $self->{conn}->get($name);
    }

    sub delete {
        my $self = shift;
        my $key = shift;

        $self->{conn}->delete($name);
    }
}

1;