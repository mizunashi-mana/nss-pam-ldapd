#!/bin/sh

# testenv.sh - script to check test environment
#
# Copyright (C) 2011, 2013 Arthur de Jong
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 USA

set -e

# get the script name
script="`basename "$0"`"

# find source directory (used for finding auxiliary files)
srcdir="${srcdir-`dirname "$0"`}"

# location of nslcd configuration file
nslcd_cfg="${nslcd_cfg-/etc/nslcd.conf}"

# find the names of services that are configured to use LDAP
nss_list_configured()
{
  sed -n 's/^[ \t]*\([a-z]*\)[ \t]*:.*[ \t]ldap.*$/\1/p' /etc/nsswitch.conf \
    | xargs
}

# check whether the name is configure to do lookups through LDAP
nss_is_enabled()
{
  name="$1"
  grep '^[ \t]*'$name'[ \t]*:.*ldap.*' /etc/nsswitch.conf > /dev/null
}

# check to see if name is configured to do lookups through
# LDAP and enable if not
nss_enable()
{
  name="$1"
  if nss_is_enabled "$name"
  then
   :
  else
    echo "$script: /etc/nsswitch.conf: enable LDAP lookups for $name" >&2
    if grep -q '^[ \t]*'$name'[ \t]*:' /etc/nsswitch.conf
    then
      # modify an existing entry by just adding ldap to the end
      sed -i 's/^\([ \t]*'$name'[ \t]*:.*[^ \t]\)[ \t]*$/\1 ldap/' /etc/nsswitch.conf
    else
      # append a new line
      printf '%-15s ldap\n' $name':' >> /etc/nsswitch.conf
    fi
    # invalidate nscd cache
    nscd -i "$name" > /dev/null 2>&1 || true
  fi
  # we're done
  return 0
}

# check nsswitch.conf
check_nsswitch() {
  required="${1:-passwd group}"
  if [ -r /etc/nsswitch.conf ]
  then
    :
  else
    echo "$script: ERROR: /etc/nsswitch.conf: not found" >&2
    return 1
  fi
  enabled=`nss_list_configured`
  if [ -z "$enabled" ]
  then
    echo "$script: ERROR: /etc/nsswitch.conf: no LDAP maps configured" >&2
    return 1
  fi
  for x in $required
  do
    if nss_is_enabled "$x"
    then
      :
    else
      echo "$script: ERROR: /etc/nsswitch.conf: $x not using ldap" >&2
      return 1
    fi
  done
  echo "$script: nsswitch.conf configured for $enabled"
  return 0
}

# check PAM stack
check_pam() {
  # TODO: implement some tests
  return 0
}

# check whether the LDAP server is available
check_ldap_server() {
  if [ -r "$nslcd_cfg" ]
  then
    :
  else
    echo "$script: ERROR: $nslcd_cfg: not found"
    return 1
  fi
  uri=`sed -n 's/^uri *//p' "$nslcd_cfg" | head -n 1`
  base="dc=test,dc=tld"
  # try to fetch the base DN
  ldapsearch -b "$base" -s base -x -H "$uri" > /dev/null 2>&1 || {
    echo "$script: ERROR: LDAP server $uri not available for $base"
    return 1
  }
  echo "$script: using LDAP server $uri"
  return 0
}

# check nslcd.conf file for presence and correct configuration
check_nslcd_conf() {
  # check if file is present
  [ -r "$nslcd_cfg" ] || {
    echo "$script: ERROR: $nslcd_cfg: not found" >&2
    return 1
  }
  # TODO: more tests...
  return 0
}

# basic check to see if nslcd is running
check_nslcd_running() {
  if [ -r /var/run/nslcd/socket ] && \
     [ -f /var/run/nslcd/nslcd.pid ] && \
     kill -0 `cat /var/run/nslcd/nslcd.pid` > /dev/null 2>&1
  then
    echo "$script: nslcd running (pid `cat /var/run/nslcd/nslcd.pid`)" >&2
    return 0
  fi
  echo "$script: ERROR: nslcd not running" >&2
  return 1
}

case "$1" in
  nss_enable)
    shift
    while [ $# -gt 0 ]
    do
      nss_enable "$1"
      shift
    done
    exit 0
    ;;
  check)
    res=0
    check_nsswitch || res=1
    check_pam || res=1
    check_ldap_server || res=1
    check_nslcd_conf || res=1
    check_nslcd_running || res=1
    [ $res -eq 0 ] && echo "$script: test environment OK"  || true
    exit $res
    ;;
  check_nss)
    shift
    check_nsswitch "$*" || exit 1
    exit 0
    ;;
  *)
    echo "Usage: $0 {nss_enable|check|check_nss}" >&2
    exit 1
    ;;
esac