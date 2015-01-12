#!/usr/bin/perl

use strict;
use warnings;

use POSIX;

use List::Util qw( shuffle );
use Getopt::Std;

use BaseInst;
use TntInst;
use MemcachedInst;

use lib 'DataManip/blib/lib';
use lib 'DataManip/blib/arch';
use DataManip;

$SIG{CHLD} = "IGNORE";

my %params = (
    n_processes     => 1,
    sleep_time      => 2, # in seconds
    logs_dir        => 'logs',

    inst_name       => '',
    tuple_size      => 1,

    blocks_count    => 1000,
);

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
    return DataManip::read_block($data_size);
}

sub generate_tuple {
    my $item_size = shift;
    my $tuple_size = shift;

    my @t;
    for (1 .. $tuple_size) {
        push @t, gen_data($item_size);
    }

    return \@t;
}

sub child_work {
    my $instance = shift;

    change_user;
    open my $log_fd, '>', "$params{logs_dir}/$params{inst_name}_$params{tuple_size}_slave.log";

    select $log_fd;
    $| = 1;
    select STDOUT;

    my $iterations_count = 100_000;
    my $first_iter = 100;
    my $iters_per_item = 10;
    my $tuple_size = $params{tuple_size};

    my @polynom_members = map {
        int((20 * $_ * $_ - $_) * log($_ / 100) / 3_000 / $tuple_size + 1)
    } $first_iter .. $iterations_count;

    my $total = 0;
    for my $iter (0 .. $iterations_count - $first_iter) {
        my $item_size = $polynom_members[$iter];
        for my $sub_iter (0 .. $iters_per_item) {
            my $t = generate_tuple($item_size, $tuple_size);
            $instance->insert(name => $tuple_size * $iter * $sub_iter, tuple => $t);
            $total += $item_size * $iter;
            undef $t;
        }

        my $time = scalar time;
        print $log_fd "$time:$tuple_size:$item_size:" . $instance->memusage() . ":$total\n";
    }
    warn "Child work complete!";
}

sub master_work {
    my %children = map { $_->{pid} => $_->{name} } @{$_[0]};
    my $inst = $_[1];

    my $fname = "$params{logs_dir}/$params{inst_name}_$params{tuple_size}_master.log";
    open my $out_file, '>', $fname or die "Can't open $fname: $!\n";
    chown get_user, $fname;

    select $out_file;
    $| = 1;
    select STDOUT;

    my $first_step = 1;
    my $content;
    my $name = $inst->name();

    do {
        sleep($params{sleep_time}) unless $first_step;
        $first_step = 0;

        while (my ($pid, $name) = each %children) {
            unless (kill 0 => $pid) {
                # child process died
                delete $children{$pid};
            }
        }

        if (%children) {
            my $time = scalar time;
            my $pid = $inst->pid();

            unless (kill 0 => $pid) {
                print $out_file "$time:$name:died\n";
                last;
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
    } while (scalar %children && $inst);
}

sub create_instance {
    my $name = shift;
    if ($name eq 'memc') {
        return MemcachedInst->new;
    } else {
        return BaseInst->new;
    }
}

sub main {
    my $instance;
    my @processes;
    my @children;

    unless (-d $params{logs_dir}) {
        die "can't mkdir: $!\n" unless mkdir $params{logs_dir};
        chown get_user, $params{logs_dir};
    }

    my $created_instance = create_instance $params{inst_name};
    die "Can't create instance " . $created_instance->name() . " (not running)\n"
        unless kill 'SIGZERO', $created_instance->pid();

    my $pid;
    for (1 .. $params{n_processes}) {
        $pid = fork;
        unless ($pid) {
            $instance = $created_instance;
            last;
        }

        push @children, { pid => $pid, name => $created_instance->name() };

        print "Process $pid (" . $created_instance->name() . ") started...\n";
    }

    if ($pid) {
        # master process
        master_work \@children, $created_instance;
    } else {
        # child process
        $instance->create_conn();
        DataManip::start($params{blocks_count});
        child_work $instance;
        DataManip::stop();
    }
}

my %opts;
getopts('hn:l:', \%opts);

my @available_instances = qw( memc );

if (defined $opts{h}) {
    print "usage: $0 [-h] [-n name] [-l tuple length]\n" .
        "Available instances names: " . (join ', ', @available_instances) . "\n";
    exit 0;
}

$params{inst_name} = $opts{n} if defined $opts{n};
$params{tuple_size} = $opts{l} if defined $opts{l};

my $inst_found = 0;
for (@available_instances) {
    if ($_ eq $params{inst_name}) {
        $inst_found = 1;
        last;
    }
}

die "Unknown instance found: '$params{inst_name}'.\nAvailable instances names: " .
    (join ', ', @available_instances) . "\n" unless $inst_found;

my $login = (getpwuid $>);
die "must run as root" if $login ne 'root';

main;

1;
