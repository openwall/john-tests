#!/usr/bin/perl -w

# this script with the rule_tst.dat will test jtr rules

use strict;
use Getopt::Long;
use Storable;

my $VERSION = "0.01-\x{3B1}";
my $RELEASE_DATE = "March 21, 2016";

my $JOHN_PATH = "../run";
# NOTE, john built on Windows 'may' need this lines changed to "$JOHN_PATH/john.exe" IF the script will not run properly.
my $JOHN_EXE  = "$JOHN_PATH/john";
my $verbosity  = 2;
my @rules;
my @caps=();
my @encs=();  # we 'may' need to handle encodings for rules (we do not do so yet).
my @johnUsageScreen=();
my %opts=(line_num => 0);
my @rulesdata;
my $show_stderr=0;
my $last_line_len=0;
my $core_only=0; # assume jumbo john. Actually at this time we ONLY work with jumbo.
my $error_cnt = 0; my $done_cnt = 0; my $ret_val_non_zero_cnt = 0;
my @startingTime;

# Set this once and we don't have to care about it anymore
$ENV{"LC_ALL"} = "C";
binmode STDOUT, ":utf8";
###############################################################################
# MAIN (much code borrowed from jtrts.pl)
###############################################################################

startTime();
parseArgs();
setup();
readData();
#filterPatterns();
process();
cleanup();
unlink_restore();
displaySummary();
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
		else { ScreenOutAlways ("All tests passed without error.  Performed $done_cnt tests.  Time used was $secs seconds\n"); }
	} else {
		my $s = "Some tests had Errors. Performed $done_cnt tests.";
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
	my $help = 0;
	my $resume = 0;
	my $err = GetOptions(\%opts,
		'help|?'             => \$help,
		'quiet+'         ,#  => \$quiet,
		'verbose+'       ,#  => \$verbose,
		'basepath=s'     ,#  => \$basepath,
		'stoponerror!'   ,#  => \$stop_on_error,
		'showstderr!'    ,#  => \$show_stderr,
		'resume!'            => \$resume,
		);
	if ($err == 0) {
		print "exiting, due to invalid option\n";
		exit 1;
	}
	if ($help) { usage($JOHN_PATH); }
	if (@ARGV) {$opts{argv} = \@ARGV; }
###	if ($resume != 0) { ResumeState(); $opts{resume}=1; }
###	else { SaveState(); }

	if (defined $opts{argv})        {@ARGV              = @{$opts{argv}}; }
	if (defined $opts{showstderr})  {$show_stderr       = $opts{showstderr}; }
	if (defined $opts{basepath}) {
		$JOHN_PATH = $opts{basepath};
		$JOHN_EXE  = "$JOHN_PATH/john";
	}
	$verbosity = 2;
	if (defined $opts{verbose}) { $verbosity += $opts{verbose} }
	if (defined $opts{quiet})   { $verbosity -= $opts{quiet} }
	my $cnt=0;
}
###############################################################################
# -? -help, or some failed option selected.  Show the usage screen.
###############################################################################
sub usage {
die <<"UsageHelp";

JtR Rules tester, command usage:

usage: $0 [-h|-?] [-option[s]]
    Options can be abbreviated!

    Options are:
    -basepath  <s> set the basepath where john exe is located. By default
                   this is set to $_[0]
    -quiet+        Makes JtRTest Suite more 'quiet' or more verbose. -q
    -verbose+      is a good level to run.  -q -q is very quiet, does not
                   output until run has ended, unless there are errors.
                   -v is the opposite of -q.  -v outputs a lot of information.
                   -v -v  is pretty much debugging level, it outputs a LOT.
                   -v -v -v dumps even more, also showing Jtr screen output.
                   -q -v together is a no-op.
    -resume        This is NOT a running 'state'. This will resume the TS where
                   it left off on the last run (whether by exit due to -stoponerr
                   or by user ^C exit. This is useful for when deep in the run
                   there was an error, and you then 'fix' the error, and want
                   to start tests off where you left off at.
    -stoponerror   Causes JtRts to stop if any error is seen.  The .pot file
                   and other temp files will be left, AND the command line
                   that was run is listed. (default is -nostoponerror).
    -showstderr    Allows any stderr writing to 'show' on screen. Usually not
                   wanted, but for some usage, like memory leak checking, or
                   other errors, any display of stderr is needed.
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

	ScreenOutAlways("-------------------------------------------------------------------------------\n");
	ScreenOutAlways("- JtR-Rules tester (rules_tst). Version $VERSION, $RELEASE_DATE.  By, Jim Fougeron\n");
	ScreenOutAlways("- Testing:  $johnUsageScreen[0]"); # note the line ends in a \n, so do not add one.
	ScreenOutAlways("--------------------------------------------------------------------------------\n");
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
	foreach my $line(@lines) {
		chomp($line);
		$line =~ s/\r$//;  # strip CR for non-Windows
		if (length($line) > 0 && substr($line, 0, 1) ne "#") {
			#$line = "(*)" . $line;  # we have now added the "base", so there is no reason for this one.
			my @ar = split('	', $line);
			my $cnt = @ar;
			if ($cnt == 4) {
				# we may have to deal with rules that are not in core.
				push(@rulesdata, $line);
			}
		}
	}
	if ($verbosity > 3) {
		my $cnt = @rulesdata;
		ScreenOutVVV("Running data-dictionary. $cnt items (rule_tst.dat):\n");
		foreach my $line(@rulesdata) { ScreenOutVVV($line . "\n"); }
		ScreenOutVVV("\n");
	}
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
	# add the cur_tst rule
	push(@fixed, "[List.Rules:cur_tst]\n");
	push(@fixed, "$_[0]\n");

	# write the local file again.
	open(FILE, ">john-local.conf") or die $!;
	print FILE @fixed;
	close(FILE);
}
sub WriteInputFile {
	my $s = $_[0];
	$s =~ s/\\n/\n/g;
	# write the local file again.
	open(FILE, ">tst-.in") or die $!;
	print FILE $s;
	close(FILE);
}
sub CreateExpected {
	my $s = $_[0];
	$s =~ s/\\n/\n/g;
	# write the local file again.
	open(FILE, ">tst-.exp") or die $!;
	print FILE $s."\n";
	close(FILE);
}
sub cleanup {
	unlink glob('tst-*');
}
sub ResumeState {
	%opts = %{retrieve('rules_tst.resume')};
}
sub SaveState {
	store \%opts, 'rules_tst.resume';
}
sub unlink_restore {
	unlink ('rules_tst.resume');
}
sub StopOnError {
	my $cmd=$_[0];
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

	LINE: foreach my $line(@rulesdata) {
		# start of -resume code (pretty trivial, I just count line#'s)
		++$line_num;
		if (defined $opts{resume} && $opts{resume} > 0 && defined $opts{line_num}) {
			if ($line_num < $opts{line_num}) {
				ScreenOutV("resuming. Skipping line $line_num = $line\n");
				next LINE;
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
		UpdateLocalConfig($ar[0]);
		WriteInputFile($ar[2]);
		my @expected = CreateExpected($ar[3]);
		my $cmd = $cmd_head;

		if ($show_stderr != 1) { $cmd .= " > tst-.out 2> /dev/null"; }
		# this will switch stderr and stdout (vs joining them), so we can grab stderr BY ITSELF.
		else { $cmd .= " > tst-.out 3>&1 1>&2 2>&3 >/dev/null"; }

		ScreenOutVV("Execute john: $cmd\n");
		my $cmd_data = `$cmd`;
		my $ret_val = $?;
		if ($ret_val != 0) { $ret_val_non_zero_cnt += 1; }
		# ok, now show stderr, if asked to.
		if ($show_stderr == 1) { print $cmd_data; }
		ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");

		# we can later on come up with something better, but for this
		# POC, a simple diff test is just fine.
		my $s = `diff tst-.out tst-.exp`;
		++$done_cnt;
		if (length($s) > 0) {
			print "problem found with rule \"$ar[1]\" = $ar[0]\n";
			print $s;
			$error_cnt += 1;
			StopOnError($cmd);
		}
	}
	if (!stringInArray("local_pot_valid", @caps)) {
		# handle john 'core' behavior.  then we delete the pot we just made, then rename the 'saved' version.
	}
	unlink "tst-.in";
	unlink "tst-.exp";
	unlink "tst-.out";
}
