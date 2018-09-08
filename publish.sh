#!/bin/sh

if [ "${build}" = "" ]; then
  build=0
fi

rev=`git log --oneline | wc -l | awk '{print $1}'`
commit=`git log --oneline -1 | awk '{print $1}'`
ver=0.${rev}.${build}
echo "Version: ${ver} (Rev=${rev}, Build=${build}, Commit=${commit})"

### Update version descriptions on files
sed -i.bak \
	-E "s/version: [0-9]+\.[0-9]+\.[0-9]+/version: ${ver}/" \
	pubspec.yaml

if [ "$1" = "" ]; then
  echo "To publish, set --force option."
  pubopts=--dry-run
else
  pubopts=
fi

flutter packages pub publish $pubopts


