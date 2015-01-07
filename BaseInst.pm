#!/usr/bin/perl

package BaseInst; {
    use strict;
    use warnings;

    use Carp;
    $Carp::CarpLevel = 2;

    use Devel::Size qw( total_size );

    sub new {
        my $class = shift;

        my $self = {
            name => "$class",
        };

        bless $self, $class;

        return $self;
    }

    sub __u_m {
        my $self = shift;
        my $name = shift;

        return "Method '$name' is not implemented in " . $self->{name};
    }

    sub name {
        my $self = shift;
        return $self->{name};
    }

    sub create_conn {
        my $self = shift;
        carp $self->__u_m('create_conn');
    }

    sub pid {
        my $self = shift;
        local $Carp::CarpLevel = 1;
        carp $self->__u_m('pid');
    }

    sub insert {
        my $self = shift;
        carp $self->__u_m('insert');
    }

    sub select {
        my $self = shift;
        carp $self->__u_m('select');
    }

    sub delete {
        my $self = shift;
        carp $self->__u_m('delete');
    }

    sub memusage {
        my $self = shift;
        carp $self->__u_m('memusage');
    }
}

1;
