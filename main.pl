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

BEGIN {
    open URANDOM, '<', '/dev/urandom';
}

sub change_user {
    # change current process uid/gid
    my $uid = scalar getpwnam 'nobody';
    my $gid = scalar getpwnam 'nobody';

    setgid $gid;
    setuid $uid;
}

sub rn {
    my $max = shift;
    my $x;
    read URANDOM, $x, 4;
    return int($max * unpack("I", $x) / (2**32));
}

sub gen_int {
    my $compress_factor = shift;
    return $compress_factor ? rn($compress_factor) : 0;
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
    my @fmt = split //, "WaAZbBhHsSlqQiInNvVjJfd";

    return join '', map {
        join '', map { pack "$_*", gen_int($compress_factor) } shuffle @fmt;
    } 0 .. $size;
}

sub generate_tuple {
    my $tuple_size = shift;      # tuple_size
    my $compress_factor = shift; # integer, may be undefined, 0 -- best compress

    my @funcs = ( \&gen_int, \&gen_str, \&gen_bin );

    return map {
        $funcs[rn(scalar @funcs)]->($compress_factor, $tuple_size);
    } 0 .. $tuple_size * scalar @funcs;
}

sub _log {
    printf @_;
}

sub child_work {
    my $instance = shift;

    change_user;

    my $iterations_count = 100000;
    my $tuple_size = 0; # in elements
    my $compress_factor = 0;

    for (0 .. $iterations_count) {
        _log("Compress_factor: %d, size: %d", $compress_factor, $tuple_size);

        for (0 .. $iterations_count) {
            $instance->insert(name => rn(9999999999999999), tuple => [ generate_tuple($tuple_size, $compress_factor) ]);
        }

        $compress_factor += rn($compress_factor + 1000);
        $tuple_size += rn($tuple_size + 10);
    }
}

sub master_work {
    my %children = map { $_->{pid} => $_->{name} } @{$_[0]};
    my %processes = map { $_->{pid} => $_->{name} } @{$_[1]}; # reference on array of references on hashes

    open my $out_file, '>', "results_$$.log";

    my $first_step = 1;
    my $content;
    my $pid;
    my $name;

    do {
        sleep($params{sleep_time}) unless $first_step;
        $first_step = 0;

        use Data::Dumper;
        print Dumper [\%processes, \%children];

        for (my ($pid, $name) = each %children) {
            unless (kill 0 => $pid) {
                # child process died
                delete $children{$pid};
            }
        }

        my $time = localtime;

        for (($pid, $name) = each %processes) {
            unless (kill 0 => $pid) {
                delete $processes{$pid};
                print $out_file "$time $name died\n";
                next;
            }

            {
                local $/ = undef; # read all file at ones
                open my $stat_file, '<', "/proc/$pid/stat";
                $content = <$stat_file>;
                close $stat_file;
            }
            chomp $content;
            print $out_file "$time $name $content\n";
        }
    } while (scalar %children && scalar %processes);
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
    my @children;

    my $pid;
    for my $i (create_instances) {
        for (1 .. $params{n_processes}) {
            $pid = fork;
            unless ($pid) {
                $instance = $i;
                last;
            }

            print "Process $pid started...\n";
            push @children, { pid => $pid, name => $i->name() };
        }

        last if defined $instance;

        push @processes, { pid => $i->pid(), name => $i->name() };
    }

    if ($pid) {
        # master process
        master_work \@children, \@processes;
    } else {
        # child process
        child_work $instance;
    }
}

my $login = (getpwuid $>);
die "must run as root" if $login ne 'root';

main;

1;
