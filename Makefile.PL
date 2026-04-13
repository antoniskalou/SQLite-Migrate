use ExtUtils::MakeMaker;

WriteMakefile(
  NAME => 'SQLite::Migrate',
  AUTHOR => [
    'Antonis Kalou <kalouantonis@protonmail.com>',
  ],
  LICENSE => 'perl_5',
  META_MERGE => {
    'meta-spec' => { version => 2 },
    resources => {
      repository => {
        type => 'git',
        url => 'https://github.com/antoniskalou/SQLite-Migrate.git',
        web => 'https://github.com/antoniskalou/SQLite-Migrate',
      },
      bugtracker => {
        web => 'https://github.com/antoniskalou/SQLite-Migrate/issues',
      },
    },
  },
  VERSION_FROM => 'lib/SQLite/Migrate.pm',
  EXE_FILES => ['bin/sqlite-migrate'],
  MIN_PERL_VERSION => '5.26.0',
  PREREQ_PM => {
    'DBI' => '1.60',
    'DBD::SQLite' => '1.68',
    'Path::Tiny' => '0.144',
    'Getopt::Long' => 0,
    'Pod::Usage' => 0,
  },
  TEST_REQUIRES => {
    'Test::More' => 0,
    'Test::Exception' => 0,
  },
)
