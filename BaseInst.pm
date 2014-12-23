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

    sub pid {
        my $self = shift;
        local $Carp::CarpLevel = 1;
        carp $self->__u_m('pid');
    }

    sub _insert {
        my $self = shift;
        carp $self->__u_m('_insert');
    }

    sub _select {
        my $self = shift;
        carp $self->__u_m('_select');
    }

    sub _delete {
        my $self = shift;
        carp $self->__u_m('_delete');
    }

    sub insert {
        my $self = shift;
        $self->_insert(@_);
        return total_size(\@_);
    }

    sub select {
        my $self = shift;
        $self->_select(@_);
        return 0;
    }

    sub delete {
        my $self = shift;
        $self->_delete(@_);
        return total_size(\@_);
    }
}

1;
