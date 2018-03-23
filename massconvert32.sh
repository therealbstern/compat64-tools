#!/bin/bash
# $Id: massconvert32.sh,v 1.79 2018/01/28 15:57:09 eha Exp eha $
#
# Written 2009, 2010, 2011, 2012, 2013  Eric Hameleers, Eindhoven, NL
#
# Convert 32bit slackware packages 'en masse' into compatibility packages
# to be installed on slackware64 - providing the 32bit part of multilib.
# The string "-compat32" is added at the end of package name when a
# compatibility package gets created.  This allows it to be installed
# on slackware64 alongside the native 64bit versions.
# For example: the original 32bit package "bzip2" will be converted to a new
#              package with the name "bzip2-compat32"
#
# You also have to install multilib versions of glibc and gcc !

# Before we start
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
SLACK32ROOT=""
SLACK32URL=""
TARGET64ROOT=""

# Helpful instructions in case the user asks for it:
function show_help () {
  # Write the help text to output:
  cat <<EOF

Usage: $0 <-i 32bit_package_tree|-u 32bit_package_url>  [-d output_directory]

$(basename $0) converts an essential subset of 32-bit Slackware
packages into 'compatibility' packages for 64-bit Slackware.

Required parameter - one of these two::
  -i 32bit_package_tree        A 32bit Slackware package-tree. It should have
                               the a,ap,d,..,y directories immediately below.
  -u 32bit_package_url         The URL of a http or ftp server containing 32bit
                               Slackware packages. It should have the
                               a,ap,d,..,y directories immediately below.
Optional parameter::
  -d destination_directory     create packages in this directory.
                               By default, the new packages will be created
                               in your current directory.
  -n                           Dry-run (do not convert packages, just mention
                               their names).
  -q                           Only print output if packages are actually being
                               converted (useful for cron jobs).

Example of a useable Slackware URL:
  http://slackware.mirrors.tds.net/pub/slackware/slackware-14.0/slackware

EOF
}

# Parse the commandline parameters:
while [ ! -z "$1" ]; do
  case $1 in
    -d|--destdir)
      TARGET64ROOT="$(cd $(dirname "${2}"); pwd)/$(basename "${2}")"
      shift 2
      ;;
    -h|--help)
      show_help
      exit 0
      ;;
    -i|--inputdir)
      SLACK32ROOT="$(cd $(dirname "${2}"); pwd)/$(basename "${2}")"
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
      SLACK32URL="${2}"
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

# A function to retrieve the fullname of a package:
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

