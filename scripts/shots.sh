#!/bin/bash
# Takes simulator screenshots from outside the test process while the UI test
# keeps `$OUT/shoot-now` in place (it holds the case name). Stops when
# `$OUT/.stop-shots` appears. Usage: shots.sh <udid> <out dir>
udid="$1"
out="$2"
mkdir -p "$out/shots"
while [ ! -f "$out/.stop-shots" ]; do
  if [ -f "$out/shoot-now" ]; then
    name=$(cat "$out/shoot-now" 2>/dev/null)
    ts=$(perl -MTime::HiRes=time -e 'printf "%d", time() * 1000')
    xcrun simctl io "$udid" screenshot --type=jpeg "$out/shots/${name:-case}-$ts.jpg" > /dev/null 2>&1
  else
    sleep 0.1
  fi
done
