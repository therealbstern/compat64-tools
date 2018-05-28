#!/bin/sh
# $Id: massconvert64.sh,v 1.79 2018/01/28 15:57:09 eha Exp eha $

# Written 2009, 2010, 2011, 2012, 2013  Eric Hameleers, Eindhoven, NL
# Copyright 2018  Ben Stern <bas-github@fortian.com>

# Convert 64-bit slackware packages 'en masse' into compatibility packages to be
# installed on slackware32 - providing the 64-bit part of multilib.  The string
# "-compat64" is added at the end of package name when a compatibility package
# gets created.  This allows it to be installed on slackware32 alongside the
# native 32-bit versions.
# For example: the original 64-bit package "bzip2" will be converted to a new
#              package with the name "bzip2-compat64"
# You also have to install multilib versions of glibc and gcc!

# Before we start...
[ -x /bin/id ] && CMD_ID="/bin/id" || CMD_ID="/usr/bin/id"
if [ "$($CMD_ID -u)" != "0" ]; then
  echo "You need to be root to run $(basename $0)."
  exit 1
fi

# Should we be verbose?
VERBOSE=${VERBOSE:-1}

# Do we really convert the packages or only pretend to?
DRYRUN=0

# In case we need temporary storage:
TMP=${TMP:-/tmp}
mkdir -p $TMP
if [ ! -w "$TMP" ]; then
  echo "Can not write to temporary directory '$TMP'!"
  exit 3
fi

# Zero some other variables:
unset SLACK64ROOT
unset SLACK64URL
unset TARGET32ROOT

# Helpful instructions in case the user asks for it:
function show_help () {
  # Write the help text to output:
  cat <<EOF

Usage: $0 <-i 64-bit_package_tree|-u 64-bit_package_url> [-d output_directory]

$(basename $0) converts an essential subset of 64-bit Slackware packages into
'compatibility' packages for 32-bit Slackware.

Required parameter - one of these two:
-i 64-bit_package_tree    A 64-bit Slackware package-tree. It should have the a,
                          ap, d, ..., y directories immediately below it.
-u 64-bit_package_url     The URL of a http or ftp server containing 64-bit
                          Slackware packages. It should have the a, ap, d, .., y
                          directories immediately below it.
Optional parameters:
-d destination_directory  Create packages in this directory.  By default, the
                          new packages will be created in the current directory.
-n                        Dry-run (do not convert packages, just mention their
                          names).
-q                        Only print output if packages are actually being
                          converted (useful for cron jobs).

Example of a useable Slackware URL:
  http://slackware.mirrors.tds.net/pub/slackware/slackware64-14.2/slackware

EOF
}

# Parse the command-line parameters:
while [ ! -z "$1" ]; do
  case $1 in
    -d|--destdir)
      TARGET32ROOT="$(cd $(dirname "${2}"); pwd)/$(basename "${2}")"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -i|--inputdir)
      SLACK64ROOT="$(cd $(dirname "${2}"); pwd)/$(basename "${2}")"
      shift 2
      ;;
    -n|--dry-run)
      DRYRUN=1
      shift
      ;;
    -q|--quiet)
      VERBOSE=0
      shift
      ;;
    -u|--inputurl)
      SLACK64URL="${2}"
      shift 2
      ;;
    -*)
      echo "Unsupported parameter '$1'!"
      exit 1
      ;;
    *)
      # Do nothing
      shift
      ;;
  esac
done

# A function to determine if there are spaces in the pathname:
function contains_spaces () {
  local CHOPPED=$(echo "$1" | tr -d ' ')
  [ "x$CHOPPED" = "x$1" ] && return 1 || return 0
}

# A function to get a package's URL in the repository:
function get_url_pkg () {
  local BP="$(basename $1)"
  local PS="$(dirname $1)"

  local DURL="$2"

  for FP in $(lftp -c 'open '${DURL}' ; cls -1 '${PS}/${BP}'-*.t?z' 2>/dev/null) ZALIEN ; do
    if [ "$(echo "$FP"|rev|cut -d- -f4-|cut -d/ -f1| rev)" = "$BP" ];
    then
      break
    fi
  done
  [ "$FP" != "ZALIEN" ] && echo "$DURL/$FP" || echo ""
}

# A function to retrieve the full name of a package:
function get_pkgfullpath () {
  local IP="$1"
  local BP="$(basename $1)"
  local FP=""

  for FP in $(ls ${IP}-*.t?z 2>/dev/null) ZALIEN; do
    if [ "$(echo "$FP"|rev|cut -d- -f4-|cut -d/ -f1| rev)" = "$BP" ];
    then
      break
    fi
  done
  [ "$FP" != "ZALIEN" ] && echo "$FP" || echo ""
}

