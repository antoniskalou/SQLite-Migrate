# NAME

SQLite::Migration

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
programmable interface to do migrations.

Unlike App::Sqitch, this util doesn't store its migrations in a specific table,
but instead uses `pragma user_version` to keep track of which migration number
we are at. Migrations start at 0 (0 being equal to no migrations applied) and
each migration increments the `user_version`.

Assumes migrations are stored in the "sql" directory in the project root.

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
