#!/bin/sh

# Use this script to find the length of the password data, within a file. There
# are formats used which have a shorter PLAINTEXTLEN than the input file was
# created with. In those cases, we must add a smaller expected count into the
# jtrts.dat file, on the line which that format uses. Often, this is seen in the
# GPU formats.  At some time, this logic may be added INTO the TS, and have the
# TS compute the lengths of passwords, and then use the
# --list=format-all-details to find out just what the PLAINTEXT_LENGTH is listed
# for the format, to be able to auto compute this information.  However, until
# the TS is changed to handle this automatically, this script will help to get
# the jtrts.dat file to have the right data.

# v2 made by magnum, adding a sum column. This is awful code, it should be pure
# perl. But it works like a champ :)

echo "num\tlen\tsum"
grep -v '^#!comment:' $1 | cut -d: -f5 |
perl -ne 'use bytes; chomp; print length, "\n"' |
sort -n | uniq -c | sort -nk2 |
perl -ne 'chomp; @f = split; $s += $f[0]; print "$f[0]\t$f[1]\t$s\n"'
