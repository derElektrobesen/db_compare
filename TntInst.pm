#!/usr/bin/perl

package TntInst; {
    use base BaseInst;

    use strict;
    use warnings;

    sub new {
        my $class = shift;

        my $self = BaseInst::new($class);
        return $self;
    }
}

1;
