#!/usr/bin/perl

use strict;
use warnings;

use Time::HiRes qw();

my %params = (
    n_processes     => 5,
    sleep_time      => 0.5, # in seconds
);

sub child_work {
    my $instance = shift;
}

sub master_work {
    my %processes = map { $_{pid} => $_{name} } @{$_[0]}; # reference on array of references on hashes

    open my $out_file, '>', "results_$$.log";

    my $first_step = 1;
    do {
        Time::HiRes::sleep($params{sleep_time}) unless $first_step;
        $first_step = 0;

        my @processes_list_copy = keys %processes;
        for (sort @processes_list_copy) {
            unless (kill 0 => $_) {
                # child process died
                delete $processes{$_};
            } else {
                my $time = localtime;
                my $content;

                {
                    local $/ = undef; # read all file at ones
                    open my $stat_file, '<', "/proc/$_/stat";
                    $content = <$stat_file>;
                    close $stat_file;
                }

                chomp $content;
                print $out_file "$time $processes{$_} $content\n";
            }
        }
    } while (%processes);
}

sub create_instances {
    return ();
}

sub main {
    my $instance;
    my @processes;

    my $pid;
    for my $i (create_instances) {
        for (0 .. $params{n_processes}) {
            $pid = fork;
            unless ($pid) {
                $instance = $i;
                last;
            }

            push @processes, { pid => $pid, name => $i->name };
        }
        last if defined $instance;
    }

    if ($pid) {
        # master process
        master_work \@processes;
    } else {
        # child process
        child_work $instance;
    }
}

main;
