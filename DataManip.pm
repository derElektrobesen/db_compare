#!/usr/bin/perl

package DataManip; {
    use strict;
    use warnings;

    use threads;
    use threads::shared;

    use Time::HiRes qw( usleep );

    my $block_size :shared = 10 * 1024 * 1024; # in bytes
    my @data :shared;
    my $can_stop :shared = 0;
    my $max_arr_size = 50;
    my @thr;

    sub write {
        my $cmd = shift;
        open URANDOM, '<', "$cmd";
        while (not $can_stop) {
            if (scalar @data >= $max_arr_size) {
                usleep 10000;
                next;
            }

            my $block :shared;
            CORE::read URANDOM, $block, $block_size;

            my $p :shared = shared_clone({ d => \$block, s => $block_size });
            warn "$block_size bytes read via $cmd (arr len: " . (scalar(@data) + 1) .")\n";

            {
                lock @data;
                push @data, $p;
            }
        }
    }

    sub reprocess {
        while (not $can_stop) {
            if (not scalar @data or scalar @data >= $max_arr_size) {
                usleep 10000;
                next;
            }

            my $i;
            {
                lock @data;
                $i = $data[int rand scalar @data];
            }

            my $ppp = int rand 255;

            my $r = '';
            for (unpack 'i*', ${$i->{d}}) {
                $r .= int($_) ^ int($ppp);
            }

            my $p :shared = shared_clone({ d => \$r, s => length $r });
            warn "$p->{s} bytes read via xor (arr len: " . (scalar(@data) + 1) .")\n";

            {
                lock @data;
                push @data, $p;
            }
        }
    }

    sub read {
        my $size = shift;
        my $content = '';

        my $required_blocks = int($size / $block_size) + 2;

        while (scalar (@data) < $required_blocks) {
            warn "Waiting block with size $size\n";
            usleep 100000;
        }

        my @to_push;
        my $append = sub {
            my $i = shift;
            if ($size >= $i->{s}) {
                $content .= ${$i->{d}};
                $size -= $i->{s};
                return 1;
            } elsif ($size) {
                $content .= substr ${$i->{d}}, 0, $size, '';
                $i->{s} -= $size;
                $size = 0;
            }
            push @to_push, $i;
            return 0;
        };

        while ($size) {
            my $i;
            {
                lock @data;
                $i = shift @data; # splice for a shared array is unimplmeneted =(
            }
            $append->($i);
        }

        if (@to_push) {
            lock @data;
            unshift @data, @to_push;
        }

        return \$content;
    }

    sub start {
        $can_stop = 0;
        srand time;
        push @thr, threads->create(\&write, '/dev/urandom');
        push @thr, threads->create(\&reprocess) for 0 .. 3;
    }

    sub stop {
        $can_stop = 1;
        $_->join() for @thr;
    }
}

1;
