#!/bin/csh

# $Id: 64dev.csh,v 1.2 2014/01/16 09:32:06 eha Exp eha $
# Created by Jim Diamond (Jim.Diamond@acadiau.ca),
# Based on 32dev.sh, part of the Slamd64 Linux project (www.slamd64.com),
# Copyright (C) 2007  Frederick Emmott <mail@fredemmott.co.uk>
# Copyright (C) 2018  Ben Stern <bas-github@fortian.com>

# Distributed under the GNU General Public License, version 2, as published
# by the Free Software Foundation.

setenv PATH "/usr/bin/64:/usr/lib/qt/bin:$PATH"
setenv CC "gcc" # This is actually the /usr/bin/64/gcc wrapper
setenv CXX "g++"
setenv FC "gfortran" # This is actually the /usr/bin/64/gfortran wrapper
setenv F77 "gfortran"

if ($?LD_LIBRARY_PATH == 1) then
    setenv LD_LIBRARY_PATH "/lib:/usr/lib:$LD_LIBRARY_PATH"
else
    setenv LD_LIBRARY_PATH "/lib:/usr/lib"
endif
if ($?PKG_CONFIG_PATH == 1) then
    setenv PKG_CONFIG_PATH "/usr/lib/pkgconfig:$PKG_CONFIG_PATH"
else
    setenv PKG_CONFIG_PATH "/usr/lib/pkgconfig"
endif

if (-d /opt/kde3/lib/qt3) setenv QTDIR /opt/kde3/lib/qt3
if (-d /usr/lib/qt) setenv QT4DIR /usr/lib/qt
