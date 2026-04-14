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
use Term::ANSIColor qw(colored);

my $VERBOSE = 0;
my $USE_COLOR = -t STDOUT;

my sub color {
  my ($text, $style) = @_;
  $USE_COLOR ? colored($text, $style) : $text;
}

my sub info { say color(shift, 'blue') }
my sub success { say color(shift, 'green') }
my sub fail {
  my ($text) = @_;
  my $output = -t STDERR ? colored($text, 'red') : $text;
  say STDERR $output;
}

my $FANCY_LOGGER = sub {
  my (%event) = @_;
  my $type = $event{type};

  if ($type eq 'skip') {
    say color("[SKIP]", 'yellow')
      . " $event{file} "
      . color("(already applied)", 'faint');
  } elsif ($type eq 'apply') {
    my $dir = uc($event{direction});
    my $color = $dir eq 'UP' ? 'green'
              : $dir eq 'DOWN' ? 'red'
              : 'faint';

    say color("[$dir]", $color)
      . " $event{file} "
      . color("→ user_version=$event{version}", 'cyan');
  } elsif ($type eq 'done') {
    say color('[DONE]', 'blue')
      . ' user_version='
      . color($event{version}, 'bold green');
  } elsif ($type eq 'sql') {
    say color($event{sql}, 'faint') if $VERBOSE;
  }
};

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
  fail $msg;
  $exit //= 1;
  $exit;
}

my sub connect_db {
  my ($db_path) = @_;

  return (undef, usage(1)) unless defined $db_path;
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
  });

  defined $dbh
    ? ($dbh, undef)
    : (undef, error("failed to connect to database '$dbi': $DBI::errstr"));
}

my sub cmd_init {
  my $sql = <<SQL;
begin;

-- code goes here!

commit;
SQL
  
  my $dir = path($SQLite::Migrate::MIGRATION_DIR);
  $dir->mkdir;

  my $up = $dir->child('000_init.up.sql');
  my $down = $dir->child('000_init.down.sql');

  $up->spew_utf8($sql) unless $up->exists;
  $down->spew_utf8($sql) unless $down->exists;
  success "Initialized migration directory at ${\$dir->absolute}";
  0;
}

my sub cmd_status {
  my ($args) = @_;
  my ($dbh, $exit) = connect_db($args->{db_path});
  return $exit if defined $exit;

  my $status = SQLite::Migrate::status($dbh);
  my $version = $status->{version};
  my @applied = @{ $status->{applied} };
  my @pending = @{ $status->{pending} };

  info "Database status";
  say "──────────────";

  printf "%-10s %s\n", "Version:", color($version, 'green');
  printf "%-10s %s\n", "Pending:", color(scalar(@pending), 'yellow');

  say "";
  
  say color("Applied migrations:", 'bold');
  if (@applied) {
    say map { '  ' . color("✓ $_\n", 'green')  } @applied;
  } else {
    say color('  (none)', 'faint');
  }

  say "";

  say color("Pending migrations:", 'bold');
  if (@pending) {
    say map { '  ' . color("• $_\n", 'yellow') } @pending;
  } else {
    say color('  (none)', 'faint');
  }
  
  0;
}

my sub cmd_deploy {
  my ($args) = @_;

  my ($dbh, $exit) = connect_db($args->{db_path});
  return $exit if defined $exit;
  SQLite::Migrate::migrate($dbh, log => $FANCY_LOGGER);
  0;
}

my sub cmd_rollback {
  my ($args) = @_;
  my ($dbh, $exit) = connect_db($args->{db_path});
  return $exit if defined $exit;
  SQLite::Migrate::rollback($dbh, $args->{extra_args}->[0],
    log => $FANCY_LOGGER
  );
  0;
}

my sub parse_args {
  my (@argv) = @_;

  my $help;
  my $migration_dir;

  GetOptionsFromArray(
    \@argv,
    'help|h' => \$help,
    'verbose|v' => \$VERBOSE,
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

  my $exit = eval { $cmd->($args) };
  return $@ ? error($@) : $exit;
}

sub run {
  my (@argv) = @_;

  my ($args, $exit) = parse_args(@argv);
  return $exit if defined $exit;

  my $cmd_exit = eval { run_command($args) };
  $@ ? error($@) : $cmd_exit;
}

1;
