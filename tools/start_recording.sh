# Sourced by .github/workflows/flutter-menu.yml; defines start_recording.
#
# start_recording FILE LOG starts `xcrun simctl io $UDID recordVideo` in the
# background, sets RECORDER to its pid and returns once the recorder says
# "Recording started" (or after 15 s while it still runs). A device with more
# than one display refuses to record without --display; then it is started
# again on the display the error message calls "(primary)". Stop it with
# `kill -INT "$RECORDER"; wait "$RECORDER"`. Returns 1 when no recorder runs.
start_recording() {
  local file=$1 log=$2 attempt number
  local display=()
  : > "$log"
  for attempt in 1 2; do
    xcrun simctl io "$UDID" recordVideo --codec=h264 "${display[@]}" --force "$file" >> "$log" 2>&1 &
    RECORDER=$!
    for _ in $(seq 1 30); do
      if grep -q 'Recording started' "$log"; then
        return 0
      fi
      kill -0 "$RECORDER" 2>/dev/null || break
      sleep 0.5
    done
    if kill -0 "$RECORDER" 2>/dev/null; then
      return 0
    fi
    # "--display=1  LCD (primary) 1398x2034"; "(primary-1)" is another display.
    number=$(sed -n 's/^ *--display=\([0-9][0-9]*\) .*(primary).*/\1/p' "$log" | head -1)
    if [ "$attempt" = 2 ] || [ -z "$number" ]; then
      return 1
    fi
    echo "start_recording: more than one display; recording --display=$number" >> "$log"
    display=(--display="$number")
  done
  return 1
}
