#!/bin/bash

function do_Init(){
    echo 'Preparing to run...'
    cp ../pw.dic .
    cp ../rawsha256_tst.in .
    cp ../cisco4_tst.in .
    cp ../rawsha512_tst.in .
    cp ../XSHA512_tst.in .

    ../../run/john -form:cpu --list=format-tests 2> /dev/null | cut -f3 1> alltests.in

    read CPU_DEV <<< $(../../run/john --list=opencl-devices -dev:cpu | \
                        grep 'Device #' | sed -e 's/^[[:space:]]*//' | cut -d ' ' -f 3 | tr '()\n' ' ')
    read GPU_DEV <<< $(../../run/john --list=opencl-devices -dev:gpu | \
                        grep 'Device #' | sed -e 's/^[[:space:]]*//' | cut -d ' ' -f 3 | tr '()\n' ' ')
    Device_List="$CPU_DEV $GPU_DEV"
    #echo "--> CPUs: $CPU_DEV"
    #echo "--> GPUs: $GPU_DEV"
    #echo "--> Final: $Device_List"
    clear
}

function do_Done(){
    rm alltests.in
    rm pw.dic
    rm rawsha256_tst.in
    rm cisco4_tst.in
    rm rawsha512_tst.in
    rm XSHA512_tst.in
    rm -f *.log
    rm -f *.rec
}

function do_Test_Suite(){
    #TODO: parse errors
    echo 'Running raw-SHA256 Test Suite tests...'

    cd ..
    ./jtrts.pl -type raw-sha256-opencl -passthru "-dev:$TST_Device_1"
    ./jtrts.pl -type raw-sha256-opencl -passthru "-dev:$TST_Device_2"
    ./jtrts.pl -type raw-sha256-opencl -passthru "-dev:$TST_Device_3"
    ./jtrts.pl -internal -type raw-sha256-opencl -passthru "-dev:$TST_Device_1 --fork=2"
    ./jtrts.pl -internal -type raw-sha256-opencl -passthru "-dev:$TST_Device_2 --fork=3"
    ./jtrts.pl -internal -type raw-sha256-opencl -passthru "-dev:$TST_Device_3 --fork=4"
    Total_Tests=$((Total_Tests + 6))
    cd - > /dev/null
}

function do_Test_Bench(){
    TEMP=$(mktemp _tmp_output.XXXXXXXX)
    TO_RUN="$3 ../../run/john $1 $2 &> $TEMP"
    eval $TO_RUN
    ret_code=$?

    if [[ $ret_code -ne 0 ]]; then
        echo "ERROR ($ret_code): $TO_RUN"
        echo
 
        cat $TEMP >> error.saved
        Total_Erros=$((Total_Erros + 1))
    else
        awk '/Device/ { print $0 }' $TEMP
        awk '/c\/s real/ { print $0 }' $TEMP
        echo
    fi
    Total_Tests=$((Total_Tests + 1))
    #-- Remove tmp files.
    rm $TEMP
} 

function do_Test(){
    TEMP=$(mktemp _tmp_output.XXXXXXXX)
    TO_RUN="$5 ../../run/john -ses=tst-cla -pot=tst-cla.pot $1 $2 $3 &> /dev/null"
    eval $TO_RUN
    ret_code=$?

    if [[ $ret_code -ne 0 ]]; then
        read MAX_TIME <<< $(echo $3 | awk '/-max-run/ { print 1 }')

        if ! [[ $ret_code -eq 1 && "$MAX_TIME" == "1" ]]; then
            echo "ERROR ($ret_code): $TO_RUN"
            echo
 
            exit 1
        fi
    fi
    TO_SHOW="../../run/john -show=left -pot=tst-cla.pot $1 $2 &> $TEMP"
    eval $TO_SHOW
    ret_code=$?

    if [[ $ret_code -ne 0 ]]; then
        echo "ERROR ($ret_code): $TO_SHOW"
        echo
 
        exit 1
    fi
    #cat $TEMP | awk '/password hash/ { print $1 }'
    read CRACKED <<< $(cat $TEMP | awk '/password hash/ { print $1 }')

    #echo "DEBUG: ($CRACKED) $TO_RUN"
    #echo "DEBUG: ($CRACKED) $TO_SHOW"

    if [[ $CRACKED -ne $4 ]]; then
        echo "ERROR: $TO_RUN"
        echo "Expected value: $4, value found: $CRACKED. $TO_SHOW"
        echo
 
        exit 1
    fi
    Total_Tests=$((Total_Tests + 1))
    #-- Remove tmp files.
    rm tst-cla.pot
    rm $TEMP
} 

