package jtr_rulez;
use strict;
use warnings;
use Exporter;

my $debug = 0;
my $failed = 0;
my $rejected = 0;
my $rules_max_length;
my $l;

our @ISA= qw( Exporter );

# these CAN be exported.
our @EXPORT_OK = qw( debug failed rejected jtr_run_rule jtr_dbg_level jtr_rule_pp_init jtr_rule_pp_next );

# these are exported by default.
our @EXPORT = qw( jtr_run_rule  jtr_dbg_level jtr_rule_pp_init jtr_rule_pp_next );

my $M="";
my %cclass=(); load_classes();
my @pp_rules=();
my $pp_idx=-0;

sub dbg {
	my $d = shift;
	if ($debug >= $d) {
		foreach my $s (@_) {
			print $s;
		}
	}
}

sub jtr_dbg_level {
	$debug = $_[0];
}

sub case_all_words { # turn john or "JOHn THE ruppor$$abc" into "John The Ruppor$$Abc"
	my $w = lc $_[0];
	$w =~ s/\b(\w)/\U$1/g;
	return $w;
}
sub case { # turn john or JOHn into John or JOHn THE ruppor$$abc" into "John the ruppor$$abc"
	my $w = lc $_[0];
	my $c = substr($w, 0, 1);
	if (ord($c) >= ord('a') && ord($c) <= ord('z')) {
		substr($w, 0, 1) = uc $c;
	}
	return $w;
}