# A function to convert a package,
# downloading it first if needed, and taking patches into account:
function conv_pkg () {
  local BP="$1"
  local SERIES="$2"
  local PATCHLIST="$3"
 
  PKGPATH="$SERIES/$BP"
  REPOFOUND=""

  # First find out if the requested package exists in the repository:
  # Two repo location options: URL or local directory.
  if [ -n "$SLACK32URL" ]; then
    FULLURL=$(get_url_pkg $PKGPATH $SLACK32URL)
    if [ -n "$FULLURL" ]; then
      FULLPKG=$SLACK32ROOT/$SERIES/$(basename $FULLURL)
      REPOVERSION=$(basename $FULLURL |rev |cut -d- -f3 |rev)
      REPOBLD="$(basename $FULLURL |rev |cut -d- -f1 |cut -d. -f2- |rev)"
    else
      # Package could not be found on the remote server:
      FULLPKG=""
      REPOVERSION=""
      REPOBLD=""
    fi
  else
    FULLPKG=$(get_pkgfullpath $SLACK32ROOT/$PKGPATH)
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
      if [ -n "$SLACK32URL" ]; then
        FULLURL=$(get_url_pkg $PKGPATH "$(dirname $SLACK32URL)/patches")
        if [ -n "$FULLURL" ]; then
          FULLPKG=$SLACK32ROOT/$SERIES/$(basename $FULLURL)
          REPOVERSION=$(basename $FULLURL |rev |cut -d- -f3 |rev)
          REPOBLD="$(basename $FULLURL |rev |cut -d- -f1 |cut -d. -f2- |rev)"
        else
          FULLPKG=""
          REPOVERSION=""
          REPOBLD=""
        fi
      else
        FULLPKG=$(get_pkgfullpath $SLACK32ROOT/$PKGPATH)
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
  HAVE_COMPAT32="$(get_pkgfullpath $TARGET64ROOT/${SERIES}-compat32/$BP-compat32)"
  if [ -n "$HAVE_COMPAT32" ]; then
    COMPAT32VERSION="$(echo "$HAVE_COMPAT32" |rev|cut -d- -f3|rev)"
    COMPAT32BLD="$(echo "$HAVE_COMPAT32" |rev|cut -d- -f1|cut -d. -f2-|rev)"
    if [ "$COMPAT32VERSION" = "$REPOVERSION" -a "${COMPAT32BLD%compat32}" = "$REPOBLD" ]
    then
      [ $VERBOSE -eq 1 ] && echo "--- ${BP}-compat32 version '$COMPAT32VERSION' already available"
    else
      if [ $DRYRUN -eq 0 ]; then
        echo ">>> Deleting old version '$COMPAT32VERSION' of '${BP}-compat32'"
      else
        echo "${BP}: existing package needs update"
      fi
      FILE_TO_REMOVE=$HAVE_COMPAT32
      HAVE_COMPAT32=""
    fi
  else
    if [ $DRYRUN -eq 1 ]; then
      echo "${BP}: new package will be converted"
    fi
  fi

  # If we do not have the latest -compat32 package, then run the conversion:
  if [ ! -n "$HAVE_COMPAT32" -a $DRYRUN -eq 0 ]; then

    if [ -n "$SLACK32URL" ]; then
      # Download the Slackware package before converting it:
      ( mkdir -p $SLACK32ROOT/$SERIES
        cd $SLACK32ROOT/$SERIES
        lftp -c "open $(dirname $FULLURL) ; get $(basename $FULLURL)" 2>/dev/null
      )
    fi

    [ $VERBOSE -eq 1 ] && echo "--- $BP"
    # Convert the Slackware package into a -compat32 version:
    sh $CONV32 -i $FULLPKG -d $TARGET64ROOT/${SERIES}-compat32

    if [ -n "$FILE_TO_REMOVE" ]; then
      # This is where we delete an older version of the -compat32 package:
      rm $(echo $FILE_TO_REMOVE | rev | cut -d. -f2- | rev).*
      FILE_TO_REMOVE=""
    fi
  fi
}

# Safety checks in case a URL was provided: 
if [ -n "$SLACK32URL" ]; then
  if [ -n "$SLACK32ROOT" ]; then
    echo "*** Options '-i' and '-u' can not be used together!"
    exit 1
  else
    # Define a 'temporary' root directory where we will download packages:
    SLACK32ROOT="${TMP}/alienBOB/slackware"
    if ! which lftp 1>/dev/null 2>&1 ; then
      echo  "No lftp binary detected! Need lftp for package downloading!"
      exit 1
    fi
  fi
fi

# The root directory of 32bit Slackware packages
# (should have the a,ap,d,..,y directories immediately below):
# Let's use a fallback directory in case none was specified:
SLACK32ROOT="${SLACK32ROOT:-"/home/ftp/pub/Linux/Slackware/slackware-current/slackware"}"

# The output directory for our converted packages; defaults to the current dir.
# Note that {a,ap,d,l,n,x}-compat32 directories will be created below this
# directory if they do not yet exist:
TARGET64ROOT="${TARGET64ROOT:-"$(pwd)"}"

# Abort if we got directories with spaces in them:
if contains_spaces "$SLACK32ROOT" ; then
  echo "Directories with spaces are unsupported: '$SLACK32ROOT'!"
  exit 1
fi
if contains_spaces "$TARGET64ROOT" ; then
  echo "Directories with spaces are unsupported: '$TARGET64ROOT'!"
  exit 1
fi

# Where the scripts are:
SRCDIR=$(cd $(dirname $(which $0)); pwd)

# The script that does the package conversion:
CONV32=$SRCDIR/convertpkg-compat32

