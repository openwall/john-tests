#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use jtrts_inc;
use Digest::MD5;
use MIME::Base64;
use List::Util qw/shuffle/;

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
my %formatDetails=();
my @tstdata;
my $showtypes=0, my $basepath=""; my $prelims=0, my $stop_on_error=0, my $show_stderr=0; my $randomize = 0;
my $last_line_len=0; my $internal_testing=0; my $hash_case_mangle=0; my $ignore_full=0;
my $error_cnt = 0, my $error_cnt_pot = 0; my $done_cnt = 0; my $ret_val_non_zero_cnt = 0;
my @startingTime;
my $pass_thru = "";
my $show_pass_thru;
my $rand_seed = 31337;
my $core_only = 0;

# Set this once and we don't have to care about it anymore
$ENV{"LC_ALL"} = "C";

# Speed up OpenCL for short runs/many salts. Do not touch if already set.
if (!defined($ENV{"LWS"})) { $ENV{"LWS"} = "8"; }
if (!defined($ENV{"GWS"})) { $ENV{"GWS"} = "64"; }

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

sub randstr {
	my @chr = ('.','/','0'..'9','A'..'Z','a'..'z');
	my $s="";
	foreach (1..$_[0]) { $s.=$chr[rand @chr]; }
	return $s;
}

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
	my $err = GetOptions(
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
		'case_mangle!'     => \$hash_case_mangle,
		'random!'          => \$randomize,
		'ignore_full!'     => \$ignore_full,
		'seed=n'           => \$rand_seed
		);
	if ($err == 0) {
		print "exiting, due to invalid option\n";
		exit 1;
	}
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
sub LoadFormatDetails {
	# build the formatDetails hash (1 time)
	my $res = `$JOHN_EXE $show_pass_thru -list=format-details`;
	my @details = split ("\n", $res);
	foreach my $detail (@details) {
		my @indiv = split("\t", $detail);
		$formatDetails {lc $indiv[0]} = $detail;
	}
}
sub StopOnError {
	my $cmd=$_[0]; my $pot=$_[1];
	if ($stop_on_error) {
		ScreenOut("Exiting on error. The .pot file $pot contains the found data\n");
		$cmd =~ s# 2>&1 >/dev/null##;
		ScreenOut("The command used to run this test was:\n\n$cmd\n");
		exit(1);
	}
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
		my $sCmd = "$JOHN_EXE -test=0 $_[0] $pass_thru";
		ScreenOutSemi("testing: $sCmd\n");
		$sCmd .= " 2>/dev/null";
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
	my @formatswedo = ();

	{
		LINE: foreach my $line(@tstdata) {
			my @ar = split(',', $line);
			my $cnt = @ar;
			if ($cnt == 12) {
				if (stringInArray($ar[7], @validFormats) && !stringInArray($ar[7], @formatswedo)) {
					push(@formatswedo, $ar[7]);
				}
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
	ScreenOutAlways_ar("\nThese are the formats jtrts processes (also valid as types):\n", sort @formatswedo);

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
		LoadFormatDetails();
	} else {
		push(@caps, "core");  # core john can ONLY do core formats.
		ScreenOut("John CORE build detected.  Only core formats can be tested.\n");
		$core_only = 1;
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
				if (index($line, ":") < 0) {
					# new format layout does not use format names on usage
					# screen. The new method forces us to use --list=formats
					my @ar = `$JOHN_EXE --list=formats`;
					foreach $line (@ar) {
						chomp $line; $line =~ s/\r$//;
						$line =~ s/, /\//g;
						$fmt_str = $fmt_str . $line;
					}
				} else {
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
			system ("$JOHN_EXE $show_pass_thru --list=subformats >JohnDynaUsage.Scr 2>/dev/null");
		}
		else {
			system ("$JOHN_EXE $show_pass_thru --subformat=LIST >JohnDynaUsage.Scr 2>/dev/null");
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
		# now that $prelims is NOT default, if the user wants them, the user can have them.
	    #$prelims = 0;
	}
	if (index($fmt_str, "-opencl") != -1)  {
	    push(@caps, "opencl");
	    #$prelims = 0;
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
						if ((stringInArray("full_only", @types)||$ignore_full) && index($ar[1], "(full)") >= 0) {
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
sub is_format_8bit {
	my $type = $_[0];
	my @details = split("\t", $formatDetails{$type});
	my $_8bit = hex($details[4]) & 0x00000002; # check for FMT_8_BIT
	return $_8bit;
}
sub stripHi {
	my $is_8bit = $_[1];
	return if ($core_only || $is_8bit);
	my @chars = split(//, $_[0]);
	for (my $i = 0; $i < length($_[0]); ++$i) {
		if (ord($chars[$i]) > ord('~')) { $chars[$i] = chr(ord($chars[$i])-0x80); }
	}
	$_[0] = join('', @chars);
}
my $sub_cnt=0;
sub pot_match_pass {
	# line will be "password  (password)"  or something else.
	my $line = $_[0];
	my $is_8bit = $_[1];
	chomp $line;
	#print "$line\n";
	stripHi($line, $is_8bit);
	if (substr($line, length($line)-1, 1) ne ")" || index($line, " (") < 0) { return 1; }
	if (index($line, "Loaded ") == 0) { return 1; }
	if (index($line, "Will run ") == 0 && index($line, "OpenMP") > 0) { return 1; }
	if (index($line, "Node numbers ") == 0) { return 1; }
	my $idx = index($line, " (");
	my $s = substr($line, $idx+2);
	$s = substr($s, 0, length($s)-1);
	#return substr($line, 0, length($s)) eq $s;
	#if (index($line, $s) == 0) { $sub_cnt+=1; print "*** good $sub_cnt\n"; return 2;}
	if (index($line, $s) == 0) { return 2;}
	ScreenOutV("FAILED line = $_[0]\n");
	return 0;
}
sub create_file_if_not_exist {
	my $filename = $_[0];
	if (-e $filename) { return; }
	open(FILE, ">".$filename);
	#print FILE "\n";
	close(FILE);
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
		if ($randomize || $ar[3] != 10000) {
			open (FILE, "<".substr($dict_name,11));
			my @lines = <FILE>;
			close(FILE);
			$dict_name = "--wordlist=$ar[5]-$ar[3].dic";
			$dict_name_ex = substr($dict_name,11);
			if ($ar[3] != 10000) {
				@lines = @lines[0 .. ($ar[3] - 1)];
			}
			if ($randomize) {
				# Add some extra lines before we shuffle. This makes sure that
				# we have lines of each length (the file has all up to 18 already)
				srand($rand_seed);
				my $L1 = randstr(136);
				my $i;
				if ($ar[3] != 10000) {
					for ($i = 18; $i < 134; $i += 3) {
						push @lines, substr($L1, 0, $i)."\n";
					}
				} else {
					my $L2 = randstr(136); my $L3 = randstr(136);
					my $L4 = randstr(136); my $L5 = randstr(136); my $L6 = randstr(136);
					for ($i = 18; $i < 136; ++$i) {
						push @lines, substr($L1, 0, $i)."\n"; push @lines, substr($L2, 0, $i)."\n";
						push @lines, substr($L3, 0, $i)."\n"; push @lines, substr($L4, 0, $i)."\n";
						push @lines, substr($L5, 0, $i)."\n"; push @lines, substr($L6, 0, $i)."\n";
					}
				}
				@lines = shuffle @lines;
			}
			open (FILE, ">".substr($dict_name,11));
			while ($#lines >= 0) {
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
		# we create the .pot file. This is a work around for a known issue in vboxfs fs
		# under virtualbox using -fork=n mode. If the file is there (even empty), then
		# forking locking works. If the file is not there, locking will 'see' multiple
		# files many times (depending upon race conditions). This is a bug in virtualbox
		# vm's, but this works around it, and cause no other side effects for other OS's.
		create_file_if_not_exist($pot);
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
		ScreenOutVV("Execute john: $cmdshow\n");
		$cmdshow .= " 2>/dev/null";

		my $cmd_show_data = `$cmdshow`;

		ScreenOutVVV("\n\nCmd_show_data = \n$cmd_show_data\n\n");

		my @cmd_show_lines = split(/\n/, $cmd_show_data);
		my $cmd_show_line = $cmd_show_lines[scalar (@cmd_show_lines) - 1];
		if (!defined($cmd_show_line)) { $cmd_show_line = "0 FAKE line"; }
		my @orig_show_words =  split(/\s/, $cmd_show_line);
		my $orig_show_cnt = $orig_show_words[0];
		if (!defined($orig_show_cnt)) { $orig_show_cnt = "0"; }
		ScreenOutVV("\n\cmd_show_line = \n$cmd_show_line\n\n");

		if (index($ar[10], "($orig_crack_cnt)") lt 0 && index($ar[10], "($orig_show_cnt)") lt 0 && index($ar[10], "(-show$orig_show_cnt)") lt 0) {
			while (not defined $crack_xx[4]) { push (@crack_xx, "unk"); }
			my $str;
			if ($ret_val == 0) {
				$str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED1!!!]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
			} else {
				$str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED2!!!  return code $ret_val]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
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
			StopOnError($cmd, $pot);
		} elsif ($ret_val == 0) {
			if ($orig_crack_cnt != $orig_show_cnt) {
				if (index($ar[10], "(-show$orig_show_cnt)") >= 0 || index($ar[10], "($orig_show_cnt)") >= 0) {
					# we are 'ok' here. Display show count.
					my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_show_cnt);
					ScreenOutSemi($str);
				} else {
					my $str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED3!!!]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
					ScreenOutAlways($str);
					$error_cnt += 1;
					StopOnError($cmd, $pot);
				}
			} else {
				my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_crack_cnt);
				ScreenOutSemi($str);
			}
		} else {
			if (!defined $crack_xx[3]) {ScreenOutAlways("\n");}
			my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [pass, but return code $ret_val]\n", $ar[4], $orig_crack_cnt);
			ScreenOutAlways($str);
			$ret_val_non_zero_cnt += 1;
			StopOnError($cmd, $pot);
		}
		if ($dict_name_ex ne "") {
			unlink ($dict_name_ex);
		}

		# now do the .pot check.
		if (-f $pot) {
			open(POTFILE,  $pot);
			my @pot_lines = <POTFILE>;
			close(POTFILE);
			unlink ("tst.in");
			open(NEWFILE, ">> tst.in");
			foreach my $line (@pot_lines) {
				chomp $line;
				my @elems = split(":", $line);
				if (scalar @elems == 2) {
					print NEWFILE "$elems[1]:$elems[0]\n";
				} else {
					print NEWFILE ":$elems[0]\n";
				}
			}
			close(NEWFILE);
			unlink ("pw3");
			my $cmd2 = sprintf("cut -f 2- -d: -s < $pot | $UNIQUE pw3 > /dev/null");
			system($cmd2);
			$cmd2 = $cmd;
			$cmd2 =~ s/$dict_name/--wordlist=pw3/;
			$cmd2 =~ s/$ar[6]/tst.in/;
			$cmd2 =~ s/2>&1 >\/dev\/null/2>_stderr/;

			ScreenOutVV("Execute john (.pot check): $cmd2\n");
			unlink ($pot);
			create_file_if_not_exist($pot);
			$cmd_data = `$cmd2`;
			open (FILE, "_stderr");
			my @stde = <FILE>;
			close(FILE);
			foreach my $s (@stde) { $cmd_data .= $s; }
			unlink ("_stderr");
			$ret_val = $?;

			# ok, now show stderr, if asked to.
			if ($show_stderr == 1) { print $cmd_data; }
			ScreenOutVV("\n\nCmd_data = \n$cmd_data\n\n");

			@crack_xx = ();
			@crack_cnt = split (/\n/, $cmd_data);
			my $invalid_pass = 0;
			my $valid_pass = 0;
			my $is_8bit = is_format_8bit($ar[7]);
			foreach $line (@crack_cnt) {
				#print ("line = $line\n");
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
				#ok, see if this is a password crack line, if so make
				#sure the PW 'matches' what it is supposed to be
				my $v = pot_match_pass($line, $is_8bit);
				if (!$v) {
					$invalid_pass += 1;
				} elsif ($v == 2) {
					$valid_pass += 1;
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
			ScreenOutVVV("\n\nCmd_show_data2 = \n$cmd_show_data2\n\n");
			my @cmd_show_lines2 = split(/\n/, $cmd_show_data2);
			my $cmd_show_line2 = $cmd_show_lines2[scalar (@cmd_show_lines2) - 1];
			my @orig_show_words2 =  split(/\s/, $cmd_show_line2);
			my $orig_show_cnt2 = $orig_show_words2[0];
			ScreenOutVV("\n\cmd_show_line2 = \n$cmd_show_line2\n$invalid_pass invalid passwords\n$valid_pass valid passwords\n\n");

			if (index($ar[11], "($crack_xx[1])") lt 0 && $orig_pot_cnt ne $orig_crack_cnt && index($ar[10], "($orig_show_cnt2)") lt 0 && index($ar[10], "(-show$orig_show_cnt2)") lt 0 || $invalid_pass != 0) {
				my $str;
				if ($ret_val == 0 || $invalid_pass != 0) {
					$str = sprintf(".pot CHK:%-24.24s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11]  [!!!FAILED4!!!]  ($valid_pass val-pwd  $invalid_pass inval-pwd)\n", $ar[4], $orig_pot_cnt, $orig_show_cnt2);
				} elsif ($invalid_pass != 0) {
					$str = sprintf(".pot CHK:%-24.24s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11] INVALID cracks=$invalid_pass  [!!!FAILED5!!!]\n", $ar[4], $orig_pot_cnt, $orig_show_cnt2);
				} else {
					$str = sprintf(".pot CHK:%-24.24s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11]  [!!!FAILED6!!! return code $ret_val]\n", $ar[4], $orig_pot_cnt, $orig_show_cnt2);
					$ret_val_non_zero_cnt += 1;
				}
				ScreenOutAlways($str);
				$error_cnt_pot += 1;
				StopOnError($cmd, $pot);
			} elsif ($ret_val == 0) {
				my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED] ($valid_pass val-pwd)\n", $ar[4], $orig_pot_cnt);
				ScreenOutSemi($str);
			} else {
				my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [pass, but return code $ret_val]\n", $ar[4], $orig_pot_cnt);
				ScreenOutAlways($str);
				$ret_val_non_zero_cnt += 1;
				StopOnError($cmd, $pot);
			}
			unlink("$pot");
			unlink("pw3");
			unlink("tst.in");
		}
	}
	# in -internal mode, we do not want the extra \n
	if (!$skip) { ScreenOutSemi("\n"); }
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
	unlink ("pw-10000.dic");
}

###############################################################################
###############################################################################
sub PossibleCaseMangle1 {
	my ($hash, $case, $ch, $force) = @_;
	my $ch1 = "\\".$ch;
	my @ar = split /$ch1/, $hash, 100;
	my $cnt; my $cnt2;
	$cnt = 0;
	foreach my $item (@ar) {
		my $len = length($item);
		if ($len == 16 || $len == 32 || $len == 40 || $len == 48 || $len == 56 || $len == 64 ||
		    $len == 80 || $len == 96 || $len == 104 || $len == 112 || $len == 128) {
			# possible hex sizes.  See if this field is 'pure' hex
			my $s = unpack("H*",pack("H*",$item));
			my $useit = 1;
			if ($force) {
				if ($case eq "uprcase" && uc $s eq $item) { $useit = 0; }
				elsif ($case eq "lowcase" && lc $s eq $item) { $useit = 0; }
			}
			if ($useit == 1 && lc $s eq lc $item) {
				#found one
				$cnt2 = 0;
				my $ret = "";
				foreach $item (@ar) {
					if ($cnt == $cnt2) {
						if    ($case eq "uprcase") { $item = uc $item; }
						elsif ($case eq "lowcase") { $item = lc $item; }
					}
					$ret .= $item . $ch;
					$cnt2 += 1;
				}
				# trim possible redundant trailing $ch value.
				if (length($ret) -1 == length($hash)) { $ret = substr($ret, 0, length($ret)-1); }
				return $ret."\n";
			}
		}
		$cnt += 1;
	}
	return "";
}
sub PossiblyCaseMangle {
	my ($hash, $up, $force) = @_;
	my $val = PossibleCaseMangle1($hash, $up, "\$", $force);
	if (length($val) == 0) { $val = PossibleCaseMangle1($hash, $up, "*", $force); }
	if (length($val) == 0) { $val = PossibleCaseMangle1($hash, $up, "#", $force); }
	if (length($val) == 0) { $val = PossibleCaseMangle1($hash, $up, ".", $force); }
	if (length($val) == 0) { $val = PossibleCaseMangle1($hash, $up, ":", $force); }
	if (length($val) == 0) {
		#, ok, there are a couple of FMT_SPLIT_UNI hashes, which have both HEX
		# and base-64 hashes (pbkdf2-hmac-sha1, raw-sha256 and raw-sha256-ng at
		# the time of this comment. So to work around these, I look for valid
		# base-64 hash here (if in non-$force mode). If I do find that string
		# then return the original hash, instead of "";
		if (not $force) {
			if (substr($hash, 0, 9) eq "{PKCS5S2}" || substr($hash, 0, 6) eq '$p5k2$') {
				# base64 hashes from pbkdf2-hmac-sha1
				return $hash."\n";
			}
			if (substr($hash, 0, 8) eq '$cisco4$' || (length($hash) == 43 && length(decode_base64($hash)) == 32) ) {
				# base64 hashes from raw-sha256
				return $hash."\n";
			}
		}
		return "";
	}
	return $val;
}
sub does_hash_split_unifies_case {
	my $type = $_[0];
	my $mangle = 0;
	if ($hash_case_mangle) {
		my @details = split("\t", $formatDetails{$type});
		$mangle = hex($details[4]) & 0x00020000; # check for FMT_SPLIT_UNIFIES_CASE
	}
	return $mangle;
}
sub is_hash_salted {
	my $type = $_[0];
	my @details = split("\t", $formatDetails{$type});
	return $details[11] > 0;
}
sub build_self_test_files {
	my $type = $_[0];
	my $cnt = 0;
	my $mangle = does_hash_split_unifies_case($type);
	my $cmd = "$JOHN_EXE -format=$type -list=format-tests $show_pass_thru 2>/dev/null";
	my $results = `$cmd`;
	ScreenOutVV("results from '$cmd' = \n$results\n\n");
	my @ar1 = split("\n", $results);
	open (FILE1, "> selftest.in") || die "problem creating selftest.in\n";
	open (FILE2, "> selftest.dic") || die "problem creating selftest.dic\n";
	# output some long format 'tester' input words.  We might improve this with time.
	# sizes I could see:  55, 56, 64, 65, 80, 81, 119, 120, 125, 126 bytes long.
	print FILE2 "12345678901234567890123456789012345678901234567890123456789012345678901234567890\n";
	print FILE2 "123456789012345678901234567890123456789012345678901234567\n";
	print FILE2 "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890\n";
	foreach my $line (@ar1) {
		my @dtls = split("\t", $line);
		if (scalar (@dtls) >= 3) {
			print FILE1 $dtls[2]."\n";
			if (defined $dtls[3]) { print FILE2 $dtls[3]; }
			print FILE2 "\n";
			if ($cnt < 3) {
				print FILE2 "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234\n";
			}
			if ($hash_case_mangle) {
				print FILE1 PossiblyCaseMangle($dtls[2], "uprcase", not $mangle);
				print FILE1 PossiblyCaseMangle($dtls[2], "lowcase", not $mangle);
			}
			$cnt += 1;
		}
	}
	close(FILE2); close(FILE1);
	DumpFileVV("selftest.dic"); DumpFileVV("selftest.in");
	return $cnt;
}
###############################################################################
# Internal mode. This will generate a file from the format itself
# using:
#    john -format=$fmt -list=format-tests | cut -f3 > selftest.in
#    john -format=$fmt -list=format-tests | cut -f4 > selftest.dic
# this function does not return, it cleans up, and exits with proper errorlevel.
###############################################################################
sub doInternalMode {
	if ($core_only == 0) {
		ScreenOut("John CORE build detected.\n The -internal mode ONLY works for jumbo build of john.\n");
		exit 1;
	}

	ScreenOutSemi("Running JTRTS in -internal mode\n");
	if ($hash_case_mangle) {ScreenOutSemi("Running hash case manging mode\n");}
	ScreenOutVV("\@validFormats\n");
	ScreenOutVV(@validFormats);
	ScreenOutVV("\n\n\@types  (before fixups)\n");
	ScreenOutVV(@types);
	if (scalar @types == 3 && $types[0] eq "base" && $types[1] eq "koi8r" && $types[2] eq "utf8") {
		@types = @validFormats;
	} else {
		my @newtypes;
		foreach my $type (@types) {
			ScreenOutVV("Looking for $type\n\n");
			my $cmd = "$JOHN_EXE -list=formats -format=$type $show_pass_thru 2>/dev/null";
			my $ret_types = `$cmd`;
			ScreenOutVV("$cmd returned $ret_types\n\n");
			$ret_types =~ s/\n//g;
			$ret_types =~ s/ //g;
			my @typesarr = split(",", $ret_types);
			foreach $type (@typesarr) { push (@newtypes, lc $type); }
		}
		# uniq newtypes
		my %seen = ();
		@newtypes = grep { ! $seen{ $_ }++ } @newtypes;
		@types = sort(@newtypes);
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
		ScreenOutVV("type=[$type] match=[@match]\n");
		if (scalar(@match) == 0) { $doit = 0; }

		if ($doit == 1) {
			# first, build our dictionary/input files
			my $cnt = build_self_test_files($type);
			# build the @tstdata array with 1 element
			if (does_hash_split_unifies_case($type)) {
				my $cnt3 = $cnt*3;
				@tstdata = ("($type),(X),(jumbo),10000,$type,selftest,selftest.in,$type,Y,X,($cnt)(-show$cnt3),($cnt)");
			} else {
				@tstdata = ("($type),(X),(jumbo),10000,$type,selftest,selftest.in,$type,Y,X,($cnt)(-show$cnt),($cnt)");
			}
			ScreenOutV("Preparing to run internal for type: $type\n");
			ScreenOutV("tstdata = @tstdata\n\n");
			process(1);
		}
	}

	cleanup();
	displaySummary();
	exit $error_cnt+$error_cnt_pot+$ret_val_non_zero_cnt;
}