sub toggle_case {  # turn jOhN into JoHn
	my @a = split("", $_[0]);
	my $w = "";
	foreach my $c (@a) {
		if (ord($c) >= ord('a') && ord($c) <= ord('z')) { $w .= uc $c; }
		elsif (ord($c) >= ord('A') && ord($c) <= ord('Z')) { $w .= lc $c; }
		else { $w .= $c; }
	}
	return $w;
}
sub rev { # turn john into nhoj   (inlining reverse was having side effects so we function this)
	my ($w) = (@_);
	$w = reverse $w;
	return $w;
}
sub purge {  #  purge out a set of characters. purge("test123john","0123456789"); gives testjohn
	my ($w, $c) = @_;
	$w =~ s/[$c]*//g;
	return $w;
}
sub replace_chars {
	my ($w, $ch, $chars) = @_;
	$w =~ s/[$chars]/$ch/g;
	return $w;
}
sub shift_case { # S	shift case: "Crack96" -> "cRACK(^"
	my ($w) = @_;
	$w =~ tr/A-Za-z0-9)!@#$%^&*(\-_=+\[{\]};:'",<.>\/?/a-zA-Z)!@#$%^&*(0-9_\-+={\[}\]:;"'<,>.?\//;
	return $w;
}
sub vowel_case { # V	lowercase vowels, uppercase consonants: "Crack96" -> "CRaCK96"
	my ($w) = @_;
	$w =~ tr/b-z/B-Z/;
	$w =~ tr/EIOU/eiou/;
	return $w;
}
sub keyboard_right { # R	shift each character right, by keyboard: "Crack96" -> "Vtsvl07"
	my ($w) = @_;
	# same behavior as john1.8.0.3-jumbo. I do not think all on the far right are 'quite' right, but at least it matches.
	# it's a very obsure rule, and not likely to have too many real world passwording implications.
	$w =~ tr/`~1qaz!QAZ2wsx@WSX3edc#EDC4rfv$RFV5tgb%TGB6yhn^YHN7ujm&UJM8ik,*IK<9ol.(OL>0p;)P:\-[_{=+\/?/1!2wsx@WSX3edc#EDC4rfv$RFV5tgb%TGB6yhn^YHN7ujm&UJM8ik,*IK<9ol.(OL>0p;\/)P:?\-['_{"=]+}\\|\\|/;
	return $w;
}
sub keyboard_left { # L	shift each character left, by keyboard: "Crack96" -> "Xeaxj85"
	my ($w) = @_;
	# idential output as john1.8.0.3-jumbo
	$w =~ tr/2wsx3edc4rfv5tgb6yhn7ujm8ik,9ol.0p;\/@WSX#EDC$RFV%TGB^YHN&UJM*IK<(OL>)P:?1!\-[_{=]+}'"/1qaz2wsx3edc4rfv5tgb6yhn7ujm8ik,9ol.!QAZ@WSX#EDC$RFV%TGB^YHN&UJM*IK<(OL>`~0p)P\-[_{;:/;
	return $w;
}
sub find_any_chars {
	# this function probably could be optimized, but as written, it works
	# well for all = / ? ( ) % type rejection rules.
	my ($w, $c) = @_;
	if (!defined $c) { return $w; }
	# some 'corrections' are needed to get a string to play nice in the reg-x we have
	
	# this is done in the load_classes initializion now.
#	$c =~ s/\\/\\\\/g; # change \ into \\
#	$c =~ s/\^/\\\^/g; # change ^ into \^
#	$c =~ s/\-/\\\-/g; # change - into \-
#	$c =~ s/\]/\\\]/g; # change ] into \]

	$w =~ s/[^$c]*//g; # The main regex. will change w the characters that were seen in original $c value.
	return length($w);
}
sub jtr_run_rule { my ($rule, $word) = @_;
	dbg(1, "jtr_run_rule called with debug level $debug\n");
	$M = $word;  # memory
	$l = length($M);
	$failed = 0;
	$rejected = 0;
	dbg(2, "checking word $word with rule $rule\n");
	my @rc = split('', $rule);
	for (my $i = 0; $i < scalar(@rc); ++$i) {
		if (length($word) == 0) { return ""; } # in jtr, this is a 'reject'
		my $c = $rc[$i];
		next if ($c eq ' ' || $c eq ':');
		if ($c eq 'l') { $word = lc $word; next; }
		if ($c eq 'u') { $word = uc $word; next; }
		if ($c eq 'c') { $word = case($word); next; }
		if ($c eq 'C') { $word = toggle_case(case($word)); next; }
		if ($c eq 't') { $word = toggle_case($word); next; }
		if ($c eq 'd') { $word = $word.$word; next; }
		if ($c eq 'r') { $word = rev($word); next; }
		if ($c eq 'f') { $word = $word.rev($word); next; }
		if ($c eq '$') { $word .= $rc[++$i]; next; }
		if ($c eq '^') { $word = $rc[++$i].$word; next; }
		if ($c eq '{') { $word = rotl($word); next; }
		if ($c eq '}') { $word = rotr($word); next; }
		if ($c eq '[') { if (length($word)) {$word = substr($word, 1);} next; }
		if ($c eq ']') { if (length($word)) {$word = substr($word, 0, length($word)-1);} next; }
		if ($c eq 'S') { $word = shift_case($word); next; }
		if ($c eq 'V') { $word = vowel_case($word); next; }
		if ($c eq 'R') { $word = keyboard_right($word); next; }
		if ($c eq 'L') { $word = keyboard_left($word); next; }
		if ($c eq '>') { my $n=get_num_val_raw($rc[++$i],$word); if(length($word)<=$n){$rejected=1; return ""; }    next; }
		if ($c eq '<') { my $n=get_num_val_raw($rc[++$i],$word); if(length($word)>=$n){$rejected=1; return ""; }    next; }
		if ($c eq '_') { my $n=get_num_val_raw($rc[++$i],$word); if(length($word)!=$n){$rejected=1; return ""; }    next; }
		if ($c eq '\''){ my $n=get_num_val_raw($rc[++$i],$word); if(length($word)> $n){ $word=substr($word,0,$n); } next; }
		#
		#   -c -8 -s -p -u -U ->N -<N -: (rejection)
		#   Not sure how to handle these, since we do not have a running john environment
		#   to probe to know what/how these impact us.
		#
		if ($c eq '-') {
			++$i;
			$c = $rc[$i];
			if ($c eq ':') {
				next;   # this one actually is done, lol.
			}
			# these are place holders now, until I can figure them out.
			if ($c eq 'c') { next; }
			if ($c eq '8') { next; }
			if ($c eq 's') { next; }
			if ($c eq 'p') { next; }
			if ($c eq 'u') { next; }
			if ($c eq 'U') { next; }
			if ($c eq '>') { ++$i; next; }
			if ($c eq '<') { ++$i; next; }
			dbg(1, "unknown length rejection rule: -$c character $c not valid.\n");
			next;
		}
		if ($c eq 's') { #   sXY & s?CY
			my $chars = "";
			if ($rc[++$i] eq "?") { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			my $ch = $rc[++$i];
			$word=replace_chars($word, $ch, $chars);
			next;
		}
		if ($c eq 'D') { # DN
			my $pos = get_num_val($rc[++$i], $word);
			if ($pos >= 0 && $pos < length($word)+1) {
				$word = substr($word, 0,$pos).substr($word, $pos+1,length($word));
			}
			next;
		}
		if ($c eq 'x') { # xNM
			my $pos = get_num_val_raw($rc[++$i], $word);
			my $len = get_num_val_raw($rc[++$i], $word);
			if ($pos >= 0 && $pos <= length($word)) {
				$word = substr($word, $pos, $len);
			}
			next;
		}
		if ($c eq 'i') { # iNX
			my $pos = get_num_val($rc[++$i], $word);
			if ($pos >= 0 && $pos <= length($word)) {
				substr($word, $pos,0) = $rc[++$i];
			}
			next;
		}
		if ($c eq 'M') { # M
			$M = $word;
			next;
		}
		if ($c eq 'Q') { # Q
			if ($M eq $word) {
				$rejected = 1;
				return "";
			}
			next;
		}
		if ($c eq '!') { # !X  !?C  (rejection)
			my $chars;
			if ($rc[++$i] eq '?') { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			if (find_any_chars($word, $chars)) {
				$rejected = 1;
				return "";
			}
			next;
		}
		if ($c eq '/') { # /X  /?C  (rejection)
			my $chars;
			if ($rc[++$i] eq '?') { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			if (!find_any_chars($word, $chars)) {
				$rejected = 1;
				return "";
			}
			next;
		}
		if ($c eq '=') { # =NX  =N?C  (rejection)
			my $chars;
			my $pos = get_num_val($rc[++$i], $word);
			if ($pos >= 0 && $pos <= length($word)) {
				my $w = substr($word, $pos, 1);
				if ($rc[++$i] eq '?') { $chars = get_class($rc[++$i]); }
				else { $chars = $rc[$i]; }
				if (!find_any_chars($w, $chars)) {
					$rejected = 1;
					return "";
				}
			}
			next;
		}
		if ($c eq '(') { # (X  (?C  (rejection)
			my $chars;
			if (length($word)==0) { $rejected = 1; return ""; }
			if ($rc[++$i] eq '?') { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			if (!find_any_chars(substr($word,0,1), $chars)) {
				$rejected = 1;
				return "";
			}
			next;
		}
		if ($c eq ')') { # )X  )?C  (rejection)
			my $chars;
			if (length($word)==0) { $rejected = 1; return ""; }
			if ($rc[++$i] eq '?') { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			if (!find_any_chars(substr($word,length($word)-1,1), $chars)) {
				$rejected = 1;
				return "";
			}
			next;
		}
		if ($c eq '%') { # %NX  %N?C  (rejection)
			my $chars;
			my $n = get_num_val($rc[++$i]);
			if ($rc[++$i] eq '?') { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			if (find_any_chars(substr($word,length($word)-1,1), $chars) < $n) {
				$rejected = 1;
				return "";
			}
			next;
		}
		if ($c eq 'X') { # XNMI
			my $posM = get_num_val($rc[++$i], $M);  # note using $M not $word.
			my $len = get_num_val($rc[++$i], $M);
			my $posI = get_num_val($rc[++$i], $word);
			if ($posM >= 0 && $len > 0 && $posI >= 0) {
				substr($word, $posI, 0) = substr($M, $posM, $len);
			}
		}
		if ($c eq 'o') { # oNX
			my $pos = get_num_val($rc[++$i], $word);
			if ($pos >= 0 && $pos < length($word)) {
				substr($word, $pos,1) = $rc[++$i];
			}
		}
		if ($c eq 'T') { # TN  (toggle case of letter at N)
			my $pos = get_num_val($rc[++$i], $word);
			if ($pos >= 0) {
				my $c = substr($word, $pos, 1);
				if (ord($c) >= ord('a') && ord($c) <= ord('z')) { substr($word, $pos, 1) = uc $c; }
				elsif (ord($c) >= ord('A') && ord($c) <= ord('Z')) { substr($word, $pos, 1) = lc $c; }
			}
			next;
		}
		if ($c eq '@') {  # @X & @?C
			my $chars = "";
			if ($rc[++$i] eq "?") { $chars = get_class($rc[++$i]); }
			else { $chars = $rc[$i]; }
			$word=purge($word, $chars);
			next;
		}
		if ($c eq 'A') { # AN"STR"  with de-ESC in STR
			my $pos = get_num_val($rc[++$i], $word);
			if ($pos < 0) {next;}
			my $delim = $rc[++$i];
			dbg(2,"delim=$delim\n");
			my $s = "";
			while ($rc[$i+1] ne $delim) {
				if ($rc[$i] eq '\\' && $rc[$i+1] eq "x") {
					# \xhh escape, replace with 'real' character
					$i += 2;
					my $s = $rc[++$i]; $s .= $rc[$i];
					($rc[$i]) = sscanf($s, "%X");
					$rc[$i] = chr($rc[$i]);
				}
				$s .= $rc[++$i];
			}
			++$i;
			substr($word, $pos, 0) = $s;
			next;
		}
		dbg(1, "Do not know how to handle character $c in the rule\n");
	}
	if (length($word) > 125) { return substr($word, 0, 125); }
	dbg(1, "resultant word after rule $rule is: $word\n");
	return $word;
}
sub rotl {
	my $w = $_[0];
	$w = substr($w, 1, length($w)).substr($w, 0, 1);
	return $w;
}
sub rotr {
	my $w = $_[0];
	$w = substr($w, length($w)-1, 1).substr($w, 0, length($w)-1);
	return $w;
}
sub get_class {
	my ($c) = @_;
	if ($c eq '?') { dbg(2,"Doing get class of ?\n"); return $cclass{'?'}; }
	return $cclass{$c};
}
sub get_num_val_raw { my ($p, $w) = (@_);
#0...9	for 0...9
#A...Z	for 10...35
#*	for max_length
#-	for (max_length - 1)
#+	for (max_length + 1)
#a...k	user-defined numeric variables (with the "v" command)
#l	initial or updated word's length (updated whenever "v" is used)
#m	initial or memorized word's last character position
#p	position of the character last found with the "/" or "%" commands
#z	"infinite" position or length (beyond end of word)
	if (ord($p) >= ord("0") && ord($p) <= ord('9')) {return ord($p)-ord('0');}
	if (ord($p) >= ord("A") && ord($p) <= ord('Z')) {return  ord($p)-ord('A')+10;}
	if ($p eq '*') { return $rules_max_length; }
	if ($p eq '-') { return $rules_max_length-1; }
	if ($p eq '+') { return $rules_max_length+1; }
#	if ($p eq 'a...k') {}
	if ($p eq 'z') {return length($w);}
	if ($p eq 'l') { return $l; }
	if ($p eq 'm') { my $m = length($M); if ($m>0){$m-=1;} return $m; }
	print "ERROR, $p is NOT a valid length item\n";
	return -1;
}
sub get_num_val { my ($p, $w) = (@_);
	$p = get_num_val_raw($p, $w);
	if ($p > length($w)) { return -1; }
	return $p;
}
sub esc_remove {
	my $w = $_[0];
	my $p = index($w, "\\");
	while ($p >= 0) {
		#print "w=$w p=$p ";
#		if (substr($w,$p+1,1) eq "\\") {++$p;} # \\ so keep the first one intact
#		if (substr($w,$p+1,1) eq "-") {++$p;} # keep \- intact
		$w = substr($w,0,$p).substr($w,$p+1);
		#print "now w=$w\n";
		$p = index($w, "\\", $p+1);
	}
	return $w;
}

sub get_items {
	my ($s, $pos) = (@_);
	$_[2] = index($s, ']', $pos);
	if ($_[2] < 0) { return ""; }
	while ($pos < $_[2] && substr($s, $_[2]-1, 1) eq "\\") {
		$_[2] = index($s, ']', $_[2]+1);
	}
	if ($pos+2 >= $_[2])  { return ""; }
	$s = substr($s, $pos+1, $_[2]-$pos-1);
	if (index($s, '-')==-1) {return esc_remove($s);}
	my @ch = split('', $s);

	# note, we do not check for some invalid ranges, like [-b] or [ab-] or [z-a]
	my $i = 0;
	my $chars = "";
	for ($i = 0; $i < length($s); ++$i) {
		if ($i>0 && $ch[$i] eq '-' && $ch[$i-1] ne "\\") {
			dbg(4, "doing range fix for $ch[$i-1]-$ch[$i+1]\n");
			for (my $c = ord($ch[$i-1])+1; $c <= ord($ch[$i+1]); ++$c) {
				$chars .= chr($c);
			}
			++$i;
		} else {
			# \xhh escape, replace with 'real' character
			if ($ch[$i] eq "\\") {
				if ($ch[$i+1] eq "x") {
					$i += 2;
					my $s = $ch[++$i]; $s .= $ch[$i];
					($ch[$i]) = sscanf($s, "%X");
					$ch[$i] = chr($ch[$i]);
				} else {
					++$i;
				}
			}
			$chars .= $ch[$i];
		}
	}
	# we must 'unique' the data (jtr will do that)
	dbg(2, "get_item returning: chars=$chars\n");
	$chars = reverse $chars;
	$chars =~ s/(.)(?=.*?\1)//g;
	$chars = reverse $chars;
	dbg(2, "get_item returning: chars=$chars\n");
#	exit(0);
	return $chars;
}

# preprocessor.  We have an array of rules that get built. Then
# we keep count of which have been handled, so we eat them one
# at a time, in order.
sub jtr_rule_pp_init { my ($pre_pp_rule, $len) = (@_);
	$pp_idx = 0;
	if (!defined($len) || $len==0) {$rules_max_length = 0;}
	else {$rules_max_length = $len; }
	@pp_rules = ();
	dbg(4, "calling pp_rule() to prepare our rules\n"); 
	pp_rule(purge($pre_pp_rule,' '), 0, 0);
	dbg(4, "There were ".scalar @pp_rules." created\n"); 
	
	if ($debug>3) {
		foreach my $s (@pp_rules) { print "$s\n"; } exit(0);
	}

	if (scalar @pp_rules > 0) {
		return $pp_rules[0];
	}
	return "";
}
sub jtr_rule_pp_next { my () = (@_);
	if (scalar @pp_rules == $pp_idx) { return ""; }
	return $pp_rules[++$pp_idx];
}
sub handle_backref { my ($gnum, $c, $pos, $s, $idx, $total) = @_;
	my $i; my $i2; my $n;

	# find any \$gnum and replace with $c
	$s =~ s/\\$gnum/$c/g;

	# find any \p$gnum[] and replace with the $gnum from it's group
	$i = index($s, "\\p${gnum}[");
	while ($i >= 0) {
		my $chars = get_items($s, $i+3, $i2);
		if ($i2 == -1) { print STDERR "invalid \\p${gnum}[..] found in rule\n"; die; }
		my @a = split('', $chars);
		my $c;
		my $i3 = $idx;
		if (scalar @a <= $i3) { $i3 = scalar @a - 1; }
		substr($s, $i, $i2-$i+1) = $a[$i3];
		$i = index($s, "\\p${gnum}[");
	}

	# now that all the stray ['s are gone, we can look for \p[ and \0
	$i = index($s, "\\p0[");
	while ($i >= 0) {
		my $chars = get_items($s, $i+3, $i2);
		if ($i2 == -1) { print STDERR "invalid \\p0[..] found in rule\n"; die; }
		my @a = split('', $chars);
		my $c;
		my $i3 = $idx;
		if (scalar @a < $i3) { $i3 = scalar @a - 1; }
		substr($s, $i, $i2-$i+1) = $a[$i3];
		$i = index($s, "\\p0[");
	}

	# find any \0 before the next [  and replace with $c
	$i = index($s, "\\0");
	#print "i for \\0 = $i  (s=$s)\n";
	while ($i >= 0) {
		$i2 = index($s, "[");
		if ($i2 > -1 && $i > $i2) { $i = -1; }
		else {
			substr($s, $i, 2) = $c;
			$i = index($s, "\\0");
		}
	}

	# find any \p[ and step them. The step is $total
	$i = index($s, "\\p[");
	while ($i >= 0) {
		my $chars = get_items($s, $i+2, $i2);
		#print "in \\p[ and found $chars with total=$total\n";
		if ($i2 == -1) { print STDERR "invalid \\p found in rule\n"; die; }
		my @a = split('', $chars);
		my $c;
		if (scalar @a <= $total) { $total = scalar @a - 1; }
		substr($s, $i, $i2-$i+1) = $a[$total];
		$i = index($s, "\\p[");
	}
	return $s;
}
sub handle_rule_rej {
	my $rule = $_[0];
	if (substr($rule, 0, 1) ne '-') {return $rule;}
	my $v = substr($rule,1,1);
	if ($v eq ':') { return substr($rule, 2); }
	if ($v eq 'c') { return substr($rule, 2); }
	if ($v eq '8') { return substr($rule, 2); }
	if ($v eq 's') { return substr($rule, 2); }
	if ($v eq 'p') { return substr($rule, 2); }
	if ($v eq 'u') { return substr($rule, 2); }
	if ($v eq 'U') { return substr($rule, 2); }
	if ($v eq '<') { return substr($rule, 3); }
	if ($v eq '>') { return substr($rule, 3); }
	return $rule;
}
#
# pre-processor: handles [] \xHH and \# and \p# backreferences. NOTE, recursive!
#
sub pp_rule_old { my ($rules, $which_group, %all_idx) = (@_);
	dbg(4, "PP: rule(s) $rules\n");
	my $pos = index($rules, '[');
	if ($pos == -1) {dbg(4, "      rule saved $rules\n"); push(@pp_rules, $rules); return; }
	my $pos2 = index($rules, ']');
	if ($pos > $pos2)  {dbg(4, "      rule saved $rules\n"); push(@pp_rules, $rules); return; }
	while ($pos < $pos2 && substr($rules, $pos2-1, 1) eq "\\") {
		$pos2 = index($rules, ']', $pos2+1);
	}
	if ($pos > $pos2)  {dbg(4, "      rule saved $rules\n"); push(@pp_rules, $rules); return; }
	my $Chars = get_items(substr($rules, $pos, $pos2-$pos+1));
	dbg(4, "  item return is $Chars from $rules with sub=".substr($rules, $pos, $pos2-$pos+1)."\n");
	my @chars = split("", $Chars);
	my $idx = 0;
	$which_group += 1;
	foreach my $c (@chars) {
		$idx++;
		$all_idx{$which_group} = $idx;
		#my $s = handle_backref($which_group, $c, $pos2, $rules, %all_idx);
		#if ($s ne $rules) { }# dbg(0, "     before handle_backref($which_group, $idx, $rules)\nhandle_backref returned $s\n"); }
		my $s = $rules;
		dbg(4, "    before sub=$s\n");
		substr($s, $pos, $pos2-$pos+1) = $c;
		dbg(4, "    after sub=$s (recurse now)\n");
		if (pp_rule($s, $which_group, %all_idx)) { return 1; }
	}
	return 0;
}

sub pp_rule { my ($rules, $which_group, $idx) = (@_);
	my $total = 0;
	dbg(3, "** entered pp_rule($rules, $which_group, $idx, $total)\n");
	my $pos = index($rules, '[');
	if ($pos == -1) { $rules=handle_rule_rej($rules); push(@pp_rules,$rules); return 0; }
	while ($pos >= 0 && substr($rules, $pos-1, 1) eq "\\") {
		$pos = index($rules, '[', $pos+1);
	}
	my $pos2;
	my $Chars = get_items($rules, $pos, $pos2);
	if ($pos > $pos2)  { $rules=handle_rule_rej($rules); push(@pp_rules,$rules); return 0;}
	my @chars = split('', $Chars);
	$idx = 0;
	$which_group += 1;
	$idx++;
	#print " * before foreach loop. rules=$rules\n";
	foreach my $c (@chars) {
		my $s = $rules;
		dbg(4, "before sub=$s\n");
		substr($s, $pos, $pos2-$pos+1) = $c;
		dbg(4, "after sub=$s\n");
		my $s2 = handle_backref($which_group, $c, $pos2, $s, $idx, $total);
		if ($s2 ne $s) {dbg(4, "before handle_backref($which_group, $c, $pos2, $s, $total)\nhandle_backref returned     $s2\n"); }
		++$total;
		dbg(4, "*** entering      recurse pp_rule($rules, $which_group, $idx, $total) pos=$pos pos2=$pos2\n");
		if (pp_rule($s2, $which_group, $idx, $_[6])) { return 1; }
		$_[6]++;
		$idx++;
		dbg(3, "*** returned from recurse pp_rule($rules, $which_group, $idx, $total) pos=$pos pos2=$pos2\n");
	}
	return 0;
}

sub load_classes {
	my $i;
	my $c_all;  for ($i = 1;    $i < 255; ++$i) { $c_all  .= chr($i); }
	my $c_8all; for ($i = 0x80; $i < 255; ++$i) { $c_8all .= chr($i); }
	$cclass{z}=$c_all;
	$cclass{b}=$c_8all;
	$cclass{'?'}='?';
	$cclass{v}="aeiouAEIOU";
	$cclass{c}="bcdfghjklmnpqrstvwxyzBCDFGHJKLMNPQRSTVWXYZ";
	$cclass{w}=" \t";
	$cclass{p}="\.,:;\'\?!`\"";
	$cclass{s}="\$%^&\*\(\)-_+=|\<\>\[\]\{\}#@/~";
	$cclass{l}="abcdefghijklmnopqrstuvwxyz";
	$cclass{u}=uc $cclass{l};
	$cclass{d}="0123456789";
	$cclass{a}=$cclass{l}.$cclass{u};
	$cclass{x}=$cclass{l}.$cclass{u}.$cclass{d};
	$cclass{o}="\x01\x02\x03\x04\x05\x06\x07\x08\x0A\x0B\x0C\x0D\x0E\x0F\x10\x11\x12\x13\x14\x15\x16\x17\x18\x19\x1A\x1B\x1C\x1D\x1E\x1F\x7F\x84\x85\x88\x8D\x8E\x8F\x90\x96\x97\x98\x9A\x9B\x9C\x9D\x9E\x9F";
	$cclass{y}=""; # note some types some chars are not valid (i.e. A..Z is not valid for a format where pass is lc(pass)
	foreach my $c (split("","bvcwpsludaxo")) {
		my $C = uc $c;
		$cclass{$C}=purge($cclass{z}, $cclass{$c});
		
		# some 'corrections' are needed to get a string to play nice in the reg-x we have
		$cclass{$C} =~ s/\\/\\\\/g; # change \ into \\
		$cclass{$C} =~ s/\^/\\\^/g; # change ^ into \^
		$cclass{$C} =~ s/\-/\\\-/g; # change - into \-
		$cclass{$C} =~ s/\]/\\\]/g; # change ] into \]
	}
	$cclass{Y}=$c_all;
	$cclass{Y} =~ s/\\/\\\\/g; # change \ into \\
	$cclass{Y} =~ s/\^/\\\^/g; # change ^ into \^
	$cclass{Y} =~ s/\-/\\\-/g; # change - into \-
	$cclass{Y} =~ s/\]/\\\]/g; # change ] into \]
}
1;
