#!/bin/sh

set -xe

echo "Path Provided: $1"
if [ "$1" ] && [ -d "$1" ]; then
  thp_path="$1"
else
  echo "Returning without doing anything..."
  exit 0
fi

if [ `cat ${thp_path}/enabled | grep '\[never\]' | wc -l` -eq 0 ]; then
  echo "Changed ${thp_path}/enabled to "
  echo `cat ${thp_path}/enabled`
  echo 'never' > ${thp_path}/enabled
fi
if [ `cat ${thp_path}/defrag | grep '\[never\]' | wc -l` -eq 0 ]; then
  echo 'never' > ${thp_path}/defrag
  re='^[0-1]+$'
  if [[ $(cat ${thp_path}/khugepaged/defrag) =~ $re ]]; then
    # RHEL 7
    echo 0  > ${thp_path}/khugepaged/defrag
  else
    # RHEL 6
    echo 'no' > ${thp_path}/khugepaged/defrag
  fi
fi
