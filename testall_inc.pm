package testall_inc;
use strict;
use warnings;
use Exporter;

my $last_line_len = 0;
my $quiet = "";

our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( usage ScreenOut ScreenOutSemi ScreenOutAlways ScreenOutV ScreenOutVV setquiet stringInArray arrayPartInString );

# these are exported by default.
our @EXPORT = qw( usage ScreenOut ScreenOutSemi ScreenOutAlways ScreenOutV ScreenOutVV setquiet stringInArray arrayPartInString );

sub setquiet {
	$quiet = $_[0];
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
    -quiet     <s> 4 'valid' values for <s>  q, qq, v and vv. q is pretty
                   quiet, qq is very quiet. in qq mode, the only screen
                   output is errors.  v is more verbose, and vv is very
                   verbose.
    -type      <s> Provide selection criteria.
                   Examples:
                     -type1 dynamic_0    This will test this 1 format
                     -type1 utf8         tests all formats with -utf8
                     -type1 nt -type2 utf8  NT format, but ONLY utf8
	               N can be 1, 2, 3 or 4.  Thus, you can provide 4
	               selection criteria
    -non_type  <s> Provide negative selection criteria.  Thus, we will
                   not process any formats containing this type.
    -showtypes     Show the possible values that can be used for -typeN
                   or -nontypeN options, and required types.
    -basepath  <s> set the basepath where john exe is located. By default 
                   this is set to $_[0]
    -prelims       Perform (and optionally show), the prelim testing (encoding).
	-noprelims     Do not perform this prelim work.
    -help|?        shows this help screen.
UsageHelp
}

###############################################################################
# Here are the Screen IO routines. These all interrelate with each other, and
# are used in DIFFERENT type situations. So, for normal output of walking the
# testings, we may output using ScreenOutSemi.  In this mode, if running under
# 'qq, we output nothing.  If in 'q', we output the one line mode, with \r to
# overwrite the prior line.  Otherwise it outputs 'normally'.  These multiple
# 'modes' allows us to better control screen output. There are quiet's and 
# verboses's.  Thus, we can tell the script how quiet, or how verbose to be,
# and the output will be tailored to that request.
###############################################################################

# this is the 'normal' screen output
sub ScreenOut {
	if ($quiet ne 'qq' && $quiet ne 'q') {
		print "$_[0]";
		$last_line_len = 0;
		if (length($_[0]) && substr($_[0], length($_[0])-1, 1) eq '\n') {
			$last_line_len = length($_[0]);
		}
	}
}
# this screen output output 1 line, and overwrite it, if in 'q' quiet mode. In 'qq' it will 
# output nothing.  In 'normal mode', it will call ScreenOut
sub ScreenOutSemi {
	if ($quiet eq 'qq') { return; }
	if ($quiet eq 'q') {
		printf ("\r%$last_line_len.${last_line_len}s\r", " ");
		my $s = $_[0];
		chomp $s;
		print $s;
		$last_line_len = length($s);
		print "\r";
	} else { ScreenOut($_[0]); }
}
# output to screen no matter what mode we are in.  This is used to show
# errors. Either script not setup or called right, OR a test failure error.
sub ScreenOutAlways {
	print "$_[0]";
	$last_line_len = 0;
	if (length($_[0]) && substr($_[0], length($_[0])-1, 1) eq '\n') {
		$last_line_len = length($_[0]);
	}
}

# print verbose 'v' messages
# also able to print array's (debugging shit).
sub ScreenOutV {
	if ($quiet eq 'v' || $quiet eq 'vv') {
		print "@_";
		$last_line_len = 0;
		if (length($_[0]) && substr($_[0], length($_[0])-1, 1) eq '\n') {
			$last_line_len = length($_[0]);
		}
	}
}

# print verbose 'vv' messages
# also able to print array's (debugging shit).
sub ScreenOutVV {
	if ($quiet eq 'vv') {
		print "@_";
		$last_line_len = 0;
		if (defined($_[0]) && length($_[0]) && substr($_[0], length($_[0])-1, 1) eq '\n') {
			$last_line_len = length($_[0]);
		}
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
1;