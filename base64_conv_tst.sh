#!/bin/bash
#
# Test script for the base64conv program.
#
# -q for 'quiet' mode.

T=yes
F=0
Q=N
if [ x$1 = "x-q" ] ; then Q=Y ; fi

# simple test cycling through the types.  $MEM and $V9 should be same in the end
MEM=123456789aBCDefGHJ
V1=`../run/base64conv 2>/dev/null -i raw -q -e -o hex $MEM`
V2=`../run/base64conv 2>/dev/null -i hex -q -e -o mime $V1`
V3=`../run/base64conv 2>/dev/null -i mime -q -e -o crypt $V2`
V4=`../run/base64conv 2>/dev/null -i crypt -q -e -o cryptBS $V3`
V5=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o mime $V4`
V6=`../run/base64conv 2>/dev/null -i mime -q -e -o cryptBS $V5`
V7=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o crypt $V6`
V8=`../run/base64conv 2>/dev/null -i crypt -q -e -o hex $V7`
V9=`../run/base64conv 2>/dev/null -i hex -q -e -o raw $V8`
if [ x$MEM != x$V9 ];
then
    F=1
    echo "Simple test failed.  '$MEM' not same as '$9'"
    echo "MEM='$MEM'"
    echo "V1 ='$V1'"
    echo "V2 ='$V2'"
    echo "V3 ='$V3'"
    echo "V4 ='$V4'"
    echo "V5 ='$V5'"
    echo "V6 ='$V6'"
    echo "V7 ='$V7'"
    echo "V8 ='$V8'"
    echo "V9 ='$V9'"
else
    if [ $Q = "N" ] ; then echo "Simple test success" ; fi
fi


#####################################################
#  Known text checks  (data made with perl script)
#####################################################

function known {
    kC=$4
    kM=$3
    kB=$2
    B=`../run/base64conv 2>/dev/null -i raw -q -e -o cryptBS $1`
    C=`../run/base64conv 2>/dev/null -i raw -q -e -o crypt $1`
    M=`../run/base64conv 2>/dev/null -i raw -q -e -o mime $1`
    T=yes
    if [ x$B != x$kB ];
    then
        echo "Known test failed (cryptBS). '$1' should be '$kB' not '$B'"
        T=no
    fi
    if [ x$M != x$kM ];
    then
        echo "Known test failed (mime). '$1' should be '$kM' not '$M'"
        T=no
    fi
    if [ x$C != x$kC ];
    then
        echo "Known test failed (crypt). '$1' should be '$kC' not '$C'"
        T=no
    fi
    C2=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o crypt $B`
    M2=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o mime $B`
    if [ x$M2 != x$kM ];
    then
        echo "Known test failed (cryptBS->mime). '$1' should be '$kM' not '$M2'"
        T=no
    fi
    if [ x$C2 != x$kC ];
    then
        echo "Known test failed (cryptBS->crypt). '$1' should be '$kC' not '$C2'"
        T=no
    fi
    B2=`../run/base64conv 2>/dev/null -i crypt -q -e -o cryptBS $C`
    M2=`../run/base64conv 2>/dev/null -i crypt -q -e -o mime $C`
    if [ x$M2 != x$kM ];
    then
        echo "Known test failed (crypt->mime). '$1' should be '$kM' not '$M2'"
        T=no
    fi
    if [ x$B2 != x$kB ];
    then
        echo "Known test failed (crypt->cryptBS). '$1' should be '$kB' not '$B2'"
        T=no
    fi
    B2=`../run/base64conv 2>/dev/null -i mime -q -e -o cryptBS $M`
    C2=`../run/base64conv 2>/dev/null -i mime -q -e -o crypt $M`
    if [ x$C2 != x$kC ];
    then
        echo "Known test failed (mime->crypt). '$1' should be '$kC' not '$C2'"
        T=no
    fi
    if [ x$B2 != x$kB ];
    then
        echo "Known test failed (mime->cryptBS). '$1' should be '$kB' not '$B2'"
        T=no
    fi
    if [ x$T = "xyes" ];
    then
        if [ $Q = "N" ] ; then echo "Success known test param = $1" ; fi
    else
        F=1
        echo "Failure known test param = $1"
    fi
}

known abcdefghijklmnopqrstuvwxyz12345 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1Bp. YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NQ MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBE
known abcdefghijklmnopqrstuvwxyz123456 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpM1 YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHM
known abcdefghijklmnopqrstuvwxyz1234567 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnB YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3 MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMr
known abcdefghijklmnopqrstuvwxyz12345678 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBs. YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3OA MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC.

known abcdefghijklmnopqrstuvwxyz123456789 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1 YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODk MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1Y
known abcdefghijklmnopqrstuvwxyz1234567890 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1A YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkw MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1Yk
known abcdefghijklmnopqrstuvwxyz12345678901 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1Al. YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwMQ MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1YkAE
known abcdefghijklmnopqrstuvwxyz123456789012 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1Al61 YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwMTI MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1YkAH6

known abcdefghijklmnopqrstuvwxyz1234567890123 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1Al6nA YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwMTIz MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1YkAH6n
known abcdefghijklmnopqrstuvwxyz12345678901234 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1Al6nAo. YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwMTIzNA MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1YkAH6nB.
known abcdefghijklmnopqrstuvwxyz123456789012345 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1Al6nAoI1 YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwMTIzNDU MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1YkAH6nB1I
known abcdefghijklmnopqrstuvwxyz1234567890123456 V7qMYJaNbVKOeh4PhtqPk3bQnFLRqR5StdLAmA1BpMnBsY1Al6nAoIXB YWJjZGVmZ2hpamtsbW5vcHFyc3R1dnd4eXoxMjM0NTY3ODkwMTIzNDU2 MK7XN4JaNqVdOahgPKtjQ53mQrFpRbRsSLclAXAoBHMrC1YkAH6nB1Iq

# null check.  Make sure we can properly handle NULL buffers.
if [ $Q = "N" ] ; then echo "performing NULL checks" ; fi
T=yes
B2=000000000000
C2=........
B=`../run/base64conv 2>/dev/null -q -i hex -o crypt $B2`
C=`../run/base64conv 2>/dev/null -q -o hex -i crypt $C2`
if [ x$B != "x$C2" -o x$C != "x$B2" ];
then
    echo "failed! crypt";
    T=no
fi
B=`../run/base64conv 2>/dev/null -q -i hex -o cryptBS $B2`
C=`../run/base64conv 2>/dev/null -q -o hex -i cryptBS $C2`
if [ x$B != "x$C2" -o x$C != "x$B2" ];
then
    echo "failed! cryptBS";
    T=no
fi
C2=AAAAAAAA
B=`../run/base64conv 2>/dev/null -q -i hex -o mime $B2`
C=`../run/base64conv 2>/dev/null -q -o hex -i mime $C2`
if [ x$B != "x$C2" -o x$C != "x$B2" ];
then
    echo "failed! mime";
    T=no
fi
if [ x$T = "xyes" ];
then
    if [ $Q = "N" ] ; then echo "ALL null tests were valid" ; fi
else
    F=1
fi

#########################################
# Conversion from all formats
# to others tests, for many
# lengths.
#########################################

function comp {
    if [ x$1 != x$2 ];
    then
        echo "$3: '$1' is not equal to '$2'"
        T=no
    fi
}

function tst {
    T=yes
    B=`../run/base64conv 2>/dev/null -i raw -q -e -o cryptBS $1`
    C=`../run/base64conv 2>/dev/null -i raw -q -e -o crypt $1`
    M=`../run/base64conv 2>/dev/null -i raw -q -e -o mime $1`

    R=`../run/base64conv 2>/dev/null -i crypt -q -e -o cryptBS $C`
    R=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o raw $R`
    comp x$1 x$R "crypt_cryptBS (1)"

    R=`../run/base64conv 2>/dev/null -i mime -q -e -o cryptBS $M`
    R=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o raw $R`
    comp x$1 x$R "mime_cryptBS (2)"

    R=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o crypt $B`
    R=`../run/base64conv 2>/dev/null -i crypt -q -e -o raw $R`
    comp x$1 x$R "cryptBS_crypt (3)"

    R=`../run/base64conv 2>/dev/null -i mime -q -e -o crypt $M`
    R=`../run/base64conv 2>/dev/null -i crypt -q -e -o raw $R`
    comp x$1 x$R "mime_crypt (4)"

    R=`../run/base64conv 2>/dev/null -i cryptBS -q -e -o mime $B`
    R=`../run/base64conv 2>/dev/null -i mime -q -e -o raw $R`
    comp a$1 a$R "cryptBS_mime (5)"

    R=`../run/base64conv 2>/dev/null -i crypt -q -e -o mime $C`
    R=`../run/base64conv 2>/dev/null -i mime -q -e -o raw $R`
    comp b$1 b$R "crypt_mime (6)"

    if [ x$T = "xyes" ];
    then
        if [ $Q = "N" ] ; then echo "Success multi-convert test param = $1" ; fi
    else
        F=1
        echo "Failure multi-convert test param = $1"
    fi
}

P=fadsgragabsrgahseeEDTa
tst $P
P=fadsgragabsrgahseeEDTa0
tst $P
P=fadsgragabsrgahseeEDTa0~
tst $P
P=fadsgragabsrgahseeEDTa0~~
tst $P
P=fadsgragabsrgahseeEDTa06x~
tst $P
P=xyhadhWaeFgAcwbsex03dz
tst $P
P=xyhadhWaeFgAcwbsex03dzZ
tst $P
P=xyhadhWaeFgAcwbsex03dzZ~
tst $P
P=xyhadhWaeFgAcwbsex03dzZ~~
tst $P
P=xyhadhWaeFgAcwbsex03dzZ~Z!
tst $P
#############################  Total random data (79 character working set)
P=PoQC,jTymI=GAPzLqs#B1@T-
tst $P
P=kbHAP_E3YWQk0/DhFj,zwO_,y
tst $P
P=p#OzRPQmEbgA!s:@dZ9nY@0dM,
tst $P
P=VGS%nUC0!@.#n3vOEDylfwA-}Rm
tst $P
P=zn}O=GYzi=LmXREZ,yYGuMNCcmZd
tst $P
P=QC*9P*myY5bAmebFK!TU4GQcZBUTA
tst $P
P=}mbfdKKG4cAxiDFfOLmO0kV{6Hg:nB
tst $P
P=~AaQZgLQ2Gxw11V_^KMVsi1pz0eR=m{
tst $P
P=V#@*jGWk=hq_p~h7B%JpDa%y
tst $P
P=uKHo,ipa7zpAeP4^/3oslwrrQ
tst $P
P=g%Fz_MN,0z~{/WJdp5BYhfH_L5
tst $P
P=,60L4e?Q=sNgBjRMI7Msec~mmf=
tst $P
P=8yQDJ4TpZJS0EgUCisBHtLO?k:LU
tst $P
P=rn-p5!JD4FyS-e41C=B:G__SMt!7z
tst $P
P=LvCRbk9bv1EuOn0PeX7AioktY2Lo2f
tst $P
P=.UusOL3m-m?rJC,a73od--KHUFpFLV5
tst $P
P=U3CrvW7Sey!YVF8_}c5dv8,3
tst $P
P=vc#uqCCyQHG_H@iXYI!1Ekbew
tst $P
P=/AVO!,lcQDX=u}PaOU7iaWAyW}
tst $P
P=H7BX8}iLz95AETxC@MDO@l@lS^6
tst $P
P=F15off04-HvYwrpat#9}vhd6umLv
tst $P
P=vWwUr6WBw0eRq@hW~RAUwyu%AR/l2
tst $P
P=8{NI-Kf9Kz0A=Xsx1SDYc?yMG2@fyr
tst $P
P=a^Tbt51QvhiTK2#2S-!z7cP*dRNPB6A
tst $P
P=C.?OkU=62rb8ZW6DS8D5S6!G
tst $P
P=xe0_mbgdqClK1MDK4zdSo-zyH
tst $P
P=3=4xxAcCUJd:m0/DsO%bTeE^An
tst $P
P=7qu*9pIvL~x@BmKxry?kwNn%*?W
tst $P
P=ANnvk@?EkSOR-=^}GdYrmpl6DtTg
tst $P
P=w7gak0XC9sVsX7qf~_Dph,A0v2B99
tst $P
P=~{0zP7#1MgxbU8u^u?B1bZD#8TFg~{
tst $P
P=w:~oS_!pBqlhVC@4z5Uj04}r?8u*wo%
tst $P
P=?bNfxfP5Oogw85@cB4,5dt5Q
tst $P
P=9Dk:Vmw#*}Okprf2sLTtg1N89
tst $P
P=WD2K}e*dzm0i-84,}Ff2la}oeY
tst $P
P=RY:Zv:tNzY~6WcYO/6}jjm~.Rj}
tst $P
P=rW~GRuv_3W}Ro5YBym3QRx@g}ad?
tst $P
P=./e6/T%KpX.@xE{/UUESK4fHnF~NH
tst $P
P=a{P,r!tHVgeH=}-*-Lr9KQsFX6040u
tst $P
P=S7iyHD5d/?65xM6cSJ@malnCBgwJ%OB
tst $P
P=onKq6-4-TjJzE8A^r5C31W/n
tst $P
P=BvNYgH/:UO/*xHbVnTk}=/VQI
tst $P
P=h1phkGu~i_DManJj{R{i}B8t2J
tst $P
P=!JTaAdEh5J,CGGj5o6Rq*T?%S/C
tst $P
P=TjNcj6BKTp8dn^^PJy,pqUAarE-{
tst $P
P=nTV.f_*1~Fu5TbE2c#%eTa*rtP?hd
tst $P
P=rGxH6d2-il/EDhkoGg5Hu8Dt2Ag%{,
tst $P
P=g2x2pm@VwIe3gsS}j7oS^!2Gt89n:j!
tst $P
P=VfxMYgm1Fj4amecMxwG7aGZJ
tst $P
P=Bq%*3t_WQK-L!wjO0DHhB1zur
tst $P
P=x-%EfHz7K5gXMxoUfB5fy#rwJD
tst $P
P=@i3Ud53sWo5O}fbo5a/@tVSPiEO
tst $P
P=t=/j?jDh/w={,YKg5mI@lywrf#QT
tst $P
P=7,s~tDgk?lB5lxl6!pq5Xu/@s:RHE
tst $P
P=?vi2zpI3Tskh_D%6{3lX2gKpvlIWjN
tst $P
P=?zdcv4K:0G-a,vgn?oeI4YwoW%Aua68
tst $P
P=MA1=Zk,sax%SfX8Zsmctl{tA
tst $P
P=}RvIWwBMNWCG8sKy7:e{%0gph
tst $P
P=Yqvylp6J8VJiDIjD3}e}YIkhgj
tst $P
P=Je-.F7,uCyE.dOQ?EFXZlsGJ^An
tst $P
P=:80=Axv}Te,D%Jbm?kBYj0N!*^G:
tst $P
P=pk-AsxOFR6PjIf?5~@tTK2O*F0*jl
tst $P
P=YxafCV0Y6~hf*NejEIO}d_Y@YeO%#m
tst $P
P=?1FM^6Al=2j:A:rqXtj3Y/}F?4dc1op
tst $P
P=tCt6Zp1AU7lg3Odr/,FyK%6N
tst $P
P=qXcXV5l,WxyzL07gAD3ErWt8M
tst $P
P=N^US17db.UPyCFytM@Zi61Jw7H
tst $P
P=T7V=j_isiXTLhlcEFUvMD*a3Y38
tst $P
P=vYSTO~MTgv_858XO@@4wgxVZyxiZ
tst $P
P=n*Qf{DaPAn%9pPAn-O0}8D{wybx=H
tst $P
P=.4UB2waQQid#y20WEj{Pq-MC1-~Mf^
tst $P
P=9*,bFT@ZR%,NC9/L8L_0sDx#8dNzCPK
tst $P
P=:77Ewp}pAbvvgR@%PeP1QYd^
tst $P
P=_zvLTkP0_{ZscGIou:KM8LAM8
tst $P
P=h:UbNTGHm%D6ir~zvqL4us_X1d
tst $P
P=.UXe%~K3Qtizdj80*nc#Hj%C=to
tst $P
P=I!CRw1V:mN0L@^D0O?aMN%DBk?f-
tst $P
P=BmxKQkHMIt2j:C=?hUP.ZIRiyA7f{
tst $P
P={Sa,u/{d=.rWKc3{8ygV!cyIVA*=3H
tst $P
P=c5LZJcSu8HhpH%7=BdEIo}2#iMS4fwS
tst $P

# if there were no failures, then list so. This is so there
# is SOME output in -q mode, if all tests passed.
if [ x$F = "x0" ] ; then echo "All tests succeeded" ; fi

