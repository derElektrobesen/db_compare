use 5.008009;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.

open my $cpuinfo, '<', '/proc/cpuinfo' or die "Can't find cpuinfo file!";
my $cpu_count = 0;
while (<$cpuinfo>) {
    $cpu_count++ if /^processor/i;
}
$cpu_count++;

WriteMakefile(
    NAME              => 'DataManip',
    VERSION_FROM      => 'lib/DataManip.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/DataManip.pm', # retrieve abstract from module
       AUTHOR         => 'Pavel Berezhnoy <pberejnoy2005@gmail.com>') : ()),
    LIBS              => ['-lpthread'], # e.g., '-lm'
    DEFINE            => "-DLOG_LEVEL=5 -DMAX_THREADS=$cpu_count",
    INC               => '', # e.g., '-I/usr/include/other'
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