# A function to convert a package, downloading it first if needed, and taking
# patches into account:
function conv_pkg () {
  local BP="$1"
  local SERIES="$2"
  local PATCHLIST="$3"
 
  PKGPATH="$SERIES/$BP"
  REPOFOUND=""

  # First find out if the requested package exists in the repository:
  # Two repo location options: URL or local directory.
  if [ -n "$SLACK64URL" ]; then
    FULLURL=$(get_url_pkg $PKGPATH $SLACK64URL)
    if [ -n "$FULLURL" ]; then
      FULLPKG=$SLACK64ROOT/$SERIES/$(basename $FULLURL)
      REPOVERSION=$(basename $FULLURL |rev |cut -d- -f3 |rev)
      REPOBLD="$(basename $FULLURL |rev |cut -d- -f1 |cut -d. -f2- |rev)"
    else
      # Package could not be found on the remote server:
      FULLPKG=""
      REPOVERSION=""
      REPOBLD=""
    fi
  else
    FULLPKG=$(get_pkgfullpath $SLACK64ROOT/$PKGPATH)
    if [ -n "$FULLPKG" ]; then
      REPOVERSION="$(basename $FULLPKG |rev |cut -d- -f3 |rev)"
      REPOBLD="$(basename $FULLPKG |rev |cut -d- -f1 |cut -d. -f2- |rev)"
    else
      REPOVERSION=""
      REPOBLD=""
    fi
  fi

  if [ -n "$FULLPKG" ]; then
    # The requested original was found in the repository.
    REPOFOUND="yes"
    # Does the package we want have a patch available?
    echo "$PATCHLIST" | tr - _ | grep -wq $(echo $BP |tr - _)
    if [ $? -eq 0 ]; then
      [ $VERBOSE -eq 1 ] && echo "--- Using Slackware's patch package for $BP"
      PKGPATH="../patches/packages/$BP"
      if [ -n "$SLACK64URL" ]; then
        FULLURL=$(get_url_pkg $PKGPATH "$(dirname $SLACK64URL)/patches")
        if [ -n "$FULLURL" ]; then
          FULLPKG=$SLACK64ROOT/$SERIES/$(basename $FULLURL)
          REPOVERSION=$(basename $FULLURL |rev |cut -d- -f3 |rev)
          REPOBLD="$(basename $FULLURL |rev |cut -d- -f1 |cut -d. -f2- |rev)"
        else
          FULLPKG=""
          REPOVERSION=""
          REPOBLD=""
        fi
      else
        FULLPKG=$(get_pkgfullpath $SLACK64ROOT/$PKGPATH)
        if [ -n "$FULLPKG" ]; then
          REPOVERSION="$(basename $FULLPKG |rev |cut -d- -f3 |rev)"
          REPOBLD="$(basename $FULLPKG |rev |cut -d- -f1 |cut -d. -f2- |rev)"
        else
          REPOVERSION=""
          REPOBLD=""
        fi
      fi
    fi
  fi

  if [ -z "$FULLPKG" ]; then
    if [ -n "$REPOFOUND" ]; then
      [ $VERBOSE -eq 1 ] && echo "*** FAIL: patch-package for '$BP' was not found in repository (original package present, this means a repository mismatch)!"
    else
      [ $VERBOSE -eq 1 ] && echo "*** FAIL: package '$BP' was not found in repository!"
    fi
    continue
  fi

  # Package (or patch) available - let's start!

  # Do we have a local converted package already?
  HAVE_COMPAT64="$(get_pkgfullpath $TARGET32ROOT/${SERIES}-compat64/$BP-compat64)"
  if [ -n "$HAVE_COMPAT64" ]; then
    COMPAT64VERSION="$(echo "$HAVE_COMPAT64" |rev|cut -d- -f3|rev)"
    COMPAT64BLD="$(echo "$HAVE_COMPAT64" |rev|cut -d- -f1|cut -d. -f2-|rev)"
    if [ "$COMPAT64VERSION" = "$REPOVERSION" -a "${COMPAT64BLD%compat64}" = "$REPOBLD" ]
    then
      [ $VERBOSE -eq 1 ] && echo "--- ${BP}-compat64 version '$COMPAT64VERSION' already available"
    else
      if [ $DRYRUN -eq 0 ]; then
        echo ">>> Deleting old version '$COMPAT64VERSION' of '${BP}-compat64'"
      else
        echo "${BP}: existing package needs update"
      fi
      FILE_TO_REMOVE=$HAVE_COMPAT64
      HAVE_COMPAT64=""
    fi
  else
    if [ $DRYRUN -eq 1 ]; then
      echo "${BP}: new package will be converted"
    fi
  fi

  # If we do not have the latest -compat64 package, then run the conversion:
  if [ ! -n "$HAVE_COMPAT64" -a $DRYRUN -eq 0 ]; then

    if [ -n "$SLACK64URL" ]; then
      # Download the Slackware package before converting it:
      ( mkdir -p $SLACK64ROOT/$SERIES
        cd $SLACK64ROOT/$SERIES
        lftp -c "open $(dirname $FULLURL) ; get $(basename $FULLURL)" 2>/dev/null
      )
    fi

    [ $VERBOSE -eq 1 ] && echo "--- $BP"
    # Convert the Slackware package into a -compat64 version:
    sh $CONV64 -i $FULLPKG -d $TARGET32ROOT/${SERIES}-compat64

    if [ -n "$FILE_TO_REMOVE" ]; then
      # This is where we delete an older version of the -compat64 package:
      rm $(echo $FILE_TO_REMOVE | rev | cut -d. -f2- | rev).*
      FILE_TO_REMOVE=""
    fi
  fi
}

