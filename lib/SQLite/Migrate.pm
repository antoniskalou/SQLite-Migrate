package SQLite::Migrate;

use v5.26;
use strict;
use warnings;
use utf8;
use open qw(:std :encoding(UTF-8));
use DBI;
use Path::Tiny qw(path);
use Carp qw(croak);
use Exporter 'import';

our $VERSION = '0.1.0';

our @EXPORT_OK = qw(migrate rollback version status);

=head1 NAME

SQLite::Migration - Lightweight migration tool/library for SQLite

=head1 SYNOPSIS

  use SQLite::Migration qw(migrate rollback);

  my $dbh = connect_to_database();
  # migrate to latest changes
  migrate($dbh);
  # rollback to migration 2
  rollback($dbh, 2);
  # rollback all the way
  rollback($dbh);

=head1 DESCRIPTION

Utilities for migrating a SQLite database forward and backwards. Its a
lightweight alternative to tools like L<App::Sqitch>, allowing a simple
programmable interface to do migrations.

Unlike App::Sqitch, this util doesn't store its migrations in a specific table,
but instead uses C<pragma user_version> to keep track of which migration number
we are at. Migrations start at 0 (0 being equal to no migrations applied) and
each migration increments the C<user_version>.

Assumes migrations are stored in the "sql" directory in the project root.

=head1 MIGRATIONS

Migrations are assumed to be stored in the "sql" directory of your project's
root. Each migration has a relevant C<.up.sql> (upwards migration) and an
optional C<.down.sql> (downwards migration) associated with it.

Migrations are run in order of their filename, so a migration called C<000_initial>
will run before C<001_second_migration>.

For example:

  # sql/000_initial.up.sql

  create table my_table(
    id integer primary key autoincrement,
    stuff text not null
  );

  # sql/000_initial.down.sql

  drop table my_table;

=head1 NOTES

This migration tool is rather simple, it will not protect you from corrupting
your DB. If a migration is partially applied, as in it applies some operations,
but fails before it can complete, then the database will be left in a corrupted
state.

=head1 FUNCTIONS

=cut

# only really changed by the user of tests, though should consider another
# way of doing this
our $MIGRATION_DIR = 'sql';

my sub migrations {
  my ($direction) = @_;
  sort { $a->basename cmp $b->basename }
  grep { $_ =~ /$direction\.sql$/ }
    path($MIGRATION_DIR)->children;
}

my sub user_version {
  my ($dbh, $set) = @_;
  $dbh->do("pragma user_version=$set") if defined $set;
  my ($version) = $dbh->selectrow_array('pragma user_version');
  $version + 0; # force numeric
}

my sub run_sql_file {
  my ($dbh, $file) = @_;
  my $sql = $file->slurp_utf8;
  say $sql;
  $dbh->do($sql) or croak "Failed to run $file: " . $dbh->errstr;
}

my sub apply_migrations {
  my ($dbh, $direction, $target) = @_;
  local $dbh->{sqlite_allow_multiple_statements} = 1;

  my $version = user_version($dbh);
  my @files = migrations($direction);

  # was using builtin::indexed, but it caused a segfault when used with reverse
  my @pairs = map { [ $_, $files[$_] ] } 0..$#files;
  @pairs = reverse @pairs if $direction eq 'down';

  for my $pair (@pairs) {
    my ($i, $file) = @$pair;
    my $name = $file->basename;

    if (($direction eq 'up' && $i < $version) ||
        ($direction eq 'down' && $i >= $version)) {
      say "[SKIP] $name (already applied)";
      next;
    }

    $version += $direction eq 'up' ? 1 : -1;
    say sprintf("[%s] %s → user_version=%d",
                uc($direction), $name, $version);

    run_sql_file($dbh, $file);
    user_version($dbh, $version);

    last if defined $target && $version == $target;
  }

  my $final = user_version($dbh);
  say "[DONE] user_version=$final";
  $final;
}

=head2 migrate

  my $migrated_to = migrate($dbh);
  # if we have 2 migrations, version is 2
  say "Migrated to version: $migrated_to";

Migrate the database to the latest migration, skipping ones that are already
applied.

Returns the latest migration number that was applied.

=cut

sub migrate {
  my ($dbh) = @_;
  apply_migrations($dbh, 'up')
}

=head2 rollback

  # migrate back to version 1
  my $rolled_back_to = rollback($dbh, 1);
  say $rolled_back_to; # 1
  # rollback all migrations
  rollback($dbh);

Rollback migrations completely or if provided a number, rollback to the given
version.

Returns the latest migration number that was rolled back to.

=cut

sub rollback {
  my ($dbh, $target) = @_;
  $target //= 0;
  apply_migrations($dbh, 'down', $target)
}

=head2 version

  my $version = version($dbh);

Return the current version (defined by C<user_version>) of the database.

This value corresponds to the number of migrations that have been applied.
A value of C<0> means no migrations have been applied yet.

=cut

sub version {
  my ($dbh) = @_;
  user_version($dbh);
}

=head2 status

  my $status = status($dbh);

Returns a hashref describing the current migration state of the database.

The returned hashref has the following structure:

  {
    version => $int,
    applied => \@applied,
    pending => \@pending,
  }

=over 4

=item * version

Same as the result of calling L</version>.

=item * applied

An arrayref of migrations that have already been applied, in the order
they were executed.

If C<version> is C<0>, this will be an empty array.

=item * pending

An arrayref of migrations that have not yet been applied, in execution order.

If all migrations have been applied, this will be an empty array.

=back

The C<applied> and C<pending> arrays are derived from the full list of available
migrations, split at the current version boundary.

=cut

sub status {
  my ($dbh) = @_;

  my $version = user_version($dbh);
  my @migrations = migrations('up');

  my @applied = grep { $_ < $version } 0..$#migrations;
  my @pending = grep { $_ >= $version } 0..$#migrations;

  @applied = @migrations[@applied];
  @pending = @migrations[@pending];

  {
    version => $version,
    pending => \@pending,
    applied => \@applied,
  };
}

1;
