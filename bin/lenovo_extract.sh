#!/usr/bin/env bash

set -e
set -o pipefail

TOP="$( cd "$( dirname "${BASH_SOURCE[0]}" )"/.. >/dev/null 2>&1 && pwd )"

# list of supported board targets
SUPPORTED=("x220" "x230" "t430" "t530" "w530")

function printusage {
  echo "Usage: $0 -f <romdump> -t <target board> -f -m <me_cleaner>(optional) -i <ifdtool>(optional)"
  printsupported
  exit 0
}

function printsupported {
  echo "Supported targets: ${SUPPORTED[@]}"
}

[ "$#" -eq 0 ] && printusage

while getopts ":f:t:m:i:" opt; do
  case $opt in
    f)
      FILE="$OPTARG"
      ;;
    t)
      BOARD="$(echo $OPTARG | awk '{print tolower($0)}')"
      ;;
    m)
      if [ -x "$OPTARG" ]; then
        MECLEAN="$OPTARG"
      fi
      ;;
    i)
      if [ -x "$OPTARG" ]; then
        IFDTOOL="$OPTARG"
      fi
      ;;
  esac
done

if [ -z "$MECLEAN" ]; then
  MECLEAN=`command -v $TOP/build/coreboot-*/util/me_cleaner/me_cleaner.py 2>&1`
  if [ -z "$MECLEAN" ]; then
    echo "me_cleaner.py required but not found or specified with -m. Aborting."
    exit 1;
  fi
fi

if [ -z "$IFDTOOL" ]; then
  IFDTOOL=`command -v $TOP/build/coreboot-*/util/ifdtool/ifdtool 2>&1`
  if [ -z "$IFDTOOL" ]; then
    echo "ifdtool required but not found or specified with -m. Aborting."
    exit 1;
  fi
fi

if [ -z "$BOARD" ]; then
  echo "specify target with -t."
  printsupported
  exit 1;
fi

for supported in "${SUPPORTED[@]}"; do
  [ "$BOARD" == "$supported" ] && _FOUND="y" && break
done

if [ -z "$_FOUND" ]; then
  echo " selected board $BOARD not supported"
  printsupported
  exit 1
fi

case $(wc -c $FILE | awk '{print $1;}') in
  8388608)
    SIZE="8MiB"
    ;;
  12582912)
    SIZE="12MiB"
    ;;
  *)
    echo "romdump size does not match"
    exit 1
esac
  

BLOBSDIR="$TOP/blobs/$BOARD"
mkdir -p "$BLOBSDIR"

echo "firmware rom: $FILE"
echo "me_cleaner: $MECLEAN"
echo "ifdtool: $IFDTOOL"

bioscopy=$(mktemp)
extractdir=$(mktemp -d)

cp "$FILE" $bioscopy

# soft disable only
$IFDTOOL -M 1 $bioscopy

# extract ifd modules
cd "$extractdir"
$IFDTOOL -x "$bioscopy"
cd -

cp "$extractdir/flashregion_0_flashdescriptor.bin" "$BLOBSDIR/ifd.bin"

cp "$extractdir/flashregion_2_intel_me.bin" "$BLOBSDIR/me.bin"
$MECLEAN -r -t "$extractdir/flashregion_2_intel_me.bin"
cp "$extractdir/flashregion_2_intel_me.bin" "$BLOBSDIR/minimal_me.bin"

cp "$extractdir/flashregion_3_gbe.bin" "$BLOBSDIR/gbe.bin"

# modify and extract ifd
cd "$extractdir"
$IFDTOOL -n "$TOP/fmaps/${SIZE}_minimal_me.layout" "$bioscopy"
$IFDTOOL -x "${bioscopy}.new"
cd -
cp "$extractdir/flashregion_0_flashdescriptor.bin" "$BLOBSDIR/ifd-minimal_me.bin"

# clean
rm "$bioscopy" "${bioscopy}.new"
rm -r "$extractdir"
