use 5.008009;
use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME              => 'DataManip',
    VERSION_FROM      => 'lib/DataManip.pm', # finds $VERSION
    PREREQ_PM         => {}, # e.g., Module::Name => 1.1
    ($] >= 5.005 ?     ## Add these new keywords supported since 5.005
      (ABSTRACT_FROM  => 'lib/DataManip.pm', # retrieve abstract from module
       AUTHOR         => 'Pavel Berezhnoy <pberejnoy2005@gmail.com>') : ()),
    LIBS              => ['-lpthread'], # e.g., '-lm'
    DEFINE            => '-DLOG_LEVEL=5',
    INC               => '', # e.g., '-I/usr/include/other'
    # OBJECT            => '$(O_FILES)', # link all the C files too
);
