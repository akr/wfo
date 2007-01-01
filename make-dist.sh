#!/bin/sh

version="`cat VERSION`" &&
tmpdir="/tmp/wfo-dist-$$" &&
mkdir $tmpdir &&
(
  cd $tmpdir &&
  svn export svn://svn@rx1620.fsij.org/akr/wfo/tags/"wfo-$version" &&
  cd "wfo-$version" &&
  autoconf
) &&
(
  cd $tmpdir &&
  tar cvf - "wfo-$version"
) > "wfo-$version".tar &&
gzip -9 "wfo-$version".tar &&
rm -rf $tmpdir
