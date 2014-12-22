#!/usr/bin/perl

use strict;
use warnings;

my %params = (
    n_processes     => 5,
);

sub child_work {
    my $instance = shift;
}

sub create_instances {
    return ();
}

sub main {
    my $instance;
    for my $i (create_instances) {
        for (0 .. $params{n_processes}) {
            unless (fork) {
                $instance = $i;
                last;
            }
        }
        last if defined $instance;
    }

    if ($child) {
        # master process
        while (wait > 0) {}
    } else {
        # child process
        child_work $instance;
    }
}

main;
