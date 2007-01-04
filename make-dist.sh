#!/bin/sh

tar_opts="--owner 0 --group 0"

version="`cat VERSION`" &&
tmpdir="/tmp/wfo-dist-$$" &&
mkdir $tmpdir &&
(
  cd $tmpdir &&
  svn export svn://svn@svn.a-k-r.org/akr/wfo/tags/"wfo-$version" &&
  cd "wfo-$version" &&
  autoconf &&
  erb misc/README.erb > README
) &&
(
  cd $tmpdir &&
  tar cvf - $tar_opts "wfo-$version"
) > "wfo-$version".tar &&
gzip -9 "wfo-$version".tar &&
rm -rf $tmpdir