# Safety checks in case a URL was provided: 
if [ -n "$SLACK64URL" ]; then
  if [ -n "$SLACK64ROOT" ]; then
    echo "*** Options '-i' and '-u' can not be used together!"
    exit 1
  else
    # Define a 'temporary' root directory where we will download packages:
    SLACK64ROOT="${TMP}/alienBOB/slackware"
    if ! which lftp 1>/dev/null 2>&1 ; then
      echo  "No lftp binary detected! Need lftp for package downloading!"
      exit 1
    fi
  fi
fi

# The root directory of 64-bit Slackware packages
# (should have the a,ap,d,..,y directories immediately below):
# Let's use a fallback directory in case none was specified:
SLACK64ROOT="${SLACK64ROOT:-"/home/ftp/pub/Linux/Slackware/slackware-current/slackware"}"

# The output directory for our converted packages; defaults to the current dir.
# Note that {a,ap,d,l,n,x}-compat64 directories will be created below this
# directory if they do not yet exist:
TARGET32ROOT="${TARGET32ROOT:-"$(pwd)"}"

# Abort if we got directories with spaces in them:
if contains_spaces "$SLACK64ROOT" ; then
  echo "Directories with spaces are unsupported: '$SLACK64ROOT'!"
  exit 1
fi
if contains_spaces "$TARGET32ROOT" ; then
  echo "Directories with spaces are unsupported: '$TARGET32ROOT'!"
  exit 1
fi

# Where the scripts are:
SRCDIR=$(cd $(dirname $(which $0)); pwd)

# The script that does the package conversion:
CONV64=$SRCDIR/convertpkg-compat64

# Bail out if the conversion script is not available/working:
if [ ! -f $CONV64 ]; then
  echo "Required script '$CONV64' is not present or not executable! Aborting..."
  exit 1
fi

# We can not proceed if there are no packages and we did not get an URL:
if [ -z "$SLACK64URL" ]; then
  if [ ! -d $SLACK64ROOT/a -o ! -d $SLACK64ROOT/ap -o ! -d $SLACK64ROOT/d -o ! -d $SLACK64ROOT/l -o ! -d $SLACK64ROOT/n -o ! -d $SLACK64ROOT/x -o ! -d $SLACK64ROOT/xap ]; then
    echo "Required package directories a,ap,d,l,n,x,xap below '$SLACK64ROOT' are not found! Aborting..."
    exit 1
  fi
fi

# If a destination_directory was specified, abort now if we can not create it:
if [ -n "$TARGET32ROOT" -a ! -d "$TARGET32ROOT" ]; then
  echo "Creating output directory '$TARGET32ROOT'..."
  mkdir -p $TARGET32ROOT
  if [ ! -w "$TARGET32ROOT" ]; then
    echo "Creation of output directory '$TARGET32ROOT' failed!"
    exit 3
  fi
fi

# Get a list of available patches
if [ -n "$SLACK64URL" ]; then
  PATCH_LIST=$(echo $(lftp -c "open $(dirname $SLACK64URL)/patches/packages/ ; cls *.t?z" 2>/dev/null | rev | cut -f4- -d- |rev))
else
  PATCH_LIST=$(echo $(cd $(dirname $SLACK64ROOT)/patches/packages/ 2>/dev/null ; ls -1 *.t?z 2>/dev/null | rev | cut -f4- -d- |rev))
fi

# This is the script's internal list of what I consider as the essential
# 64-bit multilib package set for your Slackware32:

# The A/ series:
A_COMPAT64="
aaa_elflibs
attr
bzip2
cups
cxxlibs
dbus
e2fsprogs
eudev
libgudev
lzlib
openssl-solibs
plzip
udev
util-linux
xz
"

