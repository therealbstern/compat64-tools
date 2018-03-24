__WARNING * WARNING * WARNING * WARNING * WARNING * WARNING * WARNING * WARNING__

This has not been tested at all and is currently a naive transposition of "32"
and "64" throughout the scripts.

Use at your own risk.

__WARNING * WARNING * WARNING * WARNING * WARNING * WARNING * WARNING * WARNING__


# Using 64-bit Binaries on 32-bit Slackware

In order to use and compile 64-bit software on 32-bit Slackware, you will have
to replace your gcc and glibc packages with multilib versions, or else install
'compat64' packages for gcc and glibc that add the 64-bit binaries for these
packages. You can not just take the binaries from a 64bit Slackware.  Instead,
the 'compat64' versions of the gcc and glibc packages will have to be compiled
on the 32bit system.

You will also need to install several supporting 64-bit libraries.  These
libraries can be taken from the 64-bit Slackware of the same version as your
32-bit Slackware.  To make things easier for you, this package contains two
scripts:

    convertpkg-compat64
    massconvert64.sh

The first script converts a single 64-bit Slackware package into a 'compat64'
package that can be installed on 32-bit Slackware.  The second script will do
the hard work for you: it contains an internal list of Slackware packages that
you will need for a functional multilib 32-bit Slackware.  The script will
convert these packages to 'compat64' packages.  All that the script needs is a
single command-line argument: the path to a local 64-bit Slackware package
tree (this is the directory below which you find 'a', 'ap', ... 'y'
subdirectories).

You will also need qemu-x64 installed, so that you can run 64-bit binaries on
a 32-bit kernel.  (This does work, despite allegations to the contrary, though
it is certainly not as fast as running 32 binaries on a 64 bit kernel
natively.)


# Building 64-bit binaries on 32-bit Slackware

In order to compile 64-bit software when the full set of multilib binaries is
installed, all that you need is adding "-m64" to the compiler flags.  Quite a
few build systems however insist on adding -m32, regardless of what you tell
it.  For this reason, the package installs a few scripts to enforce 64-bit
builds. To load them into your path (including wrappers around gcc) you only
need to run the following command in your bash shell:

    . /etc/profile.d/64dev.sh

Note the single dot followed by a space: this is the 'source' command which
will set the various variables in your current shell environment.  Do not
forget to exit from your shell (and login again) after you have finished
compiling your 64-bit software, to get rid of the 64-bit-enforcing
environmental variables!

Additionally, if you compile any 64-bit binaries that conflict with 32-bit
versions, they should be installed into bin/64/, not bin/.

A typical invocation of the 'configure' command as an example:

    . /etc/profile.d/64dev.sh
    ./configure \
      --prefix=/usr \
      --bindir=/usr/bin/64


# Keeping your multilib environment up to date

The third-party program 'compat32pkg' is able to keep 32-bit on 64-bit
multilib packages up to date for Slackware64.  It works similarly to
slackpkg for regular Slackware.  See
(compat32pkg.sourceforge.net)[http://compat32pkg.sourceforge.net].
[However, no such program yet exists for 32-bit Slackware, to the best of my
knowledge.  -BAS]

---

Originally by Eric Hameleers <alien@slackware.com> 15-Nov-2010

Minor modifications by Ben Stern <bas-github@fortian.com> 23-Mar-2018

Licensed under CC Attribution-Share Alike 4.0 International
