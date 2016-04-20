#!/usr/bin/perl -w

# this script with the rule_tst.dat will test jtr rules

use strict;
use Getopt::Long 'GetOptionsFromArray';
use Storable;
use Text::Tabs;

use File::Basename;
use lib dirname(__FILE__).'/';
use lib dirname(__FILE__).'/../run';
use jtr_rulez;

my $VERSION = "0.92-\x{3B2}";
my $RELEASE_DATE = "March 27, 2016";

my $JOHN_PATH = "../run";
# NOTE, john built on Windows 'may' need this lines changed to "$JOHN_PATH/john.exe" IF the script will not run properly.
my $JOHN_EXE  = "$JOHN_PATH/john";
my $verbosity = 2;
my @rules;
my @caps=();
my @encs=();  # we 'may' need to handle encodings for rules (we do not do so yet).
my @johnUsageScreen=();
my %opts=(line_num => 0);
my @rulesdata;
my $show_stderr=0;
my $last_line_len=0;
my $core_only=0; # assume jumbo john. Actually at this time we ONLY work with jumbo.
my $error_cnt = 0; my $done_cnt = 0; my $tot_rules = 0; my $ret_val_non_zero_cnt = 0;
my $max_pp = 15000;
my @startingTime;

# Set these once and we don't have to care about them anymore
$ENV{"LC_ALL"} = "C";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";
###############################################################################
# MAIN (much code borrowed from jtrts.pl)
###############################################################################
local $| = 1;  # forces non buffered line io on stdout.
startTime();
parseArgs();
setup();
readData();
process();
cleanup();
unlink_restore();
displaySummary();
UpdateLocalConfig("", 1);
exit $error_cnt+$ret_val_non_zero_cnt;

