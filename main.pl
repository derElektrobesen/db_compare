#!/usr/bin/perl

use strict;
use warnings;

use POSIX;

use List::Util qw( shuffle );

use TntInst;
use MemcachedInst;

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

sub gen_int {
    my $compress_factor = shift;
    return int(rand) % compress_factor;
}

sub gen_str {
    my ($compress_factor, $size) = @_;
    return join '', map {
        my $data = $_ * gen_int($compress_factor);
        "$data"
    } 0 .. $size;
}

sub gen_bin {
    my ($compress_factor, $size) = @_;
    my @fmt = split //, "cCWaAzbBhHsSlqQiInNvVjJfd";

    return join '', map {
        join '', map { pack "$_*", gen_int($compress_factor) } shuffle @fmt;
    } 0 .. $size;
}

sub generate_tuple {
    my $tuple_size = shift;      # tuple_size
    my $compress_factor = shift; # integer, may be undefined, 0 -- best compress

    my @funcs = ( \&gen_int, \&gen_str, \&gen_bin );

    return \map {
        $funcs[int(rand) % scalar @funcs]->($compress_factor, $tuple_size);
    } 0 .. $tuple_size * scalar @funcs;
}

sub child_work {
    my $instance = shift;

    change_user;


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
    return (
        #TntInst->new,
        MemcachedInst->new,
    );
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

1;
