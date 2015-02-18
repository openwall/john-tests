#include <stdio.h>

#define C			64
#define S			16

/*
These are the 8 types of buffers this algorithm uses:
cp
pspc
cspp
ppc
cpp
psc
csp
pc
*/

void crypt_sha512(int P) {
	int lens[8], limbs[8], limb_cnt[6]={0}, i;
	printf ("%03d - ", P);
	lens[0] = C+P;
	lens[1] = P+S+P+C;
	lens[2] = C+S+P+P;
	lens[3] = P+P+C;
	lens[4] = C+P+P;
	lens[5] = P+S+C;
	lens[6] = C+S+P;
	lens[7] = P+C;
	for (i = 0; i < 8; ++i) {
		limbs[i] = (lens[i] + 17)/128 + 1;
		limb_cnt[limbs[i]-1]++;
		printf ("%03d ", lens[i]);
	}
	printf (" :: %d %d %d %d %d %d\n", limb_cnt[0], limb_cnt[1], limb_cnt[2], limb_cnt[3], limb_cnt[4], limb_cnt[5]);
}

void main() {
	int i;
	for (i = 1; i < 125; ++i) {
		crypt_sha512(i);
	}
}