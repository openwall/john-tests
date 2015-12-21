#!/usr/bin/perl -w
use strict;
use Getopt::Long;
use jtrts_inc;
use Digest::MD5;
use MIME::Base64;
use List::Util qw/shuffle/;
use Storable;

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
my $UNIQUE    = "$JOHN_PATH/unique -mem=20";
my $verbosity  = 2;
my @types=();
my @nontypes=();
my @caps=();
my @encs=();
my @johnUsageScreen=();
my @validFormats=();
my %formatDetails=();
my %opts=(line_num => 0);
my @tstdata;
my $show_stderr=0;
my $last_line_len=0;
my $error_cnt = 0; my $error_cnt_pot = 0; my $done_cnt = 0; my $ret_val_non_zero_cnt = 0;
my $dyanmic_wanted="normal";
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
setup();     # this function taks a while!!
readData();
if (defined $opts{showtypes} && $opts{showtypes} > 0) { showTypeData(); unlink_restore(); exit 0; }
johnPrelims();
if (defined $opts{internal} && $opts{internal} > 0) { doInternalMode(); unlink_restore(); }
if (defined $opts{restore} && $opts{restore} > 0)  { doRestoreMode(); unlink_restore(); }
filterPatterns();
process(0);
cleanup();
unlink_restore();
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
		'type=s'         ,#  => \@types,
		'nontype=s'      ,#  => \@nontypes,
		'showtypes'      ,#  => \$showtypes,
		'basepath=s'     ,#  => \$basepath,
		'dynamic=s'      ,#  => \$dyanmic_wanted,
		'prelims!'       ,#  => \$prelims,
		'passthru=s'     ,#  => \@passthru,
		'stoponerror!'   ,#  => \$stop_on_error,
		'showstderr!'    ,#  => \$show_stderr,
		'internal!'      ,#  => \$internal_testing,
		'restore!'       ,#  => \$restore_testing,
		'resume!'            => \$resume,
		'case_mangle!'   ,#  => \$hash_case_mangle,
		'random!'        ,#  => \$randomize,
		'ignore_full!'   ,#  => \$ignore_full,
		'seed=n'         ,#  => \$rand_seed
		);
	if ($err == 0) {
		print "exiting, due to invalid option\n";
		exit 1;
	}
	if ($help) { usage($JOHN_PATH); }
	if (@ARGV) {$opts{argv} = \@ARGV; }
	if ($resume != 0) { ResumeState(); $opts{resume}=1; }
	else { SaveState(); }

	if (defined $opts{argv})        {@ARGV              = @{$opts{argv}}; }
	if (defined $opts{type})        {@types             = split /\s+/, $opts{type}; }
	if (defined $opts{nontype})     {@nontypes          = split /\s+/, $opts{nontype}; }
	if (defined $opts{dynamic})     {$dyanmic_wanted    = $opts{dynamic}; }
	# not sure why needed, but it is. The only think I can see is that the passthru
	# object starts with a '-' character. But if we leave it in strict mode perl
	# exits out trying to handle the next expression.
	if (defined $opts{passthru})    {@passthru          = split /\s+/, $opts{passthru}; }
	if (defined $opts{showstderr})  {$show_stderr       = $opts{showstderr}; }
	if (defined $opts{seed})        {$rand_seed         = $opts{seed}; }

	if (defined $opts{basepath}) {
		$JOHN_PATH = $opts{basepath};
		$JOHN_EXE  = "$JOHN_PATH/john";
		$UNIQUE    = "$JOHN_PATH/unique -mem=20";
	}
	$verbosity = 2;
	if (defined $opts{verbose}) { $verbosity += $opts{verbose} }
	if (defined $opts{quiet})   { $verbosity -= $opts{quiet} }
	setVerbosity($verbosity);
	if (@ARGV) { push @types, @ARGV; }
	foreach my $i (0..$#types) { $types[$i] = lc($types[$i]); }
	foreach my $s (@passthru) { $pass_thru .= " " . $s; }
	$pass_thru =~ s/--?sa[ve\-mory]*[=:]\d+ ?//;  # save memory is simply not allowed in the TS.
	$show_pass_thru = $pass_thru;
	$show_pass_thru =~ s/--?fork[=:]\d+ ?//;
	$show_pass_thru =~ s/--?mkpc?[=:]\d+ ?//;
	$show_pass_thru =~ s/--?sk[ip\-selft]* ?//;
	$show_pass_thru =~ s/--?max-r[un\-time]*[=:]\d+ ?//;
	# --dupe-suppression on GPU builds or on CPU builds:
	$show_pass_thru =~ s/--?du[pe\-surion]* ?//;
	# a possible --dupe-suppression abbreviation on noAn-GPU builds,
	# this will drop the abbreviated option if followed by other options:
	$show_pass_thru =~ s/--?d //;
	# this will drop --d at the end of -passthru="...":
	$show_pass_thru =~ s/--?d$//;
	$show_pass_thru =~ s/--?me[mfile\-sz]*[=:]\d+ ?//;
	$show_pass_thru =~ s/--?fix[\-staedly]*[=:]\d+ ?//;
	$show_pass_thru =~ s/--?pro[gres\-vry]*[=:]\d+ ?//;
	# --rules=none might help to find UbSan or ASan bugs in rpp.c,
	# that's why drop that for --show as well, just in case
	$show_pass_thru =~ s/--?ru[les]*[:=]?[^\s]* ?//;
}