###############################################################################
# End of MAIN. Everything from this point on is subroutines.
###############################################################################
sub startTime {
	@startingTime = gmtime(time);
}
sub displaySummary {
	my @timeEnd = gmtime(time);
	my $secs = timeToSecs(@timeEnd)-timeToSecs(@startingTime);
	if ($error_cnt == 0 && $ret_val_non_zero_cnt == 0) {
		if ($done_cnt == 0) { ScreenOutAlways ("NO tests were performed.  Time used was $secs seconds\n"); }
		else { ScreenOutAlways ("All tests passed without error.  Performed $done_cnt tests and created $tot_rules rules.\n Time used was $secs seconds\n"); }
	} else {
		my $s = "Some tests had Errors. Performed $done_cnt tests and created $tot_rules rules.";
		unless ($error_cnt == 0) { $s = $s . "  $error_cnt errors"; }
		unless ($ret_val_non_zero_cnt == 0) { $s = $s . "  $ret_val_non_zero_cnt runs had non-clean exit"; }
		ScreenOutAlways ("$s\nTime used was $secs seconds\n");
	}
}
###############################################################################
# parse our command line options.
###############################################################################
sub parseArgs {
	my @passthru=();
	my @args = @ARGV;
	my $help = 0;
	my $resume = 0;
	my $err = GetOptions(\%opts,
		'help|?'             => \$help,
		'quiet+'         ,#  => \$quiet,
		'verbose+'       ,#  => \$verbose,
		'basepath=s'     ,#  => \$basepath,
		'stoponerror!'   ,#  => \$stop_on_error,
		'showstderr!'    ,#  => \$show_stderr,
		'full!'          ,#  => \$full,
		'dump_rules+',   ,#  => \$dump_rules_only,
		'lib_dbg_lvl=i'  ,#  => \$lib_dbg_lvl
		'resume!'            => \$resume,
		);
	if ($err == 0) {
		print "exiting, due to invalid option\n";
		exit 1;
	}
	$opts{quiet} = 0; $opts{verbose} = 0; $opts{dump_rules} = 0;
	if ($help) { usage($JOHN_PATH); }
	if (@ARGV) {$opts{argv} = \@ARGV; }
	if ($resume != 0) { ResumeState(); $opts{resume}=1; }
	else { SaveState(); }

	# re-get command args, so these 'can' override what was in save file.
	GetOptionsFromArray(\@args, \%opts,
		'quiet+'         ,#  => \$quiet,
		'verbose+'       ,#  => \$verbose,
		'stoponerror!'   ,#  => \$stop_on_error,
		'showstderr!'    ,#  => \$show_stderr,
		'full!'          ,#  => \$full,
		'dump_rules+',   ,#  => \$dump_rules_only,
		'lib_dbg_lvl=i'  ,#  => \$lib_dbg_lvl
		);

	if (defined $opts{full})        { $max_pp = 99999999; }
	if (defined $opts{argv})        {@ARGV              = @{$opts{argv}}; }
	if (defined $opts{showstderr})  {$show_stderr       = $opts{showstderr}; }
	if (defined $opts{basepath}) {
		$JOHN_PATH = $opts{basepath};
		$JOHN_EXE  = "$JOHN_PATH/john";
	}
	$verbosity = 2;
	if (defined $opts{verbose})   { $verbosity += $opts{verbose} }
	if (defined $opts{quiet})     { $verbosity -= $opts{quiet} }
	if (defined $opts{dump_rules}){ $verbosity -= $opts{dump_rules} }
	my $cnt=0;
}
###############################################################################
# -? -help, or some failed option selected.  Show the usage screen.
###############################################################################
sub usage {
die <<"UsageHelp";

JtR Rules tester $VERSION - $RELEASE_DATE

usage: $0 [-h|-?] [-option[s]]
    Options can be abbreviated!

    Options are:
    -basepath  <s> set the basepath where john exe is located. By default this is set to $_[0]
    -quiet+        Makes JtRTest Suite more 'quiet' or more verbose. -q
    -verbose+      is a good level to run.  -q -q is very quiet, does not output until run has
                   ended, unless there are errors. -v is the opposite of -q.  -v outputs more
                   -v -v even more.  -q -v together is a no-op.
    -resume        This is NOT a running 'state'. This will resume the TS where it left off on
                   the last run (whether by exit due to -stoponerr or by user ^C exit. This is
                   useful for when deep in the run there was an error, and you then 'fix' the
                   error, and want to start tests off where you left off at.
    -stoponerror   Causes rule_tst.pl to stop if any error is seen. (default is -nostoponerror).
    -showstderr    Allows any stderr writing to 'show' on screen. Usually not wanted. default off.
    -full          tests all rules. Some take a while to build in perl. Normally, where the rule
                   would preproc to more than 5000 rules it is skipped. This flag processes these.
    -dump_rules    if set, then the script will load the first rule, and simply print all items
                   which the preprocessor built.
    -lib_dbg_lvl=i Sets the debugging level in the jtr_rulez.pm code (debugging output).
    -help|?        shows this help screen.

UsageHelp
}
# this is the 'normal' screen output
sub ScreenOut {
	if ($verbosity >= 2) {
		print "@_";
		$last_line_len = 0;
	}
}
# output to screen no matter what mode we are in.  This is used to show
# errors. Either script not setup or called right, OR a test failure error.
sub ScreenOutAlways {
	print "@_";
	use strict;
	$last_line_len = 0;
}
# print verbose 'v' messages
# also able to print array's (debugging shit).
sub ScreenOutV {
	if ($verbosity > 2) {
		print "@_";
		$last_line_len = 0;
	}
}
# this screen output output 1 line, and overwrite it, if in 'q' quiet mode. In 'qq' it will
# output nothing.  In 'normal mode', it will call ScreenOut
sub ScreenOutSemi {
	if ($verbosity < 1) { return; }
	if ($verbosity == 1) {
		my $s = ' ' x $last_line_len;
		print "\r$s\r";
		$s = $_[0];
		chomp $s;
		print $s."\r";
		$last_line_len = length( expand($s));
	} else { ScreenOut(@_); }
}
# print verbose 'vv' messages
# also able to print array's (debugging shit).
sub ScreenOutVV {
	if ($verbosity > 3) {
		print "@_";
		$last_line_len = 0;
	}
}
sub ScreenOutVVV {
	if ($verbosity > 4) {
		print "@_";
		$last_line_len = 0;
	}
}
sub stringInArray {
	my $str = shift;
	foreach my $elem(@_) {
		if ($str eq $elem) {
			return 1;
		}
	}
	return 0;
}
sub timeToSecs {
	# not a time_t, but enough to add/subtract one time from another, and get # of seconds.
	my $secs = 0;
	$secs += $_[0];
	$secs += $_[1]*60;
	$secs += $_[2]*3600;
	$secs += $_[7]*3600*24;
	return $secs;
}
###############################################################################
# Setup the program to run.  Only checks for john version, whether core or
# bleeding, etc.
###############################################################################
sub setup {
	if ( ! -d $JOHN_PATH ) {
		ScreenOutAlways("ERROR, the JOHN_PATH variable has to be setup properly for this script file to run.\n");
		exit;
	}
	if ( ! -f $JOHN_EXE )  {
		ScreenOutAlways("Error, the JOHN_EXE variable is not setup properly, or john was not built yet\n");
		exit;
	}

	# we store a john error string to this file.  We will use this data in several ways, later.
	system ("$JOHN_EXE >tst-JohnUsage.Scr 2>&1");
	system ("$JOHN_EXE --list=hidden-options >>tst-JohnUsage.Scr 2>&1");
	open(FILE, "<tst-JohnUsage.Scr") or die $!;
	@johnUsageScreen = <FILE>;
	close(FILE);
	unlink ("tst-JohnUsage.Scr");

	ScreenOutAlways("--------------------------------------------------------------------------------------\n");
	ScreenOutAlways("- JtR-Rules tester (rules_tst). Version $VERSION, $RELEASE_DATE.  By, Jim Fougeron\n");
	ScreenOutAlways("- Testing:  $johnUsageScreen[0]"); # note the line ends in a \n, so do not add one.
	ScreenOutAlways("---------------------------------------------------------------------------------------\n");
	ScreenOut("\n");
	# now use the john error screen to determine if this is a jumbo john, or
	# a core john.

	ScreenOutVV("John 'usage' data is:\n");
	ScreenOutVV(@johnUsageScreen);

	# can we use -pot=tst-.pot ?
	if (grepUsage("--pot=NAME")) {
		push(@caps, "jumbo" );
		ScreenOut("John Jumbo build detected.\n");
	} else {
		push(@caps, "core" );
		ScreenOut("John CORE build detected.  Only core formats can be tested.\n");
		$core_only = 1;
		die print "at this time, this script ONLY works with john jumbo\n";
	}
	# can we use -nolog option
	if (grepUsage("--nolog")) {
		push(@caps, "nolog_valid");
		ScreenOutV("--nolog option is valid\n");
	}
	# does this version handle --dupe-supression ?
	if (grepUsage("--dupe-supression")) {
		push(@caps, "dupe_suppression");
		ScreenOutV("--dupe-suppression option is valid\n");
	}
	# can we use --config=john.conf ?
	if (grepUsage("--config=FILE")) { push(@caps, "config_valid");
		ScreenOutV("--config=FILE option is valid\n");
	}
	if (grepUsage("--pot=NAME")) {
		push(@caps, "local_pot_valid");
		ScreenOutV("--pot=NAME option is valid\n");
	}
	# can we use --encoding=utf8, --encoding=koi8r, etc.
	if (grepUsage("--encoding=NAME")) {
		push(@caps, "encode_valid");
		ScreenOutV("--encoding=NAME option is valid\n");
		if (grepUsage("--encoding=LIST")) {
			loadAllValidEncodings();
		} else {
			# 'hopefully' these are valid.
			push(@encs, "utf8", "cp1252", "cp1251", "koi8r", "cp437", "cp737", "cp850", "cp858", "cp866", "iso8859-1", "iso8859-15" );
			push(@caps, @encs );
		}
	}
	ScreenOutV("Capabilities in this build of john:\n");
	ScreenOutV(@caps);
	ScreenOutV("\n");
}
sub grepUsage {
	foreach my $line(@johnUsageScreen) {
		if (index($line,$_[0]) ge 0) {
			return 1;
		}
	}
	return 0;
}
###############################################################################
# we read the data file 'rule_tst.dat'.  This is a tab delimited CSV file.
# it contains data with john rules, input data and expected output data.
###############################################################################
sub readData {
	open(FILE, "<rule_tst.dat") or die $!;
	my @lines = <FILE>;
	close(FILE);
	my $line_cnt = 0;
	foreach my $line(@lines) {
		chomp($line);
		$line =~ s/[ \t\r]*$//;  # strip CR for non-Windows, and 'ltrim', so that blank lines (with white space) are skipped.
		++$line_cnt;
		if (length($line) > 0) {
			if (substr($line, 0, 1) eq "#") { push(@rulesdata, $line); }
			else { push(@rulesdata, $line."	line count: $line_cnt"); }
		}
	}
	if ($verbosity > 3) {
		my $cnt = @rulesdata;
		ScreenOutVVV("Running data-dictionary. $cnt items (rule_tst.dat):\n");
		foreach my $line(@rulesdata) { ScreenOutVVV($line . "\n"); }
		ScreenOutVVV("\n");
	}
}
sub WriteTheFile {
	my $fname = shift;
	# write the local file again.
	open(FILE, "> $fname") or die $!;
	print FILE @_;
	close(FILE);
}
sub UpdateLocalConfig {
	open(FILE, "<john-local.conf") or die $!;
	my @lines = <FILE>;
	close(FILE);
	my @fixed = ();
	my $fnd = 0;
	foreach my $s (@lines) {
		if (!$fnd && index($s, "[List.Rules:cur_tst]") == -1) {
			push(@fixed, $s);
		} else {
			if ($fnd++ == 1) {
				$fnd = 0;
			}
		}
	}
	if (defined($_[1]) && $_[1] == 1) {
		WriteTheFile("john-local.conf", @fixed);
		return;
	}
	# add the cur_tst rule
	push(@fixed, "[List.Rules:cur_tst]\n");
	push(@fixed, "$_[0]\n");
	WriteTheFile("john-local.conf", @fixed);
}
sub one_rule { my ($rule_cnt, $rule, $word, $x, $y, $last) = (@_);
	if ($rule_cnt == 0) { $_[3] .= "$word\n"; }
	my $s = jtr_run_rule($rule, $word);
	if (length($s) && $s ne $last) { $_[4] .= $s."\n"; $_[5] = $s;}
}
sub build_files { my ($_rule) = (@_);
	my $sw=""; my $sm=""; my $last; my $cnt=$max_pp;
	my $rule = jtr_rule_pp_init($_rule, 125, $cnt); # use 125 byte 'format' for our tests.
	if (defined $_[1]) { $_[1] = $cnt; }
	if ($cnt>$max_pp) {
		return 0;
	}
	my $rule_cnt = 0;
	$last = "";
	while (defined ($rule) && length($rule)>0) {
		one_rule($rule_cnt, $rule, "teste thise", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testie thisie", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testa thisa", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testi thisi", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testo thiso", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testu thisu", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testb thisb", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testh thish", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testf thisf", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testz thisz", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testy thisy", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testey thisey", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testg thisg", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testpg thispg", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testch thisch", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testpg thispg", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "testpp thispp", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "HapYYr 1235\txte l", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "12345", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, "12345;/", $sw, $sm, $last);
		my $s = ""; my $i;
		for ($i = 1; $i < 0x1d; $i++) {
			if ($i != 0x0A && $i != 0x0D) {
				$s .= chr($i);
			}
		}
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, " ", $sw, $sm, $last);
		$s = ""; for (; $i < 40; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		$s = ""; for (; $i < 60; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		$s = ""; for (; $i < 65; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		$s = ""; for (; $i < 85; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		$s = ""; for (; $i < 125; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		$s = ""; for (; $i < 135; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		$s = ""; for (; $i < 255; $i++) { $s .= chr($i); }
		one_rule($rule_cnt, $rule, "$s", $sw, $sm, $last);
		one_rule($rule_cnt, $rule, 'a !"#$%&\'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~', $sw, $sm, $last);
		one_rule($rule_cnt, $rule, 'xxxabd0987654321', $sw, $sm, $last);  # generates:  (?a )?d /?d 'p Xpz0
		one_rule($rule_cnt, $rule, '0985674321xxxaby', $sw, $sm, $last);  # generates:  )?a (?d /?a 'p Xpz0
		one_rule($rule_cnt, $rule, 'josh', $sw, $sm, $last);              # generates: !?A (?\p1[za] \p1[lc] $s M 'l p Q X0z0 'l $s
		one_rule($rule_cnt, $rule, 'e' x 122, $sw, $sm, $last);           # generates: l Az"19[7-96-0]" <+ >-  or l Az"20[01]" <+ >-
		++$rule_cnt;
		$rule = jtr_rule_pp_next();
	}
	WriteTheFile("tst-.exp", $sm);
	WriteTheFile("tst-.in", $sw);
	return 1;
}
sub cleanup {
	unlink glob('tst-*');
}
sub ResumeState {
	%opts = %{retrieve('rule_tst.resume')};
	foreach my $k (keys(%opts)) {
		print ("$k=$opts{$k}\n");
	}
}
sub SaveState {
	store \%opts, 'rule_tst.resume';
}
sub unlink_restore {
	unlink ('rule_tst.resume');
}
sub StopOnError {  my ($cmd) = (@_);
	if (defined $opts{stoponerror} && $opts{stoponerror} > 0) {
		ScreenOut("Exiting on error.\n");
		$cmd =~ s# 2>&1##;
		$cmd =~ s# 2?>/dev/null##g;
		$cmd =~ s# 2>_stderr##g;
		ScreenOut("The command used to run this test was:\n\n$cmd\n");
		exit(1);
	}
}
sub process {
	my $line_num = 0;
	my $cmd_head = "$JOHN_EXE -stdout -rules=cur_tst -w=tst-.in";
	if (stringInArray("nolog_valid", @caps)) { $cmd_head = "$cmd_head -nolog"; }
	#if (stringInArray("config_valid", @caps)) { $cmd_head = "$cmd_head -config=john.conf"; }
	if (stringInArray("local_pot_valid", @caps)) {
	}
	else {
		# handle john 'core' behavior.  We save off existing john.pot, then it is overwritten
	}
	my $line = "";

	if (defined $opts{full}) { $max_pp = 99999999; }
	if ($opts{dump_rules} > 0) { print "\n"; }
	jtr_std_out_rules_set($opts{dump_rules});
	if (defined $opts{lib_dbg_lvl}) { jtr_dbg_level($opts{lib_dbg_lvl}); }

	#/^ s^[!@#$%&*()\-=_+\\|;:'",./?><]
	foreach my $line(@rulesdata) {
		# start of -resume code (pretty trivial, I just count line#'s)
		++$line_num;
		if (defined $opts{resume} && $opts{resume} > 0 && defined $opts{line_num}) {
			if ($line_num < $opts{line_num}) {
				ScreenOut("resuming. Skipping line $line_num = $line\n");
				next;
			}
		}
		# end of -resume code.
		unlink "tst-.in";
		unlink "tst-.exp";
		unlink "tst-.out";

		# mark that we are starting a new line. If we crash here,
		# a -resume picks up where we left off, i.e. on this test.
		$opts{line_num} = $line_num;
		SaveState();

		my @ar = split('	', $line);
		if (scalar @ar == 1) {
			ScreenOutSemi("$line\n");
			next;
		}
		ScreenOutSemi(" ");
		# Ok, we try to reduce some overly bloated rules.  this allows many
		# more to be tested side by side against JtR in this slow perl script
		my $rulez = $ar[0];
		$rulez =~ s/\[0\-9\]/\[0\-2\]/g;
		$rulez =~ s/\[0\-9A\-Z\]/\[0\-2AZ\]/g;
		$rulez =~ s/\[A\-Z\]/\[A\-C\]/g;
		$rulez =~ s/\[a\-z\]/\[a\-c\]/g;
		$rulez =~ s/\[ \-~\]/\[ \-\\x24\]/g;
		$rulez =~ s/\[0\-9A\-E\]/\[0\-4\]/g;
		$rulez =~ s/\^&\(\)_\+\\-=\{\}\|\[\\\]\\\\;'":,\/<>\?`~\*/^&\\-{}|\[\\\]\\\\'"\//g;
		$rulez =~ s/!\$\@#%.\^&\(\)_\+\\-=\{\}\|\[\\\]\\\\;'":,\/<>\?`~\*/^&\$\\-{}|\[\\\]\\\\'"\//g;
		UpdateLocalConfig($rulez);
		my $pp_cnt=0;
		my $working = build_files($rulez, $pp_cnt);
		my $cmd = $cmd_head;

		if ($working == 0) {
			print ("Skipped ($pp_cnt PP items):  $rulez\n");
		} else {
			ScreenOutSemi("Testing Rule:  $ar[0]\n");
			if ($show_stderr != 1) { $cmd .= " > tst-.out 2> /dev/null"; }
			# this will switch stderr and stdout (vs joining them), so we can grab stderr BY ITSELF.
			else { $cmd .= " > tst-.out 3>&1 1>&2 2>&3 >/dev/null"; }

			ScreenOutVV("Execute john: $cmd\n");
			my $cmd_data = `$cmd`;
			my $ret_val = $?;
			if ($ret_val != 0) { ScreenOutAlways("Non-zero return from john $ret_val\n  Rule: $ar[0]\n\n"); $ret_val_non_zero_cnt += 1; }
			# ok, now show stderr, if asked to.
			if ($show_stderr == 1) { print $cmd_data; }
			ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");

			# we can later on come up with something better, but for this
			# POC, a simple diff test is just fine.
			my $s = `diff tst-.out tst-.exp`;
			my $size = -s "tst-.out";
			++$done_cnt;
			$tot_rules += $pp_cnt;
			if (length($s) > 0) {
				ScreenOutSemi(" ");
				ScreenOutAlways("problem found with rule \"$ar[1]\" = $ar[0]\n");
				print $s;
				$error_cnt += 1;
				StopOnError($cmd);
			}
			if ($size == 0) {
				ScreenOutSemi(" ");
				ScreenOutAlways("Warning no data generated by: \"$ar[1]\" = $ar[0]\n");
				StopOnError($cmd);
			}
		}
	}
	if (!stringInArray("local_pot_valid", @caps)) {
		# handle john 'core' behavior.  then we delete the pot we just made, then rename the 'saved' version.
	}
	unlink "tst-.in";
	unlink "tst-.exp";
	unlink "tst-.out";
}
