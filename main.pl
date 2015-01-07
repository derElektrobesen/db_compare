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

sub child_work {
    my $instance = shift;

    change_user;
    open my $log_fd, '>', "$params{logs_dir}/proc_$$.log";

    my $iterations_count = 100000;
    my $tuple_size = 0; # in elements
    my $compress_factor = 0;

    for (0 .. $iterations_count) {
        warn scalar localtime() . " Compress_factor: $compress_factor, size: $tuple_size";

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

    my $fname = "$params{logs_dir}/results_$$.log";
    open my $out_file, '>', $fname;
    chown get_user, $fname;

    my $first_step = 1;
    my $content;
    my $pid;
    my $name;

    open my $shit, '>', '/dev/null';

    use Data::Dumper;
    do {
        sleep($params{sleep_time}) unless $first_step;
        $first_step = 0;

        print $shit Dumper [\%processes, \%children];

        for (my ($pid, $name) = each %children) {
            unless (kill 0 => $pid) {
                # child process died
                delete $children{$pid};
                my $a;
                for (($a, $_) = each %processes) {
                    delete $processes{$a} if $children{$pid} eq $processes{$a};
                }
            }
        }

        my $time = localtime;

        for (($pid, $name) = each %processes) {
            unless (kill 0 => $pid) {
                delete $processes{$pid};
                print $out_file "$time $name died\n";
                my $a;
                for (($a, $_) = each %children) {
                    delete $children{$a} if $children{$a} eq $processes{$pid};
                }
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

        $instance->create_conn();
        push @processes, { pid => $instance->pid(), name => $instance->name() };
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
