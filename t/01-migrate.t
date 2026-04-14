#!perl
use v5.26;
use strict;
use warnings;

use Test::More 'no_plan';
use Test::Exception;

use DBI qw();
use SQLite::Migrate qw(migrate rollback version status);
use Path::Tiny qw(path);
use File::Temp qw(tempdir);

my $noop = sub {};

my $test_dir = path(tempdir(CLEANUP => 1));
diag("Using test directory: $test_dir");

$SQLite::Migrate::MIGRATION_DIR = $test_dir;

my $t1_up_sql = <<SQL;
create table t1 (
  id integer primary key autoincrement,
  data text not null
)
SQL

my $t1_down_sql = <<SQL;
drop table t1;
SQL

# will fail if t2 runs before t1, since the FK wont exist
my $t2_up_sql = <<SQL;
create table t2 (
  id integer primary key autoincrement,
  data text not null,
  t1_id integer not null,
  foreign key (t1_id) references t1(id)
)
SQL

my $t2_down_sql = <<SQL;
drop table t2;
SQL

$test_dir->child('000_t1.up.sql')->spew_utf8($t1_up_sql);
$test_dir->child('000_t1.down.sql')->spew_utf8($t1_down_sql);
$test_dir->child('001_t2.up.sql')->spew_utf8($t2_up_sql);
$test_dir->child('001_t2.down.sql')->spew_utf8($t2_down_sql);

my $dbh = connect_to_db(':memory:');

note('status on empty');
{
  my $status = status($dbh);
  is($status->{version}, 0, '$status->{version} = 0');
  is_deeply($status->{pending}, [
    $test_dir->child('000_t1.up.sql')->stringify,
    $test_dir->child('001_t2.up.sql')->stringify,
  ], 'all migrations are pending');
  is_deeply($status->{applied}, [], 'no migrations applied');
}

note('migrate to latest');
{
  is( migrate($dbh, log => $noop), 2, 'user_version=2' );
  is( version($dbh), 2, 'version($dbh) = 2' );
  lives_ok {
    $dbh->selectrow_array('select 1 from t1');
    $dbh->selectrow_array('select 1 from t2');
  } 'select from both tables should succeed';

  my $status = status($dbh);
  is($status->{version}, 2, '$status->{version} = 2');
  is_deeply($status->{pending}, [], '$status->{pending} is empty');
  is_deeply($status->{applied}, [
    $test_dir->child('000_t1.up.sql')->stringify,
    $test_dir->child('001_t2.up.sql')->stringify,
  ], '$status->{applied} has all migrations');
}

note('rollback one migration');
{
  is( rollback($dbh, 1, log => $noop), 1, 'user_version=1' );
  is( version($dbh), 1, 'version($dbh) = 1' );
  throws_ok {
    $dbh->selectrow_array('select 1 from t2');
  } qr/no such table: t2/, 'select from t2 should fail';
  lives_ok {
    $dbh -> selectrow_array('select 1 from t1');
  } 'select from t1 should still succeed';

  my $status = status($dbh);
  is($status->{version}, 1, '$status->{version} = 1');
  is_deeply($status->{pending}, [
    $test_dir->child('001_t2.up.sql')->stringify,
  ], '$status->{pending} has one migration');
  is_deeply($status->{applied}, [
    $test_dir->child('000_t1.up.sql')->stringify,
  ], '$status->{applied} has one migration');
}

note('remigrate to latest');
is( migrate($dbh, log => $noop), 2, 'user_version=2' );
lives_ok {
  $dbh->selectrow_array('select 1 from t1');
  $dbh->selectrow_array('select 1 from t2');
} 'select from both tables should succeed';

note('rollback completely');
{
  is( rollback($dbh, undef, log => $noop), 0, 'user_version=0' );
  is( version($dbh), 0, 'version($dbh) = 0' );
  throws_ok {
    $dbh->selectrow_array('select 1 from t2');
  } qr/no such table: t2/, 'select from t2 should fail';
  throws_ok {
    $dbh->selectrow_array('select 1 from t1');
  } qr/no such table: t1/, 'select from t1 should fail';

  my $status = status($dbh);
  is($status->{version}, 0, '$status->{version} = 0');
  is_deeply($status->{pending}, [
    $test_dir->child('000_t1.up.sql')->stringify,
    $test_dir->child('001_t2.up.sql')->stringify,
  ], '$status->{pending} has all migrations');
  is_deeply($status->{applied}, [], '$status->{applied} is empty');
}

note('rollback to garbage version');
{
  is(migrate($dbh, log => $noop), 2, 'remigrate');
  is(rollback($dbh, 2, log => $noop), 2, 'migrate to current version');

  throws_ok { rollback($dbh, -1); } qr/invalid target version/;
  throws_ok { rollback($dbh, 1000) } qr/invalid target version/;
  throws_ok { rollback($dbh, 'blabla') } qr/invalid target version/;
}

done_testing;

sub connect_to_db {
  my ($dbname) = @_;

  my $dbi = "dbi:SQLite:$dbname";
  DBI->connect($dbi, '', '', {
    RaiseError => 1,
    PrintError => 0,
    AutoCommit => 1,
    sqlite_defensive => 1,
  }) or die "failed to connect to database '$dbi': $DBI::errstr";
}
