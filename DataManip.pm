#!/usr/bin/perl

package DataManip; {
    use strict;
    use warnings;

    use threads;
    use threads::shared;

    use Time::HiRes qw( usleep );

    my $block_size :shared = 4096;
    my @data :shared;
    my $can_stop :shared = 0;
    my $thr;

    sub write {
        my $a = shift;
        open URANDOM, '<', '/dev/urandom';
        while (not $can_stop) {
            my $block :shared;
            CORE::read URANDOM, $block, $block_size;

            my $p :shared = shared_clone({ d => \$block, s => $block_size });

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
            usleep 10000;
        }

        my @to_push;
        my $append = sub {
            my $i = shift;
            if ($size >= $i->{s}) {
                $content .= ${$i->{d}};
                $size -= $i->{s};
                return;
            } elsif ($size) {
                $content .= substr ${$i->{d}}, 0, $size, '';
                $i->{s} -= $size;
                $size = 0;
            }
            push @to_push, $i if $i->{s} > $block_size / 20;
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
        $thr = threads->create(\&write);
    }

    sub stop {
        $can_stop = 1;
        $thr->join();
    }
}

1;
