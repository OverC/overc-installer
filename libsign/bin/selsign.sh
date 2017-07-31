#!/bin/bash

S="${BASH_SOURCE[0]}"
D=`dirname "$S"`
LIBSIGN_ROOT="`cd "$D"/.. && pwd`"

echo "LIBSIGN_ROOT=$LIBSIGN_ROOT"

cmd="LD_LIBRARY_PATH=$LIBSIGN_ROOT/lib $LIBSIGN_ROOT/bin/selsign"
cmd_opts=""
out=".p7b"
verbose=0

while [ $# -gt 0 ]; do
    case "$1" in
    -d|--detached)
        cmd_opts=$cmd_opts" -d"
        out=".p7s"
        ;;
    -a|--content-attached)
        cmd_opts=$cmd_opts" -a"
        out=".p7a"
        ;;
    -k|--key)
        cmd_opts=$cmd_opts" -k $2"
        shift
        ;;
    -c|--cert)
        cmd_opts=$cmd_opts" -c $2"
        shift
        ;;
    -v|--verbose)
        verbose=1
        ;;
    *)
        break
        ;;
    esac
    shift
done

[ -z "$1" -o ! -f "$1" ] && {
    eval "$cmd"
    exit 1
}

eval "$cmd $cmd_opts $1"

[ $? -eq 0 -a -s "$1$out" -a $verbose -eq 1 ] &&
    openssl pkcs7 -in "$1$out" -inform DER -print -text -noout

exit 0
