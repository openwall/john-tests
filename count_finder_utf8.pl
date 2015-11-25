#!/usr/bin/perl -w
use strict;

# this program will read pw-new.dic, and list counts.  You provide the max length of lines
# that make up the input file, and then other shorter lengths, and this script will tell
# how many passwords are of the shorter lengths.  So, ./count_finder.pl 110 55 will list
# 1500 for length 110, and then 1120 (or how even many it is) for length 55.

if (scalar @ARGV > 4 || scalar @ARGV < 2) { die print "usage: ./count_finder.pl max_len shorter_len [count [pw file]]\n"; }
my $count = 1500;
my $pw_name = "pw-new.dic";
my $len = $ARGV[0];
my $short = $ARGV[1];
if ($len <= $short) { die print "error! shorter_len was not shorter\nusage: ./count_finder.pl max_len shorter_len [count [pw file]]\n"; }
my $short_cnt = 0;
if (scalar @ARGV > 2) {$count = $ARGV[2];}
if (scalar @ARGV == 4) {$pw_name = $ARGV[3];}
my $orig_count = $count;
my $line_cnt = 0;

open FILE, '<:encoding(UTF-8)', $pw_name or die "Can't open '$pw_name' for reading: $!"; 
my @words = <FILE>;
close(FILE);
foreach my $word (@words) {
	chomp $word;
	++$line_cnt;
	if (length($word) <= $len) {
		$count--;
		if (length($word) <= $short) { $short_cnt++; }
		if ($count == 0) {
			print "Found $orig_count of length $len  (required $line_cnt total lines to do)\n";
			print "Found $short_cnt of length $short\n";
			exit(0);
		}
	}
}
print "ran out of words, there were not $orig_count of length $len\n";
print "Found $orig_count-$count of length $len\n";
print "Found $short_cnt of length $short\n";


