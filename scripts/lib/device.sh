# Shared helpers for running the app on a real Apple TV (sourced by
# scripts/device-*.sh). Clips stream from this Mac's mock-media-server over
# the LAN; the app runs its mock Jellyfin on the TV (`-mock` profile — the
# real sign-in is never touched); results come back via devicectl.

BUNDLE=com.kristianfreeman.bumper
DEVICE="${DEVICE:-$(xcrun devicectl list devices 2>/dev/null | awk '/physical/ && (/connected/ || /available/) { for (i = 1; i <= NF; i++) if ($i ~ /^[0-9a-f]{40}$/) print $i }' | head -1)}"
MODEL="$(xcrun devicectl list devices 2>/dev/null | grep "$DEVICE" | grep -oE 'AppleTV[0-9]+,[0-9]+' | head -1)"

dc() { scripts/with-timeout.sh "${DC_TIMEOUT:-120}" xcrun devicectl "$@"; }

require_device() { [[ -n "$DEVICE" ]] || { echo "no Apple TV found (devicectl list devices)"; exit 1; }; }

# Release build → install. A sleeping TV refuses the first connection
# (CoreDevice error 4016) and wakes, so installs retry.
build_and_install() {
  echo "Building Release for ${MODEL:-$DEVICE}…"
  scripts/with-timeout.sh 900 xcodebuild -project Bumper.xcodeproj -scheme Bumper -configuration Release \
    -destination "id=$DEVICE" -derivedDataPath build/device -allowProvisioningUpdates build -quiet >"$OUT/build.log" 2>&1 \
    || { echo "BUILD FAILED (see $OUT/build.log)"; grep -m5 "error:" "$OUT/build.log"; exit 1; }
  for attempt in 1 2 3; do
    dc device install app --device "$DEVICE" build/device/Build/Products/Release-appletvos/Bumper.app >/dev/null 2>&1 && return 0
    echo "install attempt $attempt failed (TV asleep?); retrying…"; sleep 8
  done
  echo "INSTALL FAILED — is the Apple TV awake?"; exit 1
}

# Serves $1 (a folder with manifest.json) on port $2; sets MEDIA_URL.
start_media_server() {
  local dir="$1" port="${2:-8098}"
  (cd Packages/JellyfinAppKit && ../../scripts/with-timeout.sh 600 swift build -c release --product mock-media-server -q) >"$OUT/media-server-build.log" 2>&1 \
    || { echo "mock-media-server build failed (see $OUT/media-server-build.log)"; exit 1; }
  local bin; bin="$(cd Packages/JellyfinAppKit && swift build -c release --show-bin-path)/mock-media-server"
  "$bin" "$PWD/$dir" "$port" >"$OUT/media-server-$port.log" 2>&1 &
  MEDIA_SERVER=$!
  trap 'kill $MEDIA_SERVER 2>/dev/null' EXIT
  sleep 1
  kill -0 "$MEDIA_SERVER" 2>/dev/null || { echo "mock-media-server failed: $(cat "$OUT/media-server-$port.log")"; exit 1; }
  local ip; ip="$(ipconfig getifaddr "$(route -n get default 2>/dev/null | awk '/interface:/ {print $2}')")"
  MEDIA_URL="http://$ip:$port/"
}

# launch_app <timeout-seconds> <app args…> — runs in the background; sets LAUNCHER.
launch_app() {
  local t="$1"; shift
  DC_TIMEOUT="$t" dc device process launch --device "$DEVICE" --terminate-existing --console "$BUNDLE" -- "$@" >"$OUT/console.log" 2>&1 &
  LAUNCHER=$!
}

# pull <container path> <local path> — true if it came back non-empty.
pull() {
  DC_TIMEOUT=20 dc device copy from --device "$DEVICE" --domain-type appDataContainer --domain-identifier "$BUNDLE" \
    --source "$1" --destination "$2" >/dev/null 2>&1 && [[ -s "$2" ]]
}