# The AP/ series:
AP_COMPAT64="
cups
cups-filters
flac
mariadb
mpg123
mysql
sqlite
"

# The D/ series:
D_COMPAT64="
libtool
llvm
opencl-headers
"

# The L/ series:
L_COMPAT64="
Mako
SDL2
alsa-lib
alsa-oss
alsa-plugins
atk
audiofile
cairo
dbus-glib
elfutils
esound
expat
ffmpeg
fftw
freetype
fribidi
gamin
gc
gdk-pixbuf2
giflib
glib2
gmp
gnome-keyring
gtk+2
gst-plugins-base
gst-plugins-base0
gst-plugins-good
gst-plugins-good0
gst-plugins-libav
gstreamer
gstreamer0
hal
harfbuzz
icu4c
jasper
json-c
lame
lcms
lcms2
libaio
libarchive
libart_lgpl
libasyncns
libclc
libedit
libelf
libexif
libffi
libglade
libgphoto2
libidn
libidn2
libieee1284
libjpeg
libjpeg-turbo
libmng
libmpc
libnl3
libnotify
libogg
libpcap
libpng
libsamplerate
libsndfile
libtasn1
libtermcap
libtiff
libunistring
libunwind
libusb
libvorbis
libwebp
libxml2
libxslt
lzo
ncurses
ocl-icd
openjpeg
orc
pango
popt
pulseaudio
python-six
qt
readline
sbc
sdl
seamonkey-solibs
speexdsp
startup-notification
svgalib
talloc
tdb
tevent
v4l-utils
zlib
"

# The N/ series:
N_COMPAT64="
curl
cyrus-sasl
gnutls
libgcrypt
libgpg-error
libtirpc
nettle
openldap-client
openssl
p11-kit
samba
"

# The X/ series:
X_COMPAT64="
fontconfig
freeglut
glew
glu
intel-vaapi-driver
libFS
libICE
libSM
libX11
libXScrnSaver
libXTrap
libXau
libXaw
libXcomposite
libXcursor
libXdamage
libXdmcp
libXevie
libXext
libXfixes
libXfont
libXfont2
libXfontcache
libXft
libXi
libXinerama
libXmu
libXp
libXpm
libXprintUtil
libXrandr
libXrender
libXres
libXt
libXtst
libXv
libXvMC
libXxf86dga
libXxf86misc
libXxf86vm
libdmx
libdrm
libepoxy
libfontenc
libinput
libpciaccess
libva
libva-intel-driver
libvdpau
libwacom
libxcb
libxshmfence
mesa
pixman
vulkan-sdk
xcb-util
"

# The XAP/ series:
XAP_COMPAT64="
sane
"

# Create target directories if they do not exist:
for TDIR in a-compat64 ap-compat64 d-compat64 l-compat64 n-compat64 x-compat64 xap-compat64 ; do
  mkdir -p $TARGET32ROOT/$TDIR
  if [ ! -w $TARGET32ROOT/$TDIR ]; then
    echo "Directory '$TARGET32ROOT/$TDIR' is not writable! Aborting..."
    exit 1
  fi
done

# Convert the 64-bit packages from A AP D L N and X series, checking for patches:
[ $VERBOSE -eq 1 ] && echo "*** Starting the conversion process:"

[ $VERBOSE -eq 1 ] && echo "*** 'A' series:"
for INPKG in $A_COMPAT64 ; do
  conv_pkg $INPKG a "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'AP' series:"
for INPKG in $AP_COMPAT64 ; do
  conv_pkg $INPKG ap "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'D' series:"
for INPKG in $D_COMPAT64 ; do
  conv_pkg $INPKG d "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'L' series:"
for INPKG in $L_COMPAT64 ; do
  conv_pkg $INPKG l "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'N' series:"
for INPKG in $N_COMPAT64 ; do
  conv_pkg $INPKG n "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'X' series:"
for INPKG in $X_COMPAT64 ; do
  conv_pkg $INPKG x "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'XAP' series:"
for INPKG in $XAP_COMPAT64 ; do
  conv_pkg $INPKG xap "$PATCH_LIST"
done

# Mention downloaded packages if we used a URL as source:
if [ $VERBOSE -eq 1 -a $DRYRUN -eq 0 -a  -n "$SLACK64URL" ]; then
  echo "WARNING: packages which were downloaded from '$SLACK64URL'"
  echo "have been left in directory '$SLACK64ROOT'."
  echo "It is safe to remove these now."
  echo ""
fi

[ $VERBOSE -eq 1 ] && echo "*** Conversion done!"

