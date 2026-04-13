#!perl -T

use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
  use_ok('SQLite::Migrate') || print "Bail out!\n";
}

diag(
  "Testing SQLite::Migrate $SQLite::Migrate::VERSION, Perl $], $^X"
);
