#!/usr/bin/perl
# @dynamic=expr@ fuzzer

my @funcs = ();

add_funcs ('md4', 'md5', 'sha1', 'sha224', 'sha256', 'sha384', 'sha512', 'gost', 'tiger', 'whirlpool',
          'ripemd128', 'ripemd160', 'ripemd256', 'ripemd320', 'haval128_3', 'haval128_4', 'haval128_5',
          'haval160_3', 'haval160_4', 'haval160_5', 'haval192_3', 'haval192_4', 'haval192_5',
          'haval224_3', 'haval224_4', 'haval224_5', 'haval256_3', 'haval256_4', 'haval256_5', 'md2',
          'skein224', 'skein256', 'skein384', 'skein512', 'sha3_224', 'sha3_256', 'sha3_384', 'sha3_512', 
          'keccak_256', 'keccak_512');

#foreach $f (@funcs) {
#	print "$f ";
#}
my $i; my $j; my $k;
my $tests = 0; my $fails = 0;
for ($i = 0; $i < scalar(@funcs); ++$i) {
	my $f = $funcs[$i];
	next if $f =~ /_raw$/;
	my $s = `../run/john -test=0 -form=\'dynamic=$f(\$p)\'`;
	chomp $s;
	print $s."               \r";
	if (not $s =~ / PASS/) {
		print "-form=\'dynamic=$f(\$p)\' failed                       \n";
		$fails += 1;
	}
	$tests += 1;
}
for ($i = 0; $i < scalar(@funcs); ++$i) {
	my $f = $funcs[$i];
	next if $f =~ /_raw$/;
	for ($j = 0; $j < scalar(@funcs); ++$j) {
		my $f2 = $funcs[$j];
		my $s = `../run/john -test=0 -form=\'dynamic=$f($f2(\$p))\'`;
		chomp $s;
		print $s."               \r";
		if (not $s =~ / PASS/) {
			print "-form=\'dynamic=$f($f2(\$p))\' failed                       \n";
			$fails += 1;
		}
		$tests += 1;
		$s = `../run/john -test=0 -form=\'dynamic=$f($f2(\$s.\$p))\'`;
		chomp $s;
		print $s."               \r";
		if (not $s =~ / PASS/) {
			print "-form=\'dynamic=$f($f2(\$s.\$p))\' failed                       \n";
			$fails += 1;
		}
		$tests += 1;
		$s = `../run/john -test=0 -form=\'dynamic=$f($f2(\$p).\$s)\'`;
		chomp $s;
		print $s."               \r";
		if (not $s =~ / PASS/) {
			print "-form=\'dynamic=$f($f2(\$p).\$s)\' failed                       \n";
			$fails += 1;
		}
		$tests += 1;
		$s = `../run/john -test=0 -form=\'dynamic=$f($f2(\$p).\$s.$f(\$p))\'`;
		chomp $s;
		print $s."               \r";
		if (not $s =~ / PASS/) {
			print "-form=\'dynamic=$f($f2(\$p).\$s.$f(\$p))\' failed                           \n";
			$fails += 1;
		}
		$s = `../run/john -test=0 -form=\'dynamic=$f(\$s.$f2(\$p).\$s.$f(\$p))\'`;
		chomp $s;
		print $s."               \r";
		if (not $s =~ / PASS/) {
			print "-form=\'dynamic=$f(\$s.$f2(\$p).\$s.$f(\$p))\' failed                       \n";
			$fails += 1;
		}
		$tests += 1;
	}
}
print "dyna_expr_fuzzer.pl: Perfored $tests tests, and there were $fails failures.        \n";

sub add_funcs {
	my $f = shift;
	while (defined $f) {
		push (@funcs, $f);
		push (@funcs, uc $f);
		push (@funcs, $f.'_raw');
		push (@funcs, $f.'_64');
		push (@funcs, $f.'_64c');
		$f = shift;
	}
}

