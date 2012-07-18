#!/bin/sh

# Use this script to find the length of the password data, within a file. There are formats used
# which have a shorter PLAINTEXTLEN than the input file was creatd with. In those cases, we must
# add a smaller expected count into the jtrts.dat file, on the line which that format uses.
# often, this is seen in the GPU formats.  At some time, this logic may be added INTO the TS, and
# have the TS compute the lengths of passwords, and then use the --list=format-all-details to fine
# out just what the PLAINTEXT_LENGTH is listed for the format, to be able to auto compute this
# information.  However, until the TS is changed to handle this automatically, this script will
# help to get the jtrts.dat file to have the right data.

# NOTE, this script get ALL data from field 5 on. So, it is assumed the file is :pass::  (pass being
# in the 5th field). We simply drop 2 from the length, to get the proper length of the password).
# This allows passwords to contain the ':' char, BUT requires 2 :: chars tailing the line. Currently
# pass_gen.pl has been written to write files like this.  However, this 'may' have to be adjusted on
# any input file lacking this structure.

cat $1 | cut -d: -f5- | perl -ne 'use bytes; chomp; $l=length; $l-=2; print "$l\n"' | sort -n | uniq -c | sort -nk2
