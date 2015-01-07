#!/usr/bin/perl

package BaseInst; {
    use strict;
    use warnings;

    use Carp;
    $Carp::CarpLevel = 2;

    use Devel::Size qw( total_size );

    our $in_restart_mode = 0;

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

    sub get_pid {
        my $self = shift;
        carp $self->__u_m('get_pid');
    }

    sub pid {
        my $self = shift;

        my $i = 0;
        while ($in_restart_mode) {
            $i += 1;
            sleep 10;
            die "Too long restart\n" if $i > 10;
        }

        $self->{_pid} = $self->get_pid() unless defined $self->{_pid};
        return $self->{_pid};
    }

    sub real_restart {
        my $self = shift;
        carp $self->__u_m('real_restart');
    }

    sub restart {
        my $self = shift;
        $in_restart_mode = 1;
        $self->real_restart();
        delete $self->{_pid};
        $in_restart_mode = 0;
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
