#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use jtrts_inc;
use Digest::MD5;

my $VERSION = "1.13";
my $RELEASE_DATE = "Dec 21, 2014";
# how to do alpha character left, so next 'alpha', or beta release will be easy.
#use utf8;
#my $VERSION = "1.10-\x{3B1}2"; # alpha-2
#binmode(STDOUT, ":utf8"); # to print the alpha char. once we get rid of the alpha char, this line should be commented out.

#############################################################################
# For the version information list, see the file JtrTestSuite.Manifest
# also see the github commit record at:
#   https://github.com/magnumripper/jtrTestSuite/commits/master
#############################################################################

# EDIT this variable to properly setup the john-test-suite script
my $JOHN_PATH = "../run";
# NOTE, john built on Windows 'may' need this lines changed to "$JOHN_PATH/john.exe" IF the script will not run properly.
my $JOHN_EXE  = "$JOHN_PATH/john";
my $UNIQUE    = "$JOHN_PATH/unique";
my $verbosity  = 2;
my $quiet = 0; my $verbose = 0;
my @types=();
my @nontypes=();
my @caps=();
my @encs=();
my @johnUsageScreen=();
my @validFormats=();
my @tstdata;
my $showtypes=0, my $basepath=""; my $prelims=0, my $stop_on_error=0, my $show_stderr=0;
my $last_line_len=0; my $internal_testing;
my $error_cnt = 0, my $error_cnt_pot = 0; my $done_cnt = 0; my $ret_val_non_zero_cnt = 0;
my @startingTime;
my $pass_thru = "";
my $show_pass_thru;

# Set this once and we don't have to care about it anymore
$ENV{"LC_ALL"} = "C";

###############################################################################
# MAIN
###############################################################################

startTime();
parseArgs();
setup();
readData();
if ($showtypes) { showTypeData(); exit 0; }
johnPrelims();
if ($internal_testing) { doInternalMode(); }
filterPatterns();
process(0);
cleanup();
displaySummary();
exit $error_cnt+$error_cnt_pot+$ret_val_non_zero_cnt;

###############################################################################
# End of MAIN. Everything from this point on is subroutines.
###############################################################################

###############################################################################
# Here are all of the subroutines that get the job done
###############################################################################

sub startTime {
	@startingTime = gmtime(time);
}

sub displaySummary {
	my @timeEnd = gmtime(time);
	my $secs = timeToSecs(@timeEnd)-timeToSecs(@startingTime);
	if ($error_cnt == 0 && $error_cnt_pot == 0 && $ret_val_non_zero_cnt == 0) {
		if ($done_cnt == 0) { ScreenOutAlways ("NO tests were performed.  Time used was $secs seconds\n"); }
		else { ScreenOutAlways ("All tests passed without error.  Performed $done_cnt tests.  Time used was $secs seconds\n"); }
	} else {
		my $s = "Some tests had Errors. Performed $done_cnt tests.";
		unless ($error_cnt == 0) { $s = $s . "  $error_cnt errors"; }
		unless ($error_cnt_pot == 0) { $s = $s . "  $error_cnt_pot errors reprocessing the .POT files"; }
		unless ($ret_val_non_zero_cnt == 0) { $s = $s . "  $ret_val_non_zero_cnt runs had non-zero return code (cores?)"; }
		ScreenOutAlways ("$s\nTime used was $secs seconds\n");
	}
}