function do_Regressions(){
    echo 'Regression testing...'
    do_Test "alltests.in"       "-form:Raw-SHA256-opencl"     "-wo:pw.dic --skip"              7  #Skip self test segfaults
    do_Test "XSHA512_tst.in"    "-form=xSHA512-ng-opencl"     "-wo:pw.dic --rules --skip"   1500  #Skip self test segfaults, other format
    do_Test "crame_me.tst"      "-form:Raw-SHA512-ng-opencl"  "-mask=?l?l?l?l"                 6  #Can't handle more than a few hashes
    do_Test "regression_1.tst"  "-form:Raw-SHA256-opencl"     ""                           12027  #Miss cracks
}

function do_All_Devices(){

    if [[ "$1" == "raw-sha256" ]] || [[ $# -eq 0 ]]; then
        echo 'Evaluating raw-sha256 in all devices...'
        for i in $Device_List ; do do_Test_Bench "-form:Raw-SHA256-opencl" "--test -dev:$i" "" ; done
        for i in $Device_List ; do do_Test_Bench "-form:Raw-SHA256-opencl" "--test --mask=?d?d?d?d5678 -dev:$i" "" ; done 
    fi

    if [[ "$1" == "raw-sha512" ]] || [[ $# -eq 0 ]]; then
        echo 'Evaluating raw-sha512 in all devices...'
        for i in $Device_List ; do do_Test_Bench "-form:Raw-SHA512-opencl" "--test -dev:$i" "" ; done
        for i in $Device_List ; do do_Test_Bench "-form:Raw-SHA512-opencl" "--test --mask=?d?d?d?d5678 -dev:$i" "" ; done 
        for i in $Device_List ; do do_Test_Bench "-form:xSHA512-opencl" "--test -dev:$i" "" ; done
        for i in $Device_List ; do do_Test_Bench "-form:xSHA512-opencl" "--test --mask=?d?d?d?d5678 -dev:$i" "" ; done 
    fi
}

function sha256(){
    echo 'Running raw-SHA256 cracking tests...'
    do_Test "cisco4_tst.in"    "-form:Raw-SHA256-opencl" "-wo:pw.dic --rules --skip"                                           1500
    do_Test "rawsha256_tst.in" "-form:Raw-SHA256-opencl" "-wo:pw.dic --rules=all -dev:$TST_Device_2"                           1500
    do_Test "alltests.in"      "-form=raw-SHA256-opencl" "-incremental -max-run=50 -fork=4 -dev:$TST_Device_1"                    9
    do_Test "alltests.in"      "-form=raw-SHA256-opencl" "-incremental -max-run=40 -fork=4 -dev:$TST_Device_3"                    9

    do_Test "alltests.in"      "-form=Raw-SHA256-opencl" "-mask:?l -min-len=4 -max-len=7"           2 
    do_Test "alltests.in"      "-form=Raw-SHA256-opencl" "-mask:?d -min-len=1 -max-len=8"           4 "_GPU_MASK_CAND=0" 
    do_Test "alltests.in"      "-form=raw-SHA256-opencl" "-mask=[Pp][Aa@][Ss5][Ss5][Ww][Oo0][Rr][Dd] -dev:$TST_Device_1"          2
    do_Test "alltests.in"      "-form=Raw-SHA256-opencl" "-mask:tes?a?a"                                                          3
}

function sha512(){
    echo 'Running raw-SHA512 cracking tests...'
    do_Test "rawsha512_tst.in" "-form=raw-SHA512-ng-opencl" "-wo:pw.dic --rules=all --skip"                                   1500
    do_Test "XSHA512_tst.in"   "-form=xSHA512-ng-opencl"    "-wo:pw.dic --rules"                                              1500
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-incremental -max-run=50 -fork=4 -dev:$TST_Device_1"                3
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-incremental -max-run=40 -fork=4 -dev:$TST_Device_3"                3

    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask=[Pp][Aa@][Ss5][Ss5][Ww][Oo0][Rr][Dd] -dev:$TST_Device_1"      2
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask:?l?l?l?l?l?l?l --skip -dev:$TST_Device_2"                     1
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask:?d2345?d?d?d"                                                    2
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask:1?d3?d5?d7?d90123?d5?d7?d90"                                     2
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask=?u?u?uCAPS"                                                      2
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask:xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx[x-z] -min=55 -max-l=55"  2
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask:TestTESTt3st"                                                    2
    do_Test "alltests.in"      "-form=raw-SHA512-ng-opencl" "-mask:john?a?l?l?lr  -dev:$TST_Device_3"                               2

    do_Test "alltests.in"      "-form=xSHA512-ng-opencl" "-mask:?l?l?l?l?l"                            1
    do_Test "alltests.in"      "-form=xSHA512-ng-opencl" "-mask=[Pp][Aa@][Ss5][Ss5][Ww][Oo0][Rr][Dd]"  1
    do_Test "alltests.in"      "-form=xSHA512-ng-opencl" "-mask=boob?l?l?l"                            1
    do_Test "alltests.in"      "-form=xSHA512-ng-opencl" "-mask:?d -min-len=1 -max-len=4"              5 "_GPU_MASK_CAND=0"
    do_Test "alltests.in"      "-form=xSHA512-ng-opencl" "-mask:?d -min-len=4 -max-len=8"              6  
}

function do_all(){
    sha256
    sha512
}

function do_help(){
    echo 'Usage: ./test-claudio.sh [OPTIONS] [hash]'
    echo 
    echo '--help:       prints this help.'
    echo '--version:    prints the version information.'
    echo '--basic:      tests hashes against all available devices (CPU and GPU). To filter a hash type, use:'
    echo '               ./test-claudio.sh --basic [hash]'
    echo '--cracking:   runs the cracking tests. To filter a hash type, use:'
    echo '               ./test-claudio.sh [hash]'
    echo '--regression: ensures fixed bugs were not reintroduced.'
    echo '--ts:         executes the Test Suite.'
    echo ' '
    echo 'Available hashes:'
    echo '  raw-sha256: filter and execute only raw-sha256 tests.'
    echo '  raw-sha512: filter and execute only raw-sha512 tests.'
    echo

    exit 0 
}

function do_version(){
    echo 'Tester Sidekick, version 0.2-beta'
    echo 
    echo 'Copyright (C) 2016 Claudio André <claudioandre.br at gmail.com>'
    echo 'License GPLv2+: GNU GPL version 2 or later <http://gnu.org/licenses/gpl.html>'
    echo 'This program comes with ABSOLUTELY NO WARRANTY; express or implied.'
    echo

    exit 0 
}

#-----------   Helper   -----------
case "$1" in
    "help" | "--help" | "-h") 
        do_help;;
    "version" | "--version" | "-v") 
        do_version;;
esac

if [[ $# -eq 0 ]]; then
    do_help
fi

#-----------   Init   -----------
Total_Tests=0
Total_Erros=0
TST_Device_1=0
TST_Device_2=2
TST_Device_3=7
do_Init

#-----------   Tests   -----------

case "$1" in
    "--basic") 
        do_All_Devices $2;;
    "--regression")
        do_Regressions;;
    "--ts") 
        do_Test_Suite;;
    "--cracking")
        do_all;;
    "raw-sha256") 
        sha256;;
    "raw-sha512") 
        sha512;;
esac

#-----------   Done  -----------
do_Done

#----------- The End -----------
echo 
echo '--------------------------------------------------------------------------------'
if [ $Total_Erros -eq 0 ]; then
    echo "All tests passed without error! Performed $Total_Tests tests in $SECONDS seconds."
else
    echo "$Total_Erros tests FAILED! Performed $Total_Tests tests in $SECONDS seconds."
fi
echo '--------------------------------------------------------------------------------'

