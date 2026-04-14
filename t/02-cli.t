#!perl

use v5.26;
use strict;
use warnings;

use Test::More;
use Test::Output;
use File::Temp qw(tempdir);
use Path::Tiny qw(path);
use SQLite::Migrate qw();
use SQLite::Migrate::CLI qw();

my $test_dir = path(tempdir(CLEANUP => 1));
my $test_db = $test_dir->child('test.db');

# create mock migrations
$test_dir->child('000_first.up.sql')->spew_utf8('select 1;');
$test_dir->child('000_first.down.sql')->spew_utf8('select 1;');
$test_dir->child('001_second.up.sql')->spew_utf8('select 1;');
$test_dir->child('001_second.down.sql')->spew_utf8('select 1;');

my sub run_cmd {
  my ($cmd, @args) = @_;
  SQLite::Migrate::CLI::run($cmd, "$test_db", '--dir', "$test_dir", @args);
}

note('--dir with invalid directory');
{
  my $exit;
  stderr_like {
    $exit = SQLite::Migrate::CLI::run('deploy', "$test_db", '--dir', 'invalid_dir');
  } qr/No such file or directory/;
  is($exit, 1, 'exit with failure');
  is($SQLite::Migrate::MIGRATION_DIR, 'invalid_dir', 'migration dir set');
}

note("creates parent directory for db if it doesnt exist");
{
  my $nested_db = path("$test_dir/a/b/test.db");
  my $exit;
  stdout_like {
    $exit = SQLite::Migrate::CLI::run('deploy', "$nested_db", '--dir', "$test_dir")
  } qr/user_version=2/, 'user_version=2';
  is($exit, 0, 'exit success');
  ok($nested_db->exists, 'directory exists');
}

note('no subcommand');
{
  my $exit = SQLite::Migrate::CLI::run();
  is($exit, 1, 'exit with failure');
}

note('valid subcommand, no db specified');
{
  my $exit = SQLite::Migrate::CLI::run('deploy');
  is($exit, 1, 'exit with failure');
}

note('invalid command');
{
  my $exit;
  stderr_like {
    $exit = run_cmd('blabla');
  } qr/unknown command: blabla/, 'prints error';
  is($exit, 2, 'exit with failure');
}

note('init is idempotent');
{
  is(run_cmd('init'), 0, 'exit success');

  my %files = (
    up => $test_dir->child('000_init.up.sql'),
    down => $test_dir->child('000_init.down.sql'),
  );

  ok($_->is_file, "$_ exists") for values %files;

  my %stat = map { $_ => $files{$_}->stat } keys %files;
  is(run_cmd('init'), 0, 'exit success');
  is_deeply($files{$_}->stat, $stat{$_}, "$_ file unchanged")
    for keys %files;
}

note('deploy');
{
  my $exit;
  stdout_like {
    $exit = run_cmd('deploy')
  } qr/user_version=2/, 'user_version=2';
  is($exit, 0, 'exit success');
}

note('rollback to version');
{
  my $exit;
  stdout_like {
    $exit = run_cmd('rollback', '1');
  } qr/user_version=1/, 'user_version=1';
  is($exit, 0, 'exit success');
}

note('rollback');
{
  my $exit;
  stdout_like {
    $exit = run_cmd('rollback');
  } qr/user_version=0/, 'user_version=0';
  is($exit, 0, 'exit success');
}

note('rollback to garbage version');
TODO: {
  local $TODO = "determine what to do in this case";
  my $exit = run_cmd('rollback', '10000');
  is($exit, 0, 'exit success');
}


done_testing;