###############################################################################
# parse our command line options.
###############################################################################
sub parseArgs {
	my @passthru=();
	my $help = 0;
	GetOptions(
		'help|?',          => \$help,
		'quiet+'           => \$quiet,
		'verbose+'         => \$verbose,
		'type=s'           => \@types,
		'nontype=s'        => \@nontypes,
		'showtypes'        => \$showtypes,
		'basepath=s'       => \$basepath,
		'prelims!'         => \$prelims,
		'passthru=s'       => \@passthru,
		'stoponerror!'     => \$stop_on_error,
		'showstderr!'      => \$show_stderr,
		'internal!'        => \$internal_testing,
		);
	if ($basepath ne "") {
		$JOHN_PATH = $basepath;
		$JOHN_EXE  = "$JOHN_PATH/john";
		$UNIQUE    = "$JOHN_PATH/unique";
	}
	if ($help) { usage($JOHN_PATH); }
	$verbosity = 2 + $verbose - $quiet;
	setVerbosity($verbosity);
	if (@ARGV) { push @types, @ARGV; }
	foreach my $i (0..$#types) { $types[$i] = lc($types[$i]); }
	foreach my $s (@passthru) { $pass_thru .= " " . $s; }
	$show_pass_thru = $pass_thru;
	$show_pass_thru =~ s/--?fork[=:]\d+ ?//;
}

###############################################################################
# see if we can find a string (i.e. grep) from the usage data
###############################################################################
sub grepUsage {
	foreach my $line(@johnUsageScreen) {
		if (index($line,$_[0]) ge 0) {
			return 1;
		}
	}
	return 0;
}

###############################################################################
# here we do prelim work.  This is the multiple calls to -test=0 which should
# not output ANY error conditions.
###############################################################################
sub johnPrelims {
	return unless $prelims;

	johnTest0_one(" ");
	foreach my $item (@encs) {johnTest0_one($item);}
	if ($verbosity < 2) {ScreenOutSemi(" \n");}
}
sub johnTest0_one {
	if (length($_[0]) < 2 || stringInArray($_[0], @types) || stringInArray("enc", @types) || stringInArray("full", @types)) {
		if (length($_[0]) >= 2) { $_[0] = "--encoding=$_[0]"; }
		ScreenOutSemi("testing: john -test=0 $_[0]\n");
		my $sCmd = "$JOHN_EXE -test=0 $_[0] $pass_thru";
		my $sCmdOut = `$sCmd`;
		my @CmdLines = split (/\n/, $sCmdOut);
		foreach my $line(split (/\n/, $sCmdOut)) {
			if (index($line, "FAILED") ge 0) {
				ScreenOutAlways($line,"\n");
			}
		}
	}
}
###############################################################################
# We parse through the data file, and list the 'types' that can be used,
# removing duplicates, etc.
###############################################################################
sub showTypeData {
	# Get all the 'types'.  NOTE, full/full_only were removed from element 0
	# so we 'add' it to 'seed' the list, and also add base.
	my @typeddata = ("base", "full", "full_only");

	{
		LINE: foreach my $line(@tstdata) {
			my @ar = split(',', $line);
			my $cnt = @ar;
			if ($cnt == 12) {
				my @types = split('\)', $ar[0]);
				my @types_fixed = ();
				TYPE: foreach my $type (@types) {
					$type = substr($type, 1, length($type)-1);
					if ($type eq "full") {ScreenOutVV("(full) found in field0 for $line\n");}
					if (!stringInArray($type, @validFormats)) {
						push(@types_fixed, $type);
					} else {
						ScreenOutVV("Exact format found in field 1 $type\n");
					}
				}
				my %k;
				map { $k{$_} = 1 } @typeddata;
				push(@typeddata, grep { !exists $k{$_} } @types_fixed);
			}
		}
	}
	ScreenOutAlways_ar("\nHere are all of the type values in this test suite:\n", @typeddata);
	ScreenOutAlways_ar("\nThese are the valid formats in this john (also valid as types):\n", @validFormats);

	ScreenOutAlways("\nIf there is no types given, then '-type base -type utf8 -type koi8r'\n");
	ScreenOutAlways("will be the type used if this is a john-jumbo build, and -type full\n");
	ScreenOutAlways("will be used for non-jumbo john (i.e. 'core' john)\n\n");
	ScreenOutAlways("-type full does a test of ALL formats, and all encodings, including the\n");
	ScreenOutAlways("      slower types.\n");
	ScreenOutAlways("-type base tests the formats where tests do not take 'too' much time.\n");
	ScreenOutAlways("      NOTE, base covers most of the formats.\n");
	ScreenOutAlways("      NOTE, full_only will test ONLY the (full) formats.\n");
}
###############################################################################
# Setup the program to run.  Parses through params, strtok's the ./john screen
# output, and also possilby ./john --subformat=LIST (deprecated) or
# ./john --list=subformats and ./john --encoding=LIST to find
# internal 'variable' data built into jumbo, which can be added to, or removed
# over time, and between builds.
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

	# we store a ./john error string to this file.  We will use this data in several ways, later.
	system ("$JOHN_EXE >JohnUsage.Scr 2>&1");
	open(FILE, "<JohnUsage.Scr") or die $!;
	@johnUsageScreen = <FILE>;
	close(FILE);

	ScreenOutAlways("-------------------------------------------------------------------------------\n");
	ScreenOutAlways("- JtR-TestSuite (jtrts). Version $VERSION, $RELEASE_DATE.  By, Jim Fougeron & others\n");
	ScreenOutAlways("- Testing:  $johnUsageScreen[0]"); # note the line ends in a \n, so do not add one.
	ScreenOutAlways("--------------------------------------------------------------------------------\n");
	ScreenOut("\n");

	# now use the john error screen to determine if this is a jumbo john, or
	# a core john. Then use this data to figure out what formats ARE and are NOT
	# able to be run by this build (so we can later skip formats NOT built in
	# this build.  Also check for how to do -utf8 or --encoding=utf8 (different syntax
	# in different builds of john.  Also certain extra options like -nolog may
	# be 'possible'.  We simply parse that screen (and also a john --subformat=LIST to
	# get a list of dynamics, if we are in a jumbo), so we know HOW to proceed.

	ScreenOutVV("John 'usage' data is:\n");
	ScreenOutVV(@johnUsageScreen);

	# can we use -pot=./tst.pot ?
	if (grepUsage("--pot=NAME")) {
		push(@caps, "jumbo");
		push(@caps, "core");  # note, jumbo can do both CORE and JUMBO formats
		ScreenOut("John Jumbo build detected.\n");
	} else {
		push(@caps, "core");  # core john can ONLY do core formats.
		ScreenOut("John CORE build detected.  Only core formats can be tested.\n");
	}
	# load all the format strings we 'can' use.
	loadAllValidFormatTypeStrings();
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
	# can we use --config=./john.conf ?
	if (grepUsage("--config=FILE")) { push(@caps, "config_valid");
		ScreenOutV("--config=FILE option is valid\n");
	}
	# if the --field-sep=value valid?
	if (grepUsage("--field-separator-char=")) {
		push(@caps, "field_sep_valid");
		ScreenOutV("--field-separator-char=C option is valid\n");
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

	# ok, now load the md5's of the all.chr and alnum.chr files. These end up being 'required' types for the inc to run.
	my $file = $JOHN_PATH . "/all.chr";
    if (open(FILE, $file)) {
	    binmode(FILE);
		my $sHash = "inc_all_" . Digest::MD5->new->addfile(*FILE)->hexdigest;
	    close(FILE);
		push(@caps, $sHash);
		ScreenOutV("all.chr found, $sHash added as a capability\n");
	} else {
		ScreenOutV("all.chr ($file) not found\n");
	}
	$file = $JOHN_PATH . "/alnum.chr";
    if (open(FILE, $file)) {
	    binmode(FILE);
		my $sHash = "inc_alnum_" . Digest::MD5->new->addfile(*FILE)->hexdigest;
	    close(FILE);
		push(@caps, $sHash);
		ScreenOutV("alnum.chr found, $sHash added as a capability\n");
	} else {
		ScreenOutV("alnum.chr ($file) not found\n");
	}
	if (@types) {
		ScreenOutV("Types to filter on:\n");
		ScreenOutV(@types);
		ScreenOutV("\n");
	} else {
		# we setup the 'defaults'.  If there are NO types at all, then we do this:
		#  -type full      (core builds)
		#  -t base -t koi8r -t utf8 on john jumbo builds.
		if (stringInArray("jumbo", @caps)) {
			ScreenOutV("Setting default for john-jumbo to be:   base+koi8r+utf8\n");
			push (@types, "base", "koi8r", "utf8");
		} else {
			ScreenOutV("Setting default for john-core to be:   full+core\n");
			push (@types, "core", "full");
		}
	}
	if (@nontypes) {
		ScreenOutV("Types to filter off (non-types):\n");
		ScreenOutV(@nontypes);
		ScreenOutV("\n");
	}
	ScreenOutV("Capabilities in this build of john:\n");
	ScreenOutV(@caps);
	ScreenOutV("\n");
}

###############################################################################
# we parse the JohnUsage.Scr file, for the --format=NAME line, and ALL lines
# up to the next param. We then chop out all of the 'valid' formats which this
# build of john claims to be able to handle.  Then we can later compare when
# running, and simply about a run, if this build does not support it.
# The format of this data is:
#  --format=NAME        force hash type NAME: des/bsdi/md5/bf/afs/lm/trip/
#                       dummy
# NOTE, there may be MANY more.   the format names have varied in case, from
# version to version.  We lowercase them here (and also in the input data file).
###############################################################################
sub loadAllValidFormatTypeStrings {
	my $in_fmt=0;
	my $fmt_str="";
	foreach my $line(@johnUsageScreen) {
		if ($in_fmt == 0) {
			if (index($line, "--format=NAME") == 0) {
				$in_fmt = 1;
				while (substr($line, 0, 1) ne ":") {
					$line = substr($line, 1, length($line)-1);
				}
				$line = substr($line, 2, length($line)-2);
				chomp($line);
				$line =~ s/\r$//;  # strip CR for non-Windows
				$line = $line . '/';
				$line =~ s/ /\//g;
				$fmt_str = $fmt_str . $line;
			}
		} else {
			if (index($line, '-') == 0) { last; }
			while (substr($line, 0, 1) eq " " || substr($line, 0, 1) eq "\t") {
				$line = substr($line, 1, length($line)-1);
			}
			chomp($line);
			$line =~ s/\r$//;  # strip CR for non-Windows
			$line = $line . '/';
			$line =~ s/ /\//g;
			$fmt_str = $fmt_str . $line;
		}
	}
	# strip off the 'final' / char
	$fmt_str = substr($fmt_str, 0, -1);

	# Make all format labels listed from JtR lower case.
	$fmt_str = lc($fmt_str);

	# removed dynamic_n IF it exists
	$fmt_str =~ s/\/dynamic_n//g;

	# Ok, now if we have 'dynamic's, LOAD them
	if (grepUsage("--list=WHAT") || grepUsage("--subformat=LIST")) {
		if (grepUsage("--list=WHAT")) {
			system ("$JOHN_EXE --list=subformats >JohnDynaUsage.Scr 2>/dev/null");
		}
		else {
			system ("$JOHN_EXE --subformat=LIST >JohnDynaUsage.Scr 2>/dev/null");
		}
		open(FILE, "<JohnDynaUsage.Scr") or die $!;
		my @dyna = <FILE>;
		close(FILE);
		unlink("JohnDynaUsage.Scr");
		foreach my $line (@dyna) {
			my @ar = split(/ /, $line);
			if (index($ar[2], "dynamic_") == 0) {
				$fmt_str = $fmt_str . "/" . $ar[2];
			}
		}
	}
	#$fmt_str = $fmt_str . "/inc";
	@validFormats = split(/\//, $fmt_str);
	if (index($fmt_str, "-cuda") != -1)  {
	    push(@caps, "cuda");
	    $prelims = 0;
	}
	if (index($fmt_str, "-opencl") != -1)  {
	    push(@caps, "opencl");
	    $prelims = 0;
	}
	# push (inc), since ALL john versions allow the inc.
	push(@caps, "inc");
	if ($verbosity > 3) {
		my $cnt = @validFormats;
		ScreenOutVV("There are $cnt formats this john build can handle. These are:\n");
		foreach my $line(@validFormats) { ScreenOutVV($line . ","); }
		ScreenOutVV("\n");
	}
}
sub loadAllValidEncodings {
	ScreenOutV("--encoding=LIST is valid, so we get valid encodings from there\n");
	system ("$JOHN_EXE --encoding=LIST >JohnEncUsage.Scr 2>&1");
	open(FILE, "<JohnEncUsage.Scr") or die $!;
	my @encodings = <FILE>;
	close(FILE);
	unlink("JohnEncUsage.Scr");
	my $str;
	foreach my $sline (@encodings) {
		if (index($sline, "Supported ") lt 0) {
			my @encline = split(/, /,$sline);
			foreach my $item (@encline) {
				if (index($item, " ") gt 0) {
					$item = substr($item, 0, index($item, " "));
				}
				if (index($item, ",") gt 0) {
					$item = substr($item, 0, index($item, ","));
				}
				push(@caps, $item);
				push(@encs, $item);
			}
		}
	}
}
###############################################################################
# we read the data file 'jtrts.dat'.  This is a CSV file. It contains lines
# of data, which provide the data, used along with john's capabilities, along
# with the way the user wants to run (the -type and -nontype values).
###############################################################################
sub readData {
	open(FILE, "<jtrts.dat") or die $!;
	my @lines = <FILE>;
	close(FILE);
	foreach my $line(@lines) {
		chomp($line);
		$line =~ s/\r$//;  # strip CR for non-Windows
		if (length($line) > 0 && substr($line, 0, 1) ne "#") {
			#$line = "(*)" . $line;  # we have now added the "base", so there is no reason for this one.
			my @ar = split(',', $line);
			my $cnt = @ar;
			if ($cnt == 12) {
				if (!$showtypes) {
					if (index($ar[0], "($ar[7])") lt 0) {
						$line = "($ar[7])$line";
					}
					$line = "(full)$line";
					if (index($ar[1], "(full)") >= 0) {
						$line = "(full_only)$line";
					}
				}
				push(@tstdata, $line);
			}
		}
	}
	if ($verbosity > 3) {
		my $cnt = @tstdata;
		ScreenOutVV("Running data-dictionary. $cnt items (jtrts.dat):\n");
		foreach my $line(@tstdata) { ScreenOutVV($line . "\n"); }
		ScreenOutVV("\n");
	}
}
###############################################################################
###############################################################################
sub filterPatterns {
	my @filtereddata;
	{
		LINE: foreach my $line(@tstdata) {
			my @ar = split(',', $line);
			my $cnt = @ar;
			my $valid = 'f';
			if ($cnt == 12) {
				# determine if our build of john 'can' do this format:
				if (!stringInArray($ar[7], @validFormats)) {
					ScreenOutVV("Line [$line] filtered out, because format ${ar[7]} can not be processed by this build of john\n");
					next LINE;
				}
				# Now, make sure that this is something 'requested'
				if (!arrayPartInString($ar[0], @types)) {
					ScreenOutVV("Line [$line] filtered out, no requests [$ar[0]] in [@types] were satisfied\n");
					next LINE;
				}
				# Now, make sure that nothing from the is something 'non-requested' is set
				if (arrayPartInString($ar[0], @nontypes)) {
					ScreenOutVV("Line [$line] filtered out. A non request [@types] was found\n");
					next LINE;
				}
				# Now, make sure that ALL of the required types are satisfied.
				# NOTE, if user specified a format, then assume all requirements have also been specified.
				if (!stringInArray($ar[7], @types)) {
					if ($ar[1] ne "(X)") {
						my @reqs = split(/&/,$ar[1]);
						if (stringInArray("full_only", @types) && index($ar[1], "(full)") >= 0) {
							# we want this one!!
						} else {
							$valid = 'f';
							foreach my $req(@reqs) { # note, these are already wrapped in ()
								if (!stringInArray(substr($req, 1, length($req)-2), @types)) {
									ScreenOutVV("Line [$line] filtered out, required option [@reqs] not satisfied in [@types]\n");
									next LINE;
								}
							}
						}
					}
				}
				# Now, make sure that ALL of the required build capacities are satisfied.
				my @reqs = split(/&/,$ar[2]);
				foreach my $req(@reqs) {
					if (!stringInArray(substr($req, 1, length($req)-2), @caps)) {
						ScreenOutVV("Line [$line] filtered out, required build option option [@reqs] not satisfied in [@caps]\n");
						next LINE;
					}
				}

				# OK, make sure the dictionary file 'exists'
				unless (-e "${ar[5]}.dic") {
					if (substr($ar[5],0,10) ne "INCREMENT_") {
						ScreenOutVV("Line [$line] filtered out, because dictionary ${ar[5]}.dic not found\n");
						next LINE;
					}
				}

				# we are going to process this item.  Add it to our filtered array.
				push (@filtereddata, $line);
			}
		}

		# now that we have filtered our data, put it on the 'real' list.
		@tstdata = ();
		for my $line(@filtereddata) { push(@tstdata, $line); }
	}

	if ($verbosity > 3) {
		my $cnt = @tstdata;
		ScreenOutVV("Filtered items from the data-dictionary. $cnt items (jtrts.dat):\n");
		foreach my $line(@tstdata) { ScreenOutVV($line . "\n"); }
		ScreenOutVV("\n");
	}

}

sub ExtraArgs_Run { #($ar[8], $ar[7], $ar[9]);
	#if ($ar[8] eq 'Y') { $cmd = "$cmd -form=$ar[7]"; }
	#if ($ar[9] ne 'X') { $cmd .= "$cmd $ar[9]"; }
	my $ret = "";
	if ($_[0] eq 'Y') { $ret .= " -form=$_[1]"; }
	if ($_[2] ne 'X') {
		if (substr($_[2], 0, 1) eq 'X') {
			$ret .= " ".substr($_[2], 1);
		} else {
			$ret .= " $_[2]";
		}
	}
	return $ret;
}

sub ExtraArgs_Show { #($ar[9]);
	#if ($ar[9] ne 'X') { $cmd .= "$cmd $ar[9]"; }
	my $ret = "";
	if (substr($_[0], 0, 1) ne 'X') {
		$ret .= " $_[0]";
	}
	return $ret;
}

###############################################################################
###############################################################################
sub process {
	my $skip = shift(@_);
	my $pot = "./tst.pot";
	my $pot_opt = "";
	my $cmd_head = "$JOHN_EXE -ses=./tst $pass_thru";
	if ($skip) { $cmd_head .= " -skip" }
	if (stringInArray("nolog_valid", @caps)) { $cmd_head = "$cmd_head -nolog"; }
	#if (stringInArray("config_valid", @caps)) { $cmd_head = "$cmd_head -config=./john.conf"; }
	if (stringInArray("local_pot_valid", @caps)) { $cmd_head .= $pot_opt = " -pot=./tst.pot"; }
	else {
		# handle john 'core' behavior.  We save off existing john.pot, then it is overwritten
		unlink $JOHN_PATH."/john.ptt";
		rename $JOHN_PATH."/john.pot",$JOHN_PATH."/john.ptt";
		$pot = $JOHN_PATH."/john.pot";
	}
	my $dict_name_ex = "";
	my $dict_name = "";
	my $line = "";

	LINE: foreach my $line(@tstdata) {
		my @ar = split(',', $line);
		if (substr($ar[5],0,10) eq "INCREMENT_") {
			$dict_name = "--incremental=" . substr($ar[5],10);
		} else {
			$dict_name = "--wordlist=$ar[5].dic";
		}
		my $cmd = "$cmd_head $ar[6]";
		unless (-e $ar[6]) { next LINE; }
		$done_cnt = $done_cnt + 1;
		if ($ar[3] != 10000) {
			open (FILE, "<".substr($dict_name,11));
			my @lines = <FILE>;
			close(FILE);
			$dict_name = "--wordlist=$ar[5]-$ar[3].dic";
			$dict_name_ex = substr($dict_name,11);
			open (FILE, ">".substr($dict_name,11));
			my $i;
			for ($i = 0; $i < $ar[3]; $i += 1) {
				my $line = shift(@lines);
				if (defined $line) { print FILE $line; }
			}
			close(FILE);
		}
		$cmd = "$cmd $dict_name" . ExtraArgs_Run($ar[8], $ar[7], $ar[9]);
		if ($show_stderr != 1) { $cmd .= " 2>&1 >/dev/null"; }
		# this will switch stderr and stdout (vs joining them), so we can grab stderr BY ITSELF.
		else { $cmd .= " 3>&1 1>&2 2>&3 >/dev/null"; }

		ScreenOutVV("Execute john: $cmd\n");
		unlink($pot);
		my $cmd_data = `$cmd`;
		my $ret_val = $?;
		# ok, now show stderr, if asked to.
		if ($show_stderr == 1) { print $cmd_data; }
		ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");

		my @crack_cnt = split (/\n/, $cmd_data);

		my @crack_xx = ();
		foreach $line (@crack_cnt) {
		    # cut away progress indicator
		    $line =~ s/.*\x08//;
		    # convert to legacy format, take care of --fork=
		    $line =~ s/^(\d+ )?(\d+)g /guesses: $2  /;
		    if (index($line, "guesses:") == 0) {
				# fork will have multiple guess lines.
				if (defined $crack_xx[1] > 0) {
					my @crxx = split (/ /, $line);
					$crack_xx[1] += $crxx[1];
				} else {
					@crack_xx = split (/ /, $line);
				}
		    }
		}
		# convert to legacy format
		if (defined $crack_xx[4]) {
			$crack_xx[4] =~ s/100%/DONE/;
			$crack_xx[4] =~ s/%/%%/;
		}
		while (not defined $crack_xx[1]) { push (@crack_xx, "0"); }
		my $orig_crack_cnt = $crack_xx[1];
		ScreenOutSemi("\n");

		# Ok, get crack count using --show
		my $cmdshow = "$JOHN_EXE -show $show_pass_thru $pot_opt $ar[6] -form=$ar[7]" . ExtraArgs_Show($ar[9]);
		$cmdshow .= " 2>&1";

		ScreenOutVV("Execute john: $cmdshow\n");

		my $cmd_show_data = `$cmdshow`;

		ScreenOutVV("\n\nCmd_show_data = \n$cmd_show_data\n\n");

		my @cmd_show_lines = split(/\n/, $cmd_show_data);
		my $cmd_show_line = $cmd_show_lines[scalar (@cmd_show_lines) - 1];
		if (!defined($cmd_show_line)) { $cmd_show_line = ""; }
		my @orig_show_words =  split(/\s/, $cmd_show_line);
		my $orig_show_cnt = $orig_show_words[0];
		if (!defined($orig_show_cnt)) { $orig_show_cnt = ""; }
		ScreenOutVV("\n\cmd_show_line = \n$cmd_show_line\n\n");

		if (index($ar[10], "($orig_crack_cnt)") lt 0 && index($ar[10], "($orig_show_cnt)") lt 0 && index($ar[10], "(-show$orig_show_cnt)") lt 0) {
			while (not defined $crack_xx[4]) { push (@crack_xx, "unk"); }
			my $str;
			if ($ret_val == 0) {
				$str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED!!!]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
			} else {
				$str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED!!!  return code $ret_val]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
				$ret_val_non_zero_cnt += 1;
			}
			ScreenOutAlways($str);
			# check for self-test failure
			# NOTE other failures should also be looked for, when we 'find' them.
			$error_cnt += 1;
			foreach $line (@crack_cnt) {
				if (index($line, "Self test failed") ge 0) {
					ScreenOutAlways("$line\n");
				}
			}
			if ($stop_on_error) {
				ScreenOut("Exiting on error.  The pot file $pot contains the found data\n");
				$cmd =~ s# 2>&1 >/dev/null##;
				ScreenOut("The command used to run this test was:\n\n$cmd\n");
				exit(1);
			}
		} elsif ($ret_val == 0) {
			if ($orig_crack_cnt != $orig_show_cnt) {
				if (index($ar[10], "(-show$orig_show_cnt)") >= 0) {
					# we are 'ok' here.
					my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_crack_cnt);
					ScreenOutSemi($str);
				} else {
					my $str = sprintf("form=%-28.28s guesses: %4.4s -show=%-4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED!!!]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
					ScreenOutAlways($str);
				}
			} else {
				my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_crack_cnt);
				ScreenOutSemi($str);
			}
		} else {
			my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [pass, but return code $ret_val]\n", $ar[4], $orig_crack_cnt);
			ScreenOutAlways($str);
			$ret_val_non_zero_cnt += 1;
		}
		if ($dict_name_ex ne "") {
			unlink ($dict_name_ex);
		}

		# now do the .pot check.
		if (-f $pot) {
			unlink ("pw3");
			if ($ar[8] eq "\'-fie=\\x1F\'") {
				my $cmd2 = sprintf("cut -f 2- -d\"%c\" -s < $pot | $UNIQUE pw3 > /dev/null", 31);
				system($cmd2);
			} else {
				my $cmd2 = sprintf("cut -f 2- -d: -s < $pot | $UNIQUE pw3 > /dev/null");
				system($cmd2);
			}
			$cmd =~ s/$dict_name/--wordlist=pw3/;

			ScreenOutVV("Execute john (.pot check): $cmd\n");
			unlink ($pot);
			$cmd_data = `$cmd`;
			$ret_val = $?;
			# ok, now show stderr, if asked to.
			if ($show_stderr == 1) { print $cmd_data; }
			ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");

			@crack_xx = ();
			@crack_cnt = split (/\n/, $cmd_data);
			foreach $line (@crack_cnt) {
				# cut away progress indicator
				$line =~ s/.*\x08//;
				# convert to legacy format, take care of --fork=
				$line =~ s/^(\d+ )?(\d+)g /guesses: $2  /;
				if (index($line, "guesses:") == 0) {
					# fork will have multiple guess lines.
					if (defined $crack_xx[1] > 0) {
						my @crxx = split (/ /, $line);
						$crack_xx[1] += $crxx[1];
					} else {
						@crack_xx = split (/ /, $line);
					}
				}
			}
			while (not defined $crack_xx[1]) { push (@crack_xx, "0"); }
			my $orig_pot_cnt = $crack_xx[1];
			while (not defined $crack_xx[4]) { push (@crack_xx, "unk"); }
			$crack_xx[4] =~ s/%/%%/;

			# Ok, get pot count using --show
			my $cmdshow2 = "$JOHN_EXE -show $show_pass_thru $pot_opt $ar[6] -form=$ar[7]" . ExtraArgs_Show($ar[9]);
			$cmdshow2 .= " 2>&1";
			ScreenOutVV("Execute john: $cmdshow2\n");
			my $cmd_show_data2 = `$cmdshow2`;
			# ok, now show stderr, if asked to.
			ScreenOutVV("\n\nCmd_show_data2 = \n$cmd_show_data2\n\n");
			my @cmd_show_lines2 = split(/\n/, $cmd_show_data2);
			my $cmd_show_line2 = $cmd_show_lines2[scalar (@cmd_show_lines2) - 1];
			my @orig_show_words2 =  split(/\s/, $cmd_show_line2);
			my $orig_show_cnt2 = $orig_show_words2[0];
			ScreenOutVV("\n\cmd_show_line2 = \n$cmd_show_line2\n\n");

			if (index($ar[11], "($crack_xx[1])") lt 0 && $orig_pot_cnt ne $orig_crack_cnt && index($ar[10], "($orig_show_cnt2)") lt 0 && index($ar[10], "(-show$orig_show_cnt2)") lt 0) {
				my $str;
				if ($ret_val == 0) {
					$str = sprintf(".pot CHK:%-24.24s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11]  [!!!FAILED!!!]\n", $ar[4], $orig_pot_cnt, $orig_show_cnt2);
				} else {
					$str = sprintf(".pot CHK:%-24.24s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11]  [!!!FAILED!!! return code $ret_val]\n", $ar[4], $orig_pot_cnt, $orig_show_cnt2);
					$ret_val_non_zero_cnt += 1;
				}
				ScreenOutAlways($str);
				$error_cnt_pot += 1;
				if ($stop_on_error) {
					ScreenOut("Exiting on error (reporcessing original .pot file).\n The pot file $pot contains the found data\n");
					ScreenOut("The command used to run this test was:\n\n$cmd\n");
					exit(1);
				}
			} elsif ($ret_val == 0) {
				my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_pot_cnt);
				ScreenOutSemi($str);
			} else {
				my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [pass, but return code $ret_val]\n", $ar[4], $orig_pot_cnt);
				ScreenOutAlways($str);
				$ret_val_non_zero_cnt += 1;
			}
			unlink("$pot");
			unlink("pw3");
		}
	}
	ScreenOutSemi("\n");
	if (!stringInArray("local_pot_valid", @caps)) {
		# handle john 'core' behavior.  then we delete the pot we just made, then rename the 'saved' version.
		unlink $JOHN_PATH."/john.pot";
		rename $JOHN_PATH."/john.ptt",$JOHN_PATH."/john.pot";
	}
}

