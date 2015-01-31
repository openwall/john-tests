// Try to make a dictionary, where no 'longer line' (more than 7 chars), that 
// is cut off, will have duplicate value below it, or above it. Also, add
// random utf8 stuff, and high bit encoded values out (but usually not in
// the lower values).   Have a section (about 500 or so), where there are 
// a large range of length variations randomly arranged. Then have another
// where we step up by 7, down by 5, up by 6, down by 6 up by 7, down by
// by 5, ... from 2 up to 132 down to 2, up to 132, down to 2. Then another
// section like that, where we have 5 in a row that rotates like that.
// then a section that is only 7 bytes long (max).
// once we get a program that generates a exact same output file time and
// time again, we then add options to only output the lines fit certain
// criteria, so we can use this too, vs using grep against a fixed dicionary.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// random routines (from mt.cpp)
unsigned long genrand_int32();
void init_by_array(unsigned long init_key[], int key_length);
double genrand_real2();

char *gen_next(int len, unsigned &tot);
bool print_if_meet_criteria(const char *, unsigned &cnt);
int rnd(int);

// BASE94 skips ':' char. We avoid that char, due to it's usage in JtR for separator char. It simply makes things easier.
char base94[] = " !@#$%^&*()_+=-0987654321`~\\|]}[{abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ<>,./?;'\"";
unsigned starts[50000];

int main (int argc, char **argv) {
	// first few, are 'special'. These are the most important, since we have some formats
	// that only use a very FEW value.
	char *pass;
	unsigned tot=0, i, len=4, cnt=0;

	unsigned long init[4]={0x123, 0x234, 0x345, 0x456}, length=4;
    init_by_array(init, length);

	// first 4 characters (unique), base=94  (no ':' char)
	// 94^4 is 78074896
	for (i = 0; i < 50000; ++i) {
		Again:;
		unsigned val = rnd(78074896);
		for (unsigned j = 0; j < i; ++j) {
			if (starts[j] == val)
				goto Again;
		}
		starts[i] = val;
	}

	// grow from 4 to 54
	for (i = 0; i < 10; ++i) {
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		len += 5;
	}
	print_if_meet_criteria("", cnt);
	pass = gen_next(9, tot);
	print_if_meet_criteria(pass, cnt);
	print_if_meet_criteria("p", cnt);

	// zig-zag lengths 4-56 9-45. .... 
	len = 4;
	for (i = 0; i < 10; ++i) {
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(60-len, tot);
		print_if_meet_criteria(pass, cnt);
		len += 5;
	}
	for (i = 0; i < 50; ++i) {
		len = 4+rnd(16);
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
	}
	for (i = 0; i < 400; i+=3) {
		pass = gen_next(4+rnd(130), tot);
		print_if_meet_criteria(pass, cnt);
		len += 3;
	}
	for (i = 12; i < 134; i++) {
		pass = gen_next(i, tot);
		print_if_meet_criteria(pass, cnt);
	}
	for (; i > 12; i--) {
		pass = gen_next(i, tot);
		print_if_meet_criteria(pass, cnt);
	}
	for (; i < 134; i++) {
		pass = gen_next(i, tot);
		print_if_meet_criteria(pass, cnt);
	}
	for (; i > 12; i--) {
		pass = gen_next(i, tot);
		print_if_meet_criteria(pass, cnt);
	}
	len = 12;
	for (i = 0; i < 134; i+=3) {
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		len += 3;
	}
	len = 12;
	for (i = 0; i < 134; i+=3) {
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(134-len, tot);
		len += 3;
	}
	len = 12;
	for (i = 0; i < 134; i+=3) {
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(len, tot);
		print_if_meet_criteria(pass, cnt);
		len += 3;
	}
	len = 12;
	for (i = 0; i < 134; i+=3) {
		pass = gen_next(154-len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(154-len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(154-len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(154-len, tot);
		print_if_meet_criteria(pass, cnt);
		pass = gen_next(154-len, tot);
		print_if_meet_criteria(pass, cnt);
		len += 3;
	}
	for (i = 0; i < 2500; ++i) {
		pass = gen_next(6+rnd(14), tot);
		print_if_meet_criteria(pass, cnt);
	}
	return 0;
}

char *gen_next(int len, unsigned &tot) {
	static char this_word[150];
	// ok, first genertate the first 4 characters, from our base-94 charset.
	unsigned val = starts[tot++];
	int idx;
	for (idx = 0; idx < 4; ++idx) {
		unsigned x = val%94;
		val /= 94;
		this_word[idx] = base94[x];
	}
	while (idx < len-4)
		this_word[idx++] = 'p';
	while (idx < len) {
		this_word[idx++] = base94[rnd(94)];
	}
	if (len > 6 && rnd(100) > 94) {
		// set high bits on some characters
		for (idx = 5; idx < len && idx < 25; idx += 6) {
			val = rnd(126)+128;
			this_word[idx] = val;
		}
	}
	// having a " (" within the password causes problems within jtrts.pl, so we simply
	// remove any of those words.
	if (strstr(this_word, " ("))
		return gen_next(len, --tot);
	this_word[len] = 0;
	return this_word;
}
bool print_if_meet_criteria(const char *p, unsigned &cnt) {
	printf ("%s\n", p);
	++cnt;
	return true;
}

int rnd(int max) {
	return (int)(genrand_real2()*max);
}