sub ResumeState {
	%opts = %{retrieve('jtrts.resume')};
}
sub SaveState {
	store \%opts, 'jtrts.resume';
}
sub unlink_restore {
	unlink ('jtrts.resume');
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
	$res .= `$JOHN_EXE $show_pass_thru -list=format-details -format=dynamic-all`;
	my @details = split ("\n", $res);
	foreach my $detail (@details) {
		my @indiv = split("\t", $detail);
		if (scalar @indiv > 12) {
			$formatDetails {lc $indiv[0]} = $detail;
		}
	}
}
sub StopOnError {
	my $cmd=$_[0]; my $pot=$_[1]; my $show=$_[2];
	if (defined $opts{stoponerror} && $opts{stoponerror} > 0) {
		ScreenOut("Exiting on error. The .pot file $pot contains the found data\n");
		$cmd =~ s# 2>&1##;
		$cmd =~ s# 2?>/dev/null##g;
		$cmd =~ s# 2>_stderr##g;
		$show =~ s# 2>&1##;
		$show =~ s# 2?>/dev/null##g;
		$show =~ s# 2>_stderr##g;
		ScreenOut("The command used to run this test was:\n\n$cmd\n");
		if (length($show) > 0) {ScreenOut("and\n$show\n");}
		my $str = `grep Terminating tst-.log`;
		if (length($str)>0) { print "\nFrom tst-.log file:\n$str\n"; }
		exit(1);
	}
}
###############################################################################
# here we do prelim work.  This is the multiple calls to -test=0 (-test-full=0
# for jumbo) which should not output ANY error conditions.
###############################################################################
sub johnPrelims {
	return unless ( defined $opts{prelims} && $opts{prelims}>0 );
	johnTest0_one(" ");
	foreach my $item (@encs) {johnTest0_one($item);}
	if ($verbosity < 2) {ScreenOutSemi(" \n");}
}
sub johnTest0_one {
	if (length($_[0]) < 2 || stringInArray($_[0], @types) || stringInArray("enc", @types) || stringInArray("full", @types)) {
		if (length($_[0]) >= 2) { $_[0] = "--encoding=$_[0]"; }
		my $sCmd;
		if ($core_only == 1) {
			$sCmd = "$JOHN_EXE -test=0 $_[0] $pass_thru";
		} else {
			$sCmd = "$JOHN_EXE -test-full=0 $_[0] $pass_thru";
		}
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
# Setup the program to run.  Parses through params, strtok's the john screen
# output, and also possilby john --subformat=LIST (deprecated) or
# john --list=subformats and john --encoding=LIST to find
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

	# we store a john error string to this file.  We will use this data in several ways, later.
	system ("$JOHN_EXE >tst-JohnUsage.Scr 2>&1");
	open(FILE, "<tst-JohnUsage.Scr") or die $!;
	@johnUsageScreen = <FILE>;
	close(FILE);
	unlink ("tst-JohnUsage.Scr");

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

	# can we use -pot=tst-.pot ?
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
	# can we use --config=john.conf ?
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
	if (grepUsage("--regex=")) {
		push(@caps, "regex");
		ScreenOutV("--regex mode exists\n");
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
# we parse the tst-JohnUsage.Scr file, for the --format=NAME line, and ALL lines
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
	if ($in_fmt) { $fmt_str = substr($fmt_str, 0, -1); }

	# Make all format labels listed from JtR lower case.
	$fmt_str = lc($fmt_str);

	# removed dynamic_n IF it exists
	$fmt_str =~ s/\/dynamic_n//g;

	# Ok, now if we have 'dynamic's, LOAD them
	if ($dyanmic_wanted ne "none") {
		if (grepUsage("--list=WHAT") || grepUsage("--subformat=LIST")) {
			my $more = 1;
			if ($dyanmic_wanted eq "all") {
				system ("$JOHN_EXE $show_pass_thru --list=formats --format=dynamic-all >JohnDynaUsage.Scr 2>/dev/null");
				open(FILE, "<JohnDynaUsage.Scr") or die $!;
				my @dyna = <FILE>;
				close(FILE);
				unlink("JohnDynaUsage.Scr");
				if (defined($dyna[0]) && substr($dyna[0], 0, 10) eq "dynamic_0,") {
					$more = 0;
					foreach my $line (@dyna) {
						chomp $line;
						$line =~ s/\r$//;
						$line =~ s/,//g;
						my @ar = split(/ /, $line);
						foreach my $item (@ar) {
							$fmt_str = $fmt_str . "/" . $item;
						}
					}
				}
			}
			if ($more > 0) {
				if (grepUsage("--list=WHAT")) {
					system ("$JOHN_EXE $show_pass_thru --list=subformats >JohnDynaUsage.Scr 2>/dev/null");
				}
				else {
					system ("$JOHN_EXE $show_pass_thru --subformat=LIST >JohnDynaUsage.Scr 2>/dev/null");
				}
				system ("$JOHN_EXE $show_pass_thru --subformat=LIST >JohnDynaUsage.Scr 2>/dev/null");
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
		}
	}
	#$fmt_str = $fmt_str . "/inc";
	@validFormats = split(/\//, $fmt_str);
	if (index($fmt_str, "-cuda") != -1)  {
	    push(@caps, "cuda");
	}
	if (index($fmt_str, "-opencl") != -1)  {
	    push(@caps, "opencl");
	}
	# push (inc), since ALL john versions allow the inc.
	push(@caps, "inc");
	if ($verbosity > 3) {
		my $cnt = @validFormats;
		ScreenOutVVV("There are $cnt formats this john build can handle. These are:\n");
		foreach my $line(@validFormats) { ScreenOutVVV($line . ","); }
		ScreenOutVVV("\n");
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
				if (!defined $opts{showtypes} || $opts{showtypes}==0) {
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
		ScreenOutVVV("Running data-dictionary. $cnt items (jtrts.dat):\n");
		foreach my $line(@tstdata) { ScreenOutVVV($line . "\n"); }
		ScreenOutVVV("\n");
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
					ScreenOutVVV("Line [$line] filtered out, because format ${ar[7]} can not be processed by this build of john\n");
					next LINE;
				}
				# Now, make sure that this is something 'requested'
				if (!arrayPartInString($ar[0], @types)) {
					ScreenOutVVV("Line [$line] filtered out, no requests [$ar[0]] in [@types] were satisfied\n");
					next LINE;
				}
				# Now, make sure that nothing from the is something 'non-requested' is set
				if (arrayPartInString($ar[0], @nontypes)) {
					ScreenOutVVV("Line [$line] filtered out. A non request [@types] was found\n");
					next LINE;
				}
				# Now, make sure that ALL of the required types are satisfied.
				# NOTE, if user specified a format, then assume all requirements have also been specified.
				if (!stringInArray($ar[7], @types)) {
					if ($ar[1] ne "(X)") {
						my @reqs = split(/&/,$ar[1]);
						if ((stringInArray("full_only", @types)||(defined $opts{ignore_full} && $opts{ignore_full} > 0)) && index($ar[1], "(full)") >= 0) {
							# we want this one!!
						} else {
							$valid = 'f';
							foreach my $req(@reqs) { # note, these are already wrapped in ()
								if (!stringInArray(substr($req, 1, length($req)-2), @types)) {
									ScreenOutVVV("Line [$line] filtered out, required option [@reqs] not satisfied in [@types]\n");
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
						ScreenOutVVV("Line [$line] filtered out, required build option option [@reqs] not satisfied in [@caps]\n");
						next LINE;
					}
				}

				# OK, make sure the dictionary file 'exists'
				unless (-e "${ar[5]}.dic") {
					if (substr($ar[5],0,10) ne "INCREMENT_") {
						ScreenOutVVV("Line [$line] filtered out, because dictionary ${ar[5]}.dic not found\n");
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
		ScreenOutVVV("Filtered items from the data-dictionary. $cnt items (jtrts.dat):\n");
		foreach my $line(@tstdata) { ScreenOutVVV($line . "\n"); }
		ScreenOutVVV("\n");
	}

}

sub ExtraArgs_Run { #($ar[8], $ar[7], $ar[9]);
	#if ($ar[8] eq 'Y') { $cmd = "$cmd -form=$ar[7]"; }
	#if ($ar[9] ne 'X') { $cmd .= "$cmd $ar[9]"; }
	my $ret = "";
	if ($_[0] eq 'Y' || substr($_[1],0,8) eq "dynamic_") { $ret .= " -form=$_[1]"; }
	if ($core_only) { return $ret; }
	if ($_[2] ne 'X') {
		my $x = "";
		if (substr($_[2], 0, 1) eq 'X') {
			$x = substr($_[2], 1);
		} else {
			$x = $_[2];
		}
		my @a = split('\|', $x);
		$ret .= " " . $a[0];
	}
	return $ret;
}

sub ExtraArgs_RunPot { #($ar[8], $ar[7], $ar[9]);
	#if ($ar[8] eq 'Y') { $cmd = "$cmd -form=$ar[7]"; }
	#if ($ar[9] ne 'X') { $cmd .= "$cmd $ar[9]"; }
	my $ret = "";
	if ($_[0] eq 'Y' || substr($_[1],0,8) eq "dynamic_") { $ret .= " -form=$_[1]"; }
	if ($core_only) { return $ret; }
	if ($_[2] ne 'X') {
		my $x = "";
		if (substr($_[2], 0, 1) eq 'X') {
			$x = substr($_[2], 1);
		} else {
			$x = $_[2];
		}
		my @a = split('\|', $x);
		if (scalar(@a) > 1) {
			$ret .= " " . $a[1];
		}
		#if (index($ret, "-enc") < 0) {
		#	$ret .= " -enc=utf8";
		#}
	}
	return $ret;
}

sub ExtraArgs_Show { #($ar[9]);
	#if ($ar[9] ne 'X') { $cmd .= "$cmd $ar[9]"; }
	my $ret = "";
	if ($core_only) { return $ret; }
	if (substr($_[0], 0, 1) ne 'X') {
		my @a = split('\|', $_[0]);
		$ret .= " " . $a[0];
	}
	return $ret;
}
sub is_format_8bit {
	my $type = $_[0];
	my $details = $formatDetails{$type};
	if (!defined($details)) { return 0; }
	my @details = split("\t", $details);
	if (scalar @details < 5) { return 0; }
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
	if (index($line, "guesses: ") == 0) { return 1; }
	if (index($line, "../run/john") == 0) { return 1; }
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
sub exit_cause {
	my ($ret_val) = @_;
	my $exit_cause = "";

	if ($ret_val & 128) {
		$exit_cause = sprintf("segfault, signal %d%s", $ret_val & 127,
				      $ret_val & 128 ? " (core dumped)" : "");
	} else {
		$exit_cause = sprintf("exited, return code %d", $ret_val >> 8);
	}
	return $exit_cause;
}

sub process {
	my $skip = shift(@_);
	my $pot = "tst-.pot";
	my $pot_opt = "";
	my $line_num = 0;
	my $cmd_head = "$JOHN_EXE -ses=tst- $pass_thru";
	if ($skip) { $cmd_head .= " -skip" }
	if (stringInArray("nolog_valid", @caps)) { $cmd_head = "$cmd_head -nolog"; }
	#if (stringInArray("config_valid", @caps)) { $cmd_head = "$cmd_head -config=john.conf"; }
	if (stringInArray("local_pot_valid", @caps)) { $cmd_head .= $pot_opt = " -pot=tst-.pot"; }
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
		# start of -resume code (pretty trivial, I just count line#'s)
		unlink $pot;
		unlink "tst-.log";
		unlink "tst-.rec";
		++$line_num;
		if (defined $opts{resume} && $opts{resume} > 0 && defined $opts{line_num}) {
			if ($line_num < $opts{line_num}) {
				ScreenOutV("resuming. Skipping line $line_num = $line\n");
				next LINE;
			}
		}
		# end of -resume code.

		# mark that we are starting a new line. If we crash here,
		# a -resume picks up where we left off, i.e. on this test.
		$opts{line_num} = $line_num;
		SaveState();

		my @ar = split(',', $line);
		if (substr($ar[5],0,10) eq "INCREMENT_") {
			$dict_name = "--incremental=" . substr($ar[5],10);
		} else {
			$dict_name = "--wordlist=$ar[5].dic";
		}
		my $cmd = "$cmd_head $ar[6]";
		unless (-e $ar[6]) { next LINE; }
		$done_cnt = $done_cnt + 1;
		if ((defined $opts{random} && $opts{random} > 0) || $ar[3] != 10000) {
			open (FILE, "<".substr($dict_name,11));
			my @lines = <FILE>;
			close(FILE);
			$dict_name = "--wordlist=tst-$ar[5]-$ar[3].dic";
			$dict_name_ex = substr($dict_name,11);
			if ($ar[3] != 10000) {
				@lines = @lines[0 .. ($ar[3] - 1)];
			}
			if (defined $opts{random} && $opts{random} > 0) {
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
		my $runtime_err = index($cmd_data, "runtime error") != -1;

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
		my $cmdshow = "$JOHN_EXE -show $show_pass_thru $pot_opt $ar[6] -form=$ar[7]" . ExtraArgs_Show($ar[9]) . " 2>/dev/null";
		ScreenOutVV("Execute john: $cmdshow\n");

		my $cmd_show_data = `$cmdshow`;
		if (!$runtime_err) { $runtime_err = index($cmd_show_data, "runtime error") != -1; }

		ScreenOutVVV("\n\nCmd_show_data = \n$cmd_show_data\n\n");

		my @cmd_show_lines = split(/\n/, $cmd_show_data);
		my $cmd_show_line = $cmd_show_lines[scalar (@cmd_show_lines) - 1];
		if (!defined($cmd_show_line)) { $cmd_show_line = "0 FAKE line"; }
		my @orig_show_words =  split(/\s/, $cmd_show_line);
		my $orig_show_cnt = $orig_show_words[0];
		if (!defined($orig_show_cnt)) { $orig_show_cnt = "0"; }
		ScreenOutVV("\n\cmd_show_line = \n$cmd_show_line\n\n");

		if ($runtime_err || (index($ar[10], "($orig_crack_cnt)") lt 0 && index($ar[10], "($orig_show_cnt)") lt 0 && index($ar[10], "(-show$orig_show_cnt)") lt 0)) {
			while (not defined $crack_xx[4]) { push (@crack_xx, "N/A"); }
			my $str;
			if ($ret_val == 0) {
				$str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED1!!!]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
			} else {
				$str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED2!!! %s]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt, exit_cause($ret_val));
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
			StopOnError($cmd, $pot, $cmdshow);
		} elsif ($ret_val == 0) {
			while (not defined $crack_xx[4]) { push (@crack_xx, "N/A"); }
			if ($orig_crack_cnt != $orig_show_cnt) {
				if (index($ar[10], "(-show$orig_show_cnt)") >= 0 || index($ar[10], "($orig_show_cnt)") >= 0) {
					# we are 'ok' here. Display show count.
					my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_show_cnt);
					ScreenOutSemi($str);
				} else {
					my $str = sprintf("form=%-28.28s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[10]  [!!!FAILED3!!!]\n", $ar[4], $orig_crack_cnt, $orig_show_cnt);
					ScreenOutAlways($str);
					$error_cnt += 1;
					StopOnError($cmd, $pot, $cmdshow);
				}
			} else {
				my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED]\n", $ar[4], $orig_crack_cnt);
				ScreenOutSemi($str);
			}
		} else {
			if (!defined $crack_xx[3]) {ScreenOutAlways("\n");}
			while (not defined $crack_xx[4]) { push (@crack_xx, "N/A"); }
			my $str = sprintf("form=%-28.28s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [pass, but %s]\n", $ar[4], $orig_crack_cnt, exit_cause($ret_val));
			ScreenOutAlways($str);
			$ret_val_non_zero_cnt += 1;
			StopOnError($cmd, $pot, $cmdshow);
		}
		if ($dict_name_ex ne "") {
			unlink ($dict_name_ex);
		}

		# now do the .pot check.
		if (-f $pot) {
			open(POTFILE,  $pot);
			my @pot_lines = <POTFILE>;
			close(POTFILE);
			unlink ("tst-tst.in");
			open(NEWFILE, ">> tst-tst.in");
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
			unlink ("tst-pw3");
			my $cmd2 = sprintf("cut -f 2- -d: -s < $pot | $UNIQUE tst-pw3 > /dev/null");
			system($cmd2);

			$cmd2 = $cmd;
			# NOTE, we may not be able to harvest off $cmd.  We may have different run args for a .pot re-check.
			# this was seen were we use -encode=raw
			$cmd2 =~ s/$dict_name/--wordlist=tst-pw3/;
			$cmd2 =~ s/$ar[6]/tst-tst.in/;
			$cmd2 =~ s/2>&1 >\/dev\/null//;
			$cmd2 =~ s/[\-]+fork=[0-9]+ //;

# went back to original method, and have scrapped this ExtraArgs_RunPot() stuff since we now
# have john-local.pot that removes the utf8 default crap.

#			$cmd2 rebuilt.  We force -enc=utf8, and simply rebuild, vs re-using original $cmd.
#			Also, we 'X' out the original. We likely need to change this.
			#$cmd2 = "$cmd_head tst.in --wordlist=pw3 " . ExtraArgs_RunPot($ar[8], $ar[7], $ar[9]);
			if ($show_stderr != 1) { $cmd2 .= " 2>_stderr"; }
			# this will switch stderr and stdout (vs joining them), so we can grab stderr BY ITSELF.
			else { $cmd2 .= " 3>&1 1>&2 2>&3 >/dev/null"; }

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
			my $is_8bit = 0;
			if ($core_only == 0) { $is_8bit = is_format_8bit($ar[7]); }
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
			while (not defined $crack_xx[4]) { push (@crack_xx, "N/A"); }
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
					$str = sprintf(".pot CHK:%-24.24s guesses: %4.4s -show=%4.4s $crack_xx[3] $crack_xx[4] : Expected count(s) $ar[11]  [!!!FAILED6!!! %s]\n", $ar[4], $orig_pot_cnt, $orig_show_cnt2, exit_cause($ret_val));
					$ret_val_non_zero_cnt += 1;
				}
				ScreenOutAlways($str);
				$error_cnt_pot += 1;
				StopOnError($cmd2, $pot, $cmdshow2);
			} elsif ($ret_val == 0) {
				my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [PASSED] ($valid_pass val-pwd)\n", $ar[4], $orig_pot_cnt);
				ScreenOutSemi($str);
			} else {
				my $str = sprintf(".pot CHK:%-24.24s guesses: %4.4s $crack_xx[3] $crack_xx[4]  [pass, but %s]\n", $ar[4], $orig_pot_cnt, exit_cause($ret_val));
				ScreenOutAlways($str);
				$ret_val_non_zero_cnt += 1;
				StopOnError($cmd, $pot, $cmdshow2);
			}
			unlink("$pot");
			unlink("tst-pw3");
			unlink("tst-tst.in");
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
	unlink glob('tst-*');
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
	if (defined $opts{case_mangle} && $opts{case_mangle} > 0) {
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
	open (FILE1, "> tst-.in") || die "problem creating tst-.in\n";
	open (FILE2, "> tst-.dic") || die "problem creating tst-.dic\n";
	# output some long format 'tester' input words.  We might improve this with time.
	# sizes I could see:  55, 56, 64, 65, 80, 81, 119, 120, 125, 126 bytes long.
	print FILE2 "12345678901234567890123456789012345678901234567890123456789012345678901234567890\n";
	print FILE2 "123456789012345678901234567890123456789012345678901234567\n";
	print FILE2 "123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890\n";
	foreach my $line (@ar1) {
		my @dtls = split("\t", $line);
		if (scalar (@dtls) >= 3) {
			if ($dtls[2] !~ m/:/) { $dtls[2] = "vec_" . $dtls[1] . ":" . $dtls[2]; }
			print FILE1 $dtls[2]."\n";
			if (defined $dtls[3]) { print FILE2 $dtls[3]; }
			print FILE2 "\n";
			if ($cnt < 3) {
				print FILE2 "1234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234567890123456789012345678901234\n";
			}
			if (defined $opts{case_mangle} && $opts{case_mangle} > 0) {
				print FILE1 PossiblyCaseMangle($dtls[2], "uprcase", not $mangle);
				print FILE1 PossiblyCaseMangle($dtls[2], "lowcase", not $mangle);
			}
			$cnt += 1;
		}
	}
	close(FILE2); close(FILE1);
	DumpFileVV("tst-.dic"); DumpFileVV("tst-.in");
	return $cnt;
}
###############################################################################
# Internal mode. This will generate a file from the format itself
# using:
#    john -format=$fmt -list=format-tests | cut -f3 > tst-.in
#    john -format=$fmt -list=format-tests | cut -f4 > tst-.dic
# this function does not return, it cleans up, and exits with proper errorlevel.
###############################################################################
sub doInternalMode {
	if ($core_only == 1) {
		ScreenOut("John CORE build detected.\n The -internal mode ONLY works for jumbo build of john.\n");
		exit 1;
	}

	ScreenOutSemi("Running JTRTS in -internal mode\n");
	if (defined $opts{case_mangle} && $opts{case_mangle} > 0) {
		ScreenOutSemi("Running hash case manging mode\n");
	}
	ScreenOutVVV("\@validFormats\n");
	ScreenOutVVV(@validFormats);
	ScreenOutVVV("\n\n\@types  (before fixups)\n");
	ScreenOutVVV(@types);
	if (scalar @types == 3 && $types[0] eq "base" && $types[1] eq "koi8r" && $types[2] eq "utf8") {
		@types = @validFormats;
	} else {
		my @newtypes;
		foreach my $type (@types) {
			ScreenOutVV("Looking for $type\n");
			my $cmd = "$JOHN_EXE -list=formats -format=$type $show_pass_thru 2>/dev/null";
			ScreenOutVV("Running:  $cmd\n");
			my $ret_types = `$cmd`;
			ScreenOutVV("$cmd returned $ret_types\n");
			$ret_types =~ s/\n//g;
			$ret_types =~ s/ //g;
			ScreenOutVV("fixed ret_types = $ret_types\n");
			my @typesarr = split(",", $ret_types);
			ScreenOutVV("typesarr=@typesarr\n\n");
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
		ScreenOutVVV("\n\nsearch of type in validFormats resulted in:\n");
		ScreenOutVVV("type=[$type] match=[@match]\n");
		if (scalar(@match) == 0) { $doit = 0; }

		if ($doit == 1) {
			# first, build our dictionary/input files
			my $cnt = build_self_test_files($type);
			# build the @tstdata array with 1 element
			if (does_hash_split_unifies_case($type)) {
				my $cnt3 = $cnt*3;
				@tstdata = ("($type),(X),(jumbo),10000,$type,tst-,tst-.in,$type,Y,X,($cnt)(-show$cnt3),($cnt)");
			} else {
				@tstdata = ("($type),(X),(jumbo),10000,$type,tst-,tst-.in,$type,Y,X,($cnt)(-show$cnt),($cnt)");
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

###############################################################################
# Restore mode. This function does the actual restore 'test'. There are several
# types of restore test, so a common function was written to do any of them.
###############################################################################
sub doOneRestore {
	my ($type, $dic, $hashes, $cnt, $runtime, $form, $exargs) = @_;

	ScreenOutSemi("\nRunning JTRTS in \'$type Mode\' -restore mode (against a $cnt candidate $form input file)\n  ** NOTE: may take a couple minutes to run\n");
	my $cmd = "$JOHN_EXE -ses=tst- $pass_thru $exargs $dic $hashes -pot=tst-.pot -max-run=$runtime -form=$form 2>&1";
	ScreenOutV("Running initial command.  Cmd line:\n\n$cmd\n\n");
	my $results = `$cmd`;
	my $ret = $?;
	ScreenOutVV("Results of this run are: $results\n return code [".($ret>>8)."]\n\n");
	if ($verbosity > 1) { show_eta($results); }
	$cmd = "$JOHN_EXE -res=tst- 2>&1";
	while ( ($ret>>8) == 1) {
		ScreenOutV("Continuing session.  Cmd line: $cmd\n");
		$results = `$cmd`;
		$ret = $?;
		`stty echo >/dev/null 2>/dev/null`;
		ScreenOutVV("Results of this run are: $results\n return code [".($ret>>8)."]\n\n");
		if ($verbosity > 1) { show_eta($results); }
	}
	# now compute if we got them all.
	$results = `LC_ALL='C' sort tst-.pot | LC_ALL='C' uniq | LC_ALL='C' wc -l`;
	chomp $results;
	print ("Done with run.  Results (should be $cnt) : $results   ");

	if ($results != $cnt) {
		print "FAIL!\n";
		exit 1;
	}
	if ($error_cnt+$error_cnt_pot+$ret_val_non_zero_cnt != 0) {
		print "Some error status.\n";
		exit 1;
	}
	print "PASS\n";
	cleanup();
}
###############################################################################
# Restore mode. This will run john for X seconds at a time, then restore the
# session and keep restoring, until 'done'.  Once done, we process the .pot file
# the same way, making sure we have the expected values.
#
# this function does not return, it cleans up, and exits with proper errorlevel.
# when it calls doOneRestore, that function can also exit, returning errorlevel.
###############################################################################
sub doRestoreMode {
	if ($core_only == 1) {
		ScreenOut("John CORE build detected.\n The -max-run-time mode ONLY works for jumbo build of john.\n");
		exit 1;
	}
	cleanup();

	# now test pure mask
	doOneRestore("Pure Mask", "", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "-mask=1111[12]?d?d?d");

	# now test wordlist + mask.
	doOneRestore("Wordlist+Mask", "-w=bitcoin_restart_rules_tst.dic", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "-mask=?w?d?d");

	if (stringInArray("regex", @caps)) {
		# now test pure rexgen mode. DISABLED - PURE REGEX HAS NO RESUME YET
		#doOneRestore("Pure RexGen", "-regex=1111[1-2][0-9][0-9][0-9]", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "");

		# now test wordlist + rexgen mode.
		doOneRestore("Wordlist+RexGen", "-w=bitcoin_restart_rules_tst.dic", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "-regex=\\\\0[0-9][0-9]");
	}

	# now test markov.
	doOneRestore("Markov", "-markov", "markov_resume_tst.in", 2000, 20, "bitcoin", "");

	# now test markov+mask.
	doOneRestore("Markov", "-markov", "markov_mask_resume_tst.in", 2000, 20, "bitcoin", "-mask:?w?d?d");

	# now test wordlist
	# grow the tst-pw-new.dic file from pw file using rules:
	my $cmd = "$JOHN_EXE -rules=appendNumNum --stdout --w=bitcoin_restart_rules_tst.dic > tst-pw-new.dic 2>/dev/null";
	$cmd = `$cmd`;
	doOneRestore("Wordlist", "-w=tst-pw-new.dic", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "");
	unlink("tst-pw-new.dic");

	# now test wordlist + rules.
	doOneRestore("Wordlist+Rules", "-w=bitcoin_restart_rules_tst.dic", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "-rules=appendNumNum");

	# now test wordlist + rules + mask.
	doOneRestore("Wordlist+Rules+Mask", "-w=bitcoin_restart_rules_tst.dic", "bitcoin_restart_rules_tst.in", 2000, 40, "bitcoin", "-rules=appendNum -mask=?w?d");
	`echo "1111"> tst-pw-new.dic`;
	doOneRestore("Wordlist+Rules+Mask #2", "-w=tst-pw-new.dic", "bitcoin_restart_rules_tst.in", 2000, 20, "bitcoin", "-rules=append12Num -mask=?w?d?d");
	unlink("tst-pw-new.dic");

	# now test single mode.
	doOneRestore("Single", "-single", "bitcoin_restart_single_tst.in", 2000, 20, "bitcoin", "");

	exit 0;
}

#use String::Scanf;
sub show_eta {
	#my $tot = 0; my $cnt = 0; my $jnk; my $jnk2; my $val;
	my $results = $_[0];
	my @ar = split("\n", $results);
	foreach my $str (@ar) {
		if (index($str, "ETA") > 0 && index($str, "\.\.") > 0) {
			ScreenOut ($str."\n");
			#$cnt += 1;
			#($jnk, $val, $jnk2) = sscanf("%d %dg %s", $str);
			#$tot += $val;
		}
	}
	#if ($cnt > 1) { ScreenOut("cur total: $tot\n"); }
}
