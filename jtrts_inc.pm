package jtrts_inc;
use strict;
use warnings;
use Exporter;

my $last_line_len = 0;
my $verbosity;

our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( usage ScreenOut ScreenOutSemi ScreenOutAlways ScreenOutV ScreenOutVV
                     setVerbosity stringInArray arrayPartInString timeToSecs ScreenOutAlways_ar );

# these are exported by default.
our @EXPORT = qw( usage ScreenOut ScreenOutSemi ScreenOutAlways ScreenOutV ScreenOutVV
                  setVerbosity stringInArray arrayPartInString timeToSecs ScreenOutAlways_ar );

sub setVerbosity {
	$verbosity = $_[0];
}

###############################################################################
# -? -help, or some failed option selected.  Show the usage screen.
###############################################################################
sub usage {
die <<"UsageHelp";

JtR TestSuite, command usage:

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
                   -q -v together is a no-op.
    -type      <s> Provide selection criteria.
                   Examples:
                     -type1 dynamic_0    This will test this 1 format
                     -type1 utf-8         tests all formats with -utf-8
                     -type1 nt -type2 utf-8  NT format, but ONLY utf-8
                   N can be 1, 2, 3 or 4.  Thus, you can provide 4
                   selection criteria.  NOTE, any 'left over' command
                   line params, get shoved into a 'type'.
    -nontype   <s> Provide negative selection criteria.  Thus, we will
                   not process any formats containing this type.
    -showtypes     Show the possible values that can be used for -typeN
                   or -nontypeN options, and required types.
    -prelims       Perform (and optionally show), the prelim testing (encoding).
                   in 'full' mode, all encodings are tested.  normally, only
                   -test=0 and tests of any 'requested' encodings is performed.
    -no-prelims    Do not perform this prelim work. -no-prelim is default.
    -passthru  <s> Pass this argument straight into john.  Can use more than 1.
    -stoponerror   Causes JtRts to stop if any error is seen.  The .pot file
                   and other temp files will be left, AND the command line
                   that was run is listed. (default is -nostoponerror).
    -showstderr    Allows any stderr writing to 'show' on screen. Usually not
                   wanted, but for some usage, like memory leak checking, or
                   other errors, any display of stderr is needed.
    -help|?        shows this help screen.
UsageHelp
}

###############################################################################
# Here are the Screen IO routines. These all interrelate with each other, and
# are used in DIFFERENT type situations. So, for normal output of walking the
# testings, we may output using ScreenOutSemi.  In this mode, if running under
# 'qq, we output nothing.  If in 'q', we output the one line mode, with \r to
# overwrite the prior line.  Otherwise it outputs 'normally'.  These multiple
# 'modes' allows us to better control screen output. There are verbosity's and
# verboses's.  Thus, we can tell the script how verbose to be, and the output
# will be tailored to that request.
###############################################################################

# this is the 'normal' screen output
sub ScreenOut {
	if ($verbosity >= 2) {
		print "@_";
		$last_line_len = 0;
	}
}
# this screen output output 1 line, and overwrite it, if in 'q' quiet mode. In 'qq' it will
# output nothing.  In 'normal mode', it will call ScreenOut
sub ScreenOutSemi {
	if ($verbosity < 1) { return; }
	if ($verbosity == 1) {
		printf ("\r%$last_line_len.${last_line_len}s\r", " ");
		my $s = $_[0];
		chomp $s;
		print $s;
		$last_line_len = length($s);
		print "\r";
	} else { ScreenOut(@_); }
}
# output to screen no matter what mode we are in.  This is used to show
# errors. Either script not setup or called right, OR a test failure error.
sub ScreenOutAlways {
	print "@_";
	$last_line_len = 0;
}

sub ScreenOutAlways_ar {
	my $len = length($_[0]);
	if (substr($_[0], length($_[0])-1, 1) eq "\n") { $len = 0; }
	print shift;
	my $first = 1;
	my $s;
	foreach $s (@_) {
		if ($len + length($s) + 2 > 78) { print("\n"); $len = 0; }
		if ($len && !$first) {
			print ", $s";
			$len += length($s)+2;
		} else {
			print "  $s";
			$len += length($s)+2;
		}
		$first = 0;
	}
	if ($len) { print "\n"; }
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

sub stringInArray {
	my $str = shift;
	foreach my $elem(@_) {
		if ($str eq $elem) {
			return 1;
		}
	}
	return 0;
}
sub arrayPartInString {
	my $str = shift;
	foreach my $elem(@_) {
		if (index($str, "($elem)") ge 0) {
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
1;