# Bail out if the conversion script is not available/working:
if [ ! -f $CONV32 ]; then
  echo "Required script '$CONV32' is not present or not executable! Aborting..."
  exit 1
fi

# We can not proceed if there are no packages and we did not get an URL:
if [ -z "$SLACK32URL" ]; then
  if [ ! -d $SLACK32ROOT/a -o ! -d $SLACK32ROOT/ap -o ! -d $SLACK32ROOT/d -o ! -d $SLACK32ROOT/l -o ! -d $SLACK32ROOT/n -o ! -d $SLACK32ROOT/x -o ! -d $SLACK32ROOT/xap ]; then
    echo "Required package directories a,ap,d,l,n,x,xap below '$SLACK32ROOT' are not found! Aborting..."
    exit 1
  fi
fi

# If a destination_directory was specified, abort now if we can not create it:
if [ -n "$TARGET64ROOT" -a ! -d "$TARGET64ROOT" ]; then
  echo "Creating output directory '$TARGET64ROOT'..."
  mkdir -p $TARGET64ROOT
  if [ ! -w "$TARGET64ROOT" ]; then
    echo "Creation of output directory '$TARGET64ROOT' failed!"
    exit 3
  fi
fi

# Get a list of available patches
if [ -n "$SLACK32URL" ]; then
  PATCH_LIST=$(echo $(lftp -c "open $(dirname $SLACK32URL)/patches/packages/ ; cls *.t?z" 2>/dev/null | rev | cut -f4- -d- |rev))
else
  PATCH_LIST=$(echo $(cd $(dirname $SLACK32ROOT)/patches/packages/ 2>/dev/null ; ls -1 *.t?z 2>/dev/null | rev | cut -f4- -d- |rev))
fi

# This is the script's internal list of what I consider as the essential
# 32bit multilib package set for your Slackware64:

# The A/ series:
A_COMPAT32="
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
AP_COMPAT32="
cups
cups-filters
flac
mariadb
mpg123
mysql
sqlite
"

# The D/ series:
D_COMPAT32="
libtool
llvm
opencl-headers
"

# The L/ series:
L_COMPAT32="
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
N_COMPAT32="
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
X_COMPAT32="
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
XAP_COMPAT32="
sane
"

# Create target directories if they do not exist:
for TDIR in a-compat32 ap-compat32 d-compat32 l-compat32 n-compat32 x-compat32 xap-compat32 ; do
  mkdir -p $TARGET64ROOT/$TDIR
  if [ ! -w $TARGET64ROOT/$TDIR ]; then
    echo "Directory '$TARGET64ROOT/$TDIR' is not writable! Aborting..."
    exit 1
  fi
done

# Convert the 32bit packages from A AP D L N and X series, checking for patches:
[ $VERBOSE -eq 1 ] && echo "*** Starting the conversion process:"

[ $VERBOSE -eq 1 ] && echo "*** 'A' series:"
for INPKG in $A_COMPAT32 ; do
  conv_pkg $INPKG a "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'AP' series:"
for INPKG in $AP_COMPAT32 ; do
  conv_pkg $INPKG ap "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'D' series:"
for INPKG in $D_COMPAT32 ; do
  conv_pkg $INPKG d "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'L' series:"
for INPKG in $L_COMPAT32 ; do
  conv_pkg $INPKG l "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'N' series:"
for INPKG in $N_COMPAT32 ; do
  conv_pkg $INPKG n "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'X' series:"
for INPKG in $X_COMPAT32 ; do
  conv_pkg $INPKG x "$PATCH_LIST"
done

[ $VERBOSE -eq 1 ] && echo "*** 'XAP' series:"
for INPKG in $XAP_COMPAT32 ; do
  conv_pkg $INPKG xap "$PATCH_LIST"
done

# Mention downloaded packages if we used a URL as source:
if [ $VERBOSE -eq 1 -a $DRYRUN -eq 0 -a  -n "$SLACK32URL" ]; then
  echo "WARNING: packages which were downloaded from '$SLACK32URL'"
  echo "have been left in directory '$SLACK32ROOT'."
  echo "It is safe to remove these now."
  echo ""
fi

[ $VERBOSE -eq 1 ] && echo "*** Conversion done!"

