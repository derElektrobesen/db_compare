#!/usr/bin/perl

package TntInst; {
    use base BaseInst;

    use strict;
    use warnings;

    use MR::Tarantool::Box;

    sub new {
        my $class = shift;

        my $self = BaseInst::new($class);

        $self->{conn} = $self->_create_conn();

        return $self;
    }

    sub _create_conn {
        my $self = shift;
    }
}

1;
