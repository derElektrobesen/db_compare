#!/usr/bin/perl

use strict;
use warnings;

use POSIX;

use TntInst;

$SIG{CHLD} = "IGNORE";

my %params = (
    n_processes     => 5,
    sleep_time      => 1, # in seconds
);

sub change_user {
    # change current process uid/gid
    my $uid = scalar getpwnam 'nobody';
    my $gid = scalar getpwnam 'nobody';

    setgid $gid;
    setuid $uid;
}

sub child_work {
    my $instance = shift;

    change_user;

    sleep 5;
}

sub master_work {
    my %processes = map { $_->{pid} => $_->{name} } @{$_[0]}; # reference on array of references on hashes

    open my $out_file, '>', "results_$$.log";

    my $first_step = 1;
    do {
        sleep($params{sleep_time}) unless $first_step;
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
    return ( TntInst->new );
}

sub main {
    my $instance;
    my @processes;

    my $pid;
    for my $i (create_instances) {
        for (1 .. $params{n_processes}) {
            $pid = fork;
            unless ($pid) {
                $instance = $i;
                last;
            }

            print "Process $pid started...\n";
            push @processes, { pid => $pid, name => $i->name() };
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
