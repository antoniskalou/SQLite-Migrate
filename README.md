# NAME

SQLite::Migration - Lightweight migration tool/library for SQLite

# SYNOPSIS

    use SQLite::Migration qw(migrate rollback);

    my $dbh = connect_to_database();
    # migrate to latest changes
    migrate($dbh);
    # rollback to migration 2
    rollback($dbh, 2);
    # rollback all the way
    rollback($dbh);

# DESCRIPTION

Utilities for migrating a SQLite database forward and backwards. Its a
lightweight alternative to tools like [App::Sqitch](https://metacpan.org/pod/App%3A%3ASqitch), allowing a simple
programmable interface to do migrations, that also provides a CLI for
convenience.

Unlike App::Sqitch, this util doesn't store its migrations in a specific table,
but instead uses `pragma user_version` to keep track of which migration number
we are at. Migrations start at 0 (0 being equal to no migrations applied) and
each migration increments the `user_version`.

By default assumes migrations are stored in the "sql" directory in the
project root.

# COMMAND LINE INTERFACE

For documentation regarding the command line interface see [sqlite-migrate](https://metacpan.org/pod/sqlite-migrate).

# MIGRATIONS

Migrations are assumed to be stored in the "sql" directory of your project's
root. Each migration has a relevant `.up.sql` (upwards migration) and an
optional `.down.sql` (downwards migration) associated with it.

Migrations are run in order of their filename, so a migration called `000_initial`
will run before `001_second_migration`.

For example:

    # sql/000_initial.up.sql

    create table my_table(
      id integer primary key autoincrement,
      stuff text not null
    );

    # sql/000_initial.down.sql

    drop table my_table;

# NOTES

This migration tool is rather simple, it will not protect you from corrupting
your DB. If a migration is partially applied, as in it applies some operations,
but fails before it can complete, then the database will be left in a corrupted
state.

# FUNCTIONS

## migrate

    my $migrated_to = migrate($dbh);
    # if we have 2 migrations, version is 2
    say "Migrated to version: $migrated_to";

Migrate the database to the latest migration, skipping ones that are already
applied.

Returns the latest migration number that was applied.

## rollback

    # migrate back to version 1
    my $rolled_back_to = rollback($dbh, 1);
    say $rolled_back_to; # 1
    # rollback all migrations
    rollback($dbh);

Rollback migrations completely or if provided a number, rollback to the given
version.

Returns the latest migration number that was rolled back to.

## version

    my $version = version($dbh);

Return the current version (defined by `user_version`) of the database.

This value corresponds to the number of migrations that have been applied.
A value of `0` means no migrations have been applied yet.

## status

    my $status = status($dbh);

Returns a hashref describing the current migration state of the database.

The returned hashref has the following structure:

    {
      version => $int,
      applied => \@applied,
      pending => \@pending,
    }

- version

    Same as the result of calling ["version"](#version).

- applied

    An arrayref of migrations that have already been applied, in the order
    they were executed.

    If `version` is `0`, this will be an empty array.

- pending

    An arrayref of migrations that have not yet been applied, in execution order.

    If all migrations have been applied, this will be an empty array.

The `applied` and `pending` arrays are derived from the full list of available
migrations, split at the current version boundary.
