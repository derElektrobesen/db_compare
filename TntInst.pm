#!/usr/bin/perl

package TntInst; {
    use strict;
    use warnings;

    sub new {
        my $class = shift;

        my $self = {
            name => "TntInst",
        };

        bless $self, $class;

        return $self;
    }

    sub name {
        my $self = shift;
        return $self->{name};
    }
}

1;
