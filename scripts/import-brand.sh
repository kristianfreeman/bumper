#!/usr/bin/env bash
# Copies the generated Bumper brand (the brand kit's dist folder) into the app:
# tvOS layered icons and top shelf, the iPhone icon, the launch symbol, the
# boil frames, and the palette (BrandTheme.swift). Rerun after the kit
# rebuilds; never edit the copied files by hand.
#
#   scripts/import-brand.sh [path/to/brands/bumper/dist]
set -euo pipefail
cd "$(dirname "$0")/.."
DIST="${1:-$HOME/Developer/brand/brands/bumper/dist}"
[[ -f "$DIST/BrandTheme.swift" ]] || { echo "no brand dist at $DIST" >&2; exit 1; }

TV=App/Assets.xcassets
BA="$TV/App Icon & Top Shelf Image.brandassets"
INFO='"info" : { "author" : "xcode", "version" : 1 }'

imageset() {   # dir, idiom, then pairs of scale=file
  local dir="$1" idiom="$2"; shift 2
  rm -rf "$dir"; mkdir -p "$dir"
  local entries=()
  for pair in "$@"; do
    local scale="${pair%%=*}" src="${pair#*=}" name="image@${pair%%=*}.png"
    cp "$DIST/$src" "$dir/$name"
    entries+=("{ \"filename\" : \"$name\", \"idiom\" : \"$idiom\", \"scale\" : \"$scale\" }")
  done
  local IFS=,
  printf '{ "images" : [ %s ], %s }\n' "${entries[*]}" "$INFO" > "$dir/Contents.json"
}

stack() {      # stack dir, size suffix for 1x, optional size suffix for 2x
  local dir="$1" one="$2" two="${3:-}"
  rm -rf "$dir"; mkdir -p "$dir"
  for layer in Front:front Middle:plate Back:back; do
    local name="${layer%%:*}" file="${layer#*:}"
    mkdir -p "$dir/$name.imagestacklayer"
    printf '{ %s }\n' "$INFO" > "$dir/$name.imagestacklayer/Contents.json"
    if [[ -n "$two" ]]; then
      imageset "$dir/$name.imagestacklayer/Content.imageset" tv "1x=icon/$file-$one.png" "2x=icon/$file-$two.png"
    else
      imageset "$dir/$name.imagestacklayer/Content.imageset" tv "1x=icon/$file-$one.png"
    fi
  done
  printf '{ "layers" : [ { "filename" : "Front.imagestacklayer" }, { "filename" : "Middle.imagestacklayer" }, { "filename" : "Back.imagestacklayer" } ], %s }\n' "$INFO" > "$dir/Contents.json"
}

# tvOS icon (Front / Middle = the plate / Back) and top shelf.
stack "$BA/App Icon.imagestack" 400x240 800x480
stack "$BA/App Icon - App Store.imagestack" 1280x768
imageset "$BA/Top Shelf Image.imageset" tv "1x=topshelf/topshelf-1920x720.png" "2x=topshelf/topshelf-3840x1440.png"
imageset "$BA/Top Shelf Image Wide.imageset" tv "1x=topshelf/topshelf-wide-2320x720.png" "2x=topshelf/topshelf-wide-4640x1440.png"

# Launch screen: the still sticker on soot.
imageset "$TV/LaunchSymbol.imageset" tv "1x=frames/symbol-0@240.png" "2x=frames/symbol-0@480.png"
mkdir -p "$TV/LaunchBackground.colorset"
printf '{ "colors" : [ { "idiom" : "universal", "color" : { "color-space" : "srgb", "components" : { "red" : "0x17", "green" : "0x16", "blue" : "0x14", "alpha" : "1.000" } } } ], %s }\n' "$INFO" > "$TV/LaunchBackground.colorset/Contents.json"

# The boil: four frames each of the wordmark and the sticker.
for mark in wordmark symbol wordmark-light symbol-light; do
  for i in 0 1 2 3; do
    imageset "$TV/BumperBoil-$mark-$i.imageset" tv "1x=frames/$mark-$i@240.png" "2x=frames/$mark-$i@480.png"
  done
done

# The clean still marks (vectors) for places where the mark sits still at
# small sizes, like the sidebar header.
for mark in wordmark wordmark-light symbol symbol-light; do
  dir="$TV/BumperMark-$mark.imageset"
  rm -rf "$dir"; mkdir -p "$dir"
  cp "$DIST/$mark.svg" "$dir/$mark.svg"
  printf '{ "images" : [ { "filename" : "%s.svg", "idiom" : "universal" } ], "properties" : { "preserves-vector-representation" : true }, %s }\n' "$mark" "$INFO" > "$dir/Contents.json"
done

# iPhone: one 1024 icon.
PHONE=iPhone/Assets.xcassets
mkdir -p "$PHONE/AppIcon.appiconset"
printf '{ %s }\n' "$INFO" > "$PHONE/Contents.json"
cp "$DIST/icon/ios-1024x1024.png" "$PHONE/AppIcon.appiconset/icon-1024.png"
printf '{ "images" : [ { "filename" : "icon-1024.png", "idiom" : "universal", "platform" : "ios", "size" : "1024x1024" } ], %s }\n' "$INFO" > "$PHONE/AppIcon.appiconset/Contents.json"

# Mac: the same artwork at the Mac's icon sizes (macOS 26 rounds it).
MAC=Mac/Assets.xcassets
mkdir -p "$MAC/AppIcon.appiconset"
printf '{ %s }\n' "$INFO" > "$MAC/Contents.json"
entries=()
for spec in 16:1 16:2 32:1 32:2 128:1 128:2 256:1 256:2 512:1 512:2; do
  pt=${spec%%:*}; scale=${spec#*:}; px=$((pt * scale))
  name="icon-${pt}@${scale}x.png"
  sips -z $px $px "$DIST/icon/ios-1024x1024.png" --out "$MAC/AppIcon.appiconset/$name" >/dev/null
  entries+=("{ \"filename\" : \"$name\", \"idiom\" : \"mac\", \"scale\" : \"${scale}x\", \"size\" : \"${pt}x${pt}\" }")
done
( IFS=,; printf '{ "images" : [ %s ], %s }\n' "${entries[*]}" "$INFO" > "$MAC/AppIcon.appiconset/Contents.json" )

# The palette.
cp "$DIST/BrandTheme.swift" Packages/JellyfinAppKit/Sources/DesignSystem/BrandTheme.swift

echo "Imported the brand from $DIST"
