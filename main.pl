#!/usr/bin/perl

use strict;
use warnings;

use POSIX;

use List::Util qw( shuffle );

use TntInst;
use MemcachedInst;

$SIG{CHLD} = "IGNORE";

my %params = (
    n_processes     => 1,
    sleep_time      => 2, # in seconds
    logs_dir        => 'logs',

    inst_name       => '',
    tuple_size      => '',
);

BEGIN {
    open URANDOM, '<', '/dev/urandom';
}

sub get_user {
    my $name = $_[0] || 'nobody';
    my $uid = getpwnam $name;
    my $gid = getgrnam $name;

    return ($uid, $gid);
}

sub change_user {
    # change current process uid/gid
    my ($uid, $gid) = get_user;

    setgid $gid;
    setuid $uid;
}

sub gen_data {
    my $data_size = shift;
    my $data;
    read URANDOM, $data, $data_size;
    return \$data;
}

sub generate_tuple {
    my $item_size = shift;
    my $tuple_size = shift;

    return [ map { ${gen_data($item_size)} } 1 .. $tuple_size ];
}

sub child_work {
    my $instance = shift;

    change_user;
    open my $log_fd, '>', "$params{logs_dir}/proc_" . (lc $instance->name()) . "_$$.log";

    select $log_fd;
    $| = 1;
    select STDOUT;

    my $iterations_count = 100_000;
    my $first_iter = 100;
    my $items_count = 100;
    my $iters_per_item = 1000;

    my @polynom_members = map { int((20 * $_ * $_ - $_) * log($_ / 100) / 3_000) } $first_iter .. $iterations_count;

    for my $tuple_size (1 .. $items_count) {
        my $item_size = 1;

        for my $iter ($first_iter .. $iterations_count) {
            for my $sub_iter (0 .. $iters_per_item) {
                $instance->insert(name => $tuple_size * $iter * $sub_iter,
                                  tuple => generate_tuple($item_size, $tuple_size));
            }
            $item_size = $polynom_members[$iter] / $tuple_size;

            my $time = scalar time;
            print $log_fd "$time:$tuple_size:$item_size:" . $instance->memusage() .
                          ":" . ($iter * $iters_per_item * $tuple_size) . "\n";
        }
    }
}

sub master_work {
    my %children = map { $_->{pid} => $_->{name} } @{$_[0]};
    my %processes = map { $_->name() => $_ } @{$_[1]};

    my $fname = "$params{logs_dir}/results_$$.log";
    open my $out_file, '>', $fname or die "Can't open $fname: $!\n";
    chown get_user, $fname;

    select $out_file;
    $| = 1;
    select STDOUT;

    my $first_step = 1;
    my $content;
    my $pid;
    my $name;

    do {
        sleep($params{sleep_time}) unless $first_step;
        $first_step = 0;

        while (my ($pid, $name) = each %children) {
            unless (kill 0 => $pid) {
                # child process died
                delete $children{$pid};
                delete $processes{$name} unless scalar grep { $name eq $_ } keys %children;
            }
        }

        my $time = scalar time;

        while (($name, $inst) = each %processes) {
            my $pid = $inst->pid();

            unless (kill 0 => $pid) {
                delete $processes{$name};
                print $out_file "$time:$name:died\n";
                my $a;
                for (($a, $_) = each %children) {
                    delete $children{$a} if $children{$a} eq $name;
                }
                next;
            }

            {
                local $/ = undef; # read all file at ones
                open my $stat_file, '<', "/proc/$pid/stat";
                $content = <$stat_file>;
                close $stat_file;
            }

            $content =~ /^(?:\S+ ){22}(\S+).*/; # virtual mem
            print $out_file "$time:$name:$1\n";
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

    unless (-d $params{logs_dir}) {
        die "can't mkdir: $!\n" unless mkdir $params{logs_dir};
        chown get_user, $params{logs_dir};
    }

    my @created_instances = create_instances;
    for (@created_instances) {
        die "Can't create instance " . $_->name() . " (not running)\n"
            unless kill 'SIGZERO', $_->pid();
    }

    my $pid;
    for my $i (@created_instances) {
        for (1 .. $params{n_processes}) {
            $pid = fork;
            unless ($pid) {
                $instance = $i;
                last;
            }

            push @children, { pid => $pid, name => $i->name() };

            print "Process $pid (" . $i->name() . ") started...\n";
        }

        last if defined $instance;

        push @processes, $i;
    }

    if ($pid) {
        # master process
        master_work \@children, \@processes;
    } else {
        # child process
        $instance->create_conn();
        child_work $instance;
    }
}

my $login = (getpwuid $>);
die "must run as root" if $login ne 'root';

main;

1;