###############################################################################
# cleanup temp files, etc
###############################################################################
sub cleanup {
	unlink ("JohnUsage.Scr");
	unlink ("tst.pot");
	unlink ("tst.log");
	unlink ("tst.ses");
	unlink ("selftest.dic");
	unlink ("selftest.in");
}

###############################################################################
# Internal mode. This will generate a file from the format itself
# using:
#    john -format=$fmt -list=format-tests | cut -f3 > selftest.in
#    john -format=$fmt -list=format-tests | cut -f4 > selftest.dic
# this function does not return, it cleans up, and exits with proper errorlevel.
###############################################################################
sub doInternalMode {
	if (grepUsage("--pot=NAME")) {
		# we are OK, we run only on jumbo mode.
	} else {
		ScreenOut("John CORE build detected.\n The -internal mode ONLY works for jumbo build of john.\n");
		exit 1;
	}
	ScreenOutSemi("Running JTRTS in -internal mode\n");
	ScreenOutVV("\@validFormats\n");
	ScreenOutVV(@validFormats);
	ScreenOutVV("\n\n\@types  (before fixups)\n");
	ScreenOutVV(@types);
	if (scalar @types == 3 && $types[0] eq "base" && $types[1] eq "koi8r" && $types[2] eq "utf8") {
		@types = @validFormats;
	} else {
		# handle finding 'classes' here, such as $types[x] == "dynamic", then find all dynamic
		# also handle other wildcard stuff.  Make sure that these types work:
		# dynamic, cpu, gpu, cuda, opencl also wildcards.  Probably also encodings.
	}

	ScreenOutVV("\n\n\@types  (after fixups)\n");
	ScreenOutVV(@types);
	ScreenOutVV("\n\n\@nontypes\n");
	ScreenOutVV(@nontypes);

	# now process the internal stuff.
	foreach my $type (@types) {
		my $doit = 1;
		# handle finding 'classes' here, such as $types[x] == "dynamic", then find all dynamic
		# also handle other wildcard stuff.  Make sure that these types work:
		# dynamic, cpu, gpu, cuda, opencl also wildcards.
		foreach my $nontype (@nontypes) {
			my $s = $type;
			if ($s =~ m/$nontype/) {
				$doit = 0;
			}
		}

		# make sure we have this type as a valid type in JtR
		my @match = grep { /^$type$/ } @validFormats;
		ScreenOutVV("\n\nsearch of type in validFormats resulted in:\n");
		ScreenOutVV("type=[$type] match=[\@match]\n");
		if (scalar(@match) == 0) { $doit = 0; }

		if ($doit == 1) {
			# first, build our dictionary
			my $cmd = "$JOHN_EXE -format=$type -list=format-tests $show_pass_thru 2>&1 | cut -f 4 > selftest.dic";
			$cmd = `$cmd`;
			# Now build the input file
			$cmd = "$JOHN_EXE -format=$type -list=format-tests $show_pass_thru 2>&1 | cut -f3 > selftest.in";
			$cmd = `$cmd`;
			my $cnt = `wc -l selftest.in | awk \'{print \$1}\'`;
			chomp $cnt;
			# build the @tstdata array with 1 element
			@tstdata = ("($type),(X),(jumbo),10000,$type,selftest,selftest.in,$type,Y,X,($cnt)(-show$cnt),($cnt)");
			ScreenOutVV("Preparing to run internal for type: $type\n");
			process(1);
		}
	}

	cleanup();
	displaySummary();
	exit $error_cnt+$error_cnt_pot+$ret_val_non_zero_cnt;
}
