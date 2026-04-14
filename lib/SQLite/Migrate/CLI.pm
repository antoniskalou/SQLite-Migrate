package SQLite::Migrate::CLI;

use v5.26;
use strict;
use warnings;
use utf8;

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

my sub connect_db {
  my ($db_path) = @_;

  my $path = path($db_path);
  # create parent dir if needed
  $path->parent->mkdir unless $path->parent->exists;

  my $dbi = "dbi:SQLite:$path";
  DBI->connect($dbi, '', '', {
    RaiseError => 1,
    # auto-commit always on as per documentation recommendation
    AutoCommit => 1,
    # strictly enforce use of UTF-8
    sqlite_string_mode => DBD_SQLITE_STRING_MODE_UNICODE_STRICT,
    # dont allow features that might corrupt the DB
    sqlite_defensive => 1,
  });
}

my sub cmd_init {
  my $sql = <<SQL;
begin;

-- code goes here!

commit;
SQL
  
  my $dir = path($SQLite::Migrate::MIGRATION_DIR);
  $dir->mkdir;
  $dir->child('000_init.up.sql')->spew_utf8($sql);
  $dir->child('000_init.down.sql')->spew_utf8($sql);
  say "Initialized migration directory at ${\$dir->absolute}";
  0;
}

my sub cmd_status {
  my ($args) = @_;
  my $dbh = connect_db($args->{db_path})
    or return error("failed to connect to DB");

  my $status = SQLite::Migrate::status($dbh);
  my $version = $status->{version};
  my @applied = @{ $status->{applied} };
  my @pending = @{ $status->{pending} };

  say "Database status";
  say "---------------";
  say "Version: $version";
  say "Applied: ", scalar(@applied);
  say "Pending: ", scalar(@pending);
  say "";
  
  say "Applied migrations:";
  if (@applied) {
    say "  [✓] $_" for @applied;
  } else {
    say "  (none)";
  }

  say "";

  say "Pending migrations:";
  if (@pending) {
    say "  [ ] $_" for @pending;
  } else {
    say "  (none)";
  }
  
  0;
}

my sub cmd_deploy {
  my ($args) = @_;
  my $dbh = connect_db($args->{db_path})
    or return error("failed to connect to DB");
  SQLite::Migrate::migrate($dbh, @{ $args->{extra_args} });
  0;
}

my sub cmd_rollback {
  my ($args) = @_;
  my $dbh = connect_db($args->{db_path})
    or return error("failed to connect to DB");
  SQLite::Migrate::rollback($dbh, @{ $args->{extra_args} });
  0;
}

my sub parse_args {
  my (@argv) = @_;

  my $help;
  my $migration_dir;

  GetOptionsFromArray(
    \@argv,
    'help|h' => \$help,
    'dir=s' => \$migration_dir,
  ) or return (undef, usage(2));

  return (undef, help()) if $help;

  my $command = shift @argv or return (undef, usage(1));
  # db_path is optional for some commands
  my $db_path = shift @argv;

  return ({
    command => $command,
    db_path => $db_path,
    migration_dir => $migration_dir,
    extra_args => \@argv,
  }, undef);
}

my %COMMANDS = (
  init => \&cmd_init,
  status => \&cmd_status,
  deploy => \&cmd_deploy,
  rollback => \&cmd_rollback,
);

my sub run_command {
  my ($args) = @_;

  if (defined $args->{migration_dir}) {
    $SQLite::Migrate::MIGRATION_DIR = $args->{migration_dir};
  }

  my $cmd = $COMMANDS{$args->{command}}
    or return error("unknown command: ${\$args->{command}}", 2);

  eval { $cmd->($args) };
  return $@ ? error($@) : 0;
}

sub run {
  my (@argv) = @_;

  my ($args, $exit) = parse_args(@argv);
  return $exit if defined $exit;

  my $cmd_exit = eval { run_command($args) };
  $@ ? error($@) : $cmd_exit;
}

1;
