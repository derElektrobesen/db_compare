#!/usr/bin/perl

package BaseInst; {
    use strict;
    use warnings;

    use Carp;

    sub new {
        my $class = shift;

        my $self = {
            name => "$class",
        };

        bless $self, $class;
        srand time;

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
}

1;
