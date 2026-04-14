package SQLite::Migrate::CLI;

use v5.26;
use strict;
use warnings;

use DBI qw();
use DBD::SQLite::Constants qw(:dbd_sqlite_string_mode SQLITE_DETERMINISTIC);
use SQLite::Migrate qw();
use Path::Tiny qw(path);

use Getopt::Long qw(GetOptionsFromArray);
use Pod::Usage qw(pod2usage);

my sub usage {
  my ($exit) = @_;
  pod2usage(
    -verbose => 1,
    -exitval => 'NOEXIT',
    -output => \*STDERR,
  );
  $exit;
}

my sub help {
  pod2usage(-verbose => 2, exitval => 'NOEXIT');
  0;
}

my sub error {
  my ($msg, $exit) = @_;
  say STDERR $msg;
  $exit //= 1;
  $exit;
}

sub run {
  my (@argv) = @_;

  my $help;
  my $migration_dir;

  GetOptionsFromArray(
    \@argv,
    'help|h' => \$help,
    'dir=s' => \$migration_dir,
  ) or return usage(2);

  return help() if $help;

  if (defined $migration_dir) {
    $SQLite::Migrate::MIGRATION_DIR = $migration_dir;
  }

  my $command = shift @argv or return usage(1);
  my $db_path = shift @argv or return usage(1);

  my $path = path($db_path);
  # create parent dir if needed
  $path->parent->mkdir unless $path->parent->exists;

  my $dbi = "dbi:SQLite:$path";
  my $dbh = DBI->connect($dbi, '', '', {
    RaiseError => 1,
    # auto-commit always on as per documentation recommendation
    AutoCommit => 1,
    # strictly enforce use of UTF-8
    sqlite_string_mode => DBD_SQLITE_STRING_MODE_UNICODE_STRICT,
    # dont allow features that might corrupt the DB
    sqlite_defensive => 1,
  }) or return error("failed to connect to database '$dbi': $DBI::errstr");

  my %command_to_sub = (
    deploy => \&SQLite::Migrate::migrate,
    rollback => \&SQLite::Migrate::rollback,
  );

  my $sub = $command_to_sub{$command}
    or return error("unknown command: $command", 2);

  eval {
    $sub->($dbh, @argv);
  };
  return $@ ? error($@) : 0;
}

1;
