#!/bin/sh
# Renders design/AppIcon.svg into the app's asset catalog. Needs rsvg-convert (brew install librsvg).
set -eu
cd "$(dirname "$0")/.."
out=App/Assets.xcassets/AppIcon.appiconset
mkdir -p "$out"
printf '{"info":{"author":"xcode","version":1}}\n' > App/Assets.xcassets/Contents.json
images=""
for size in 16 32 128 256 512; do
    for scale in 1 2; do
        px=$((size * scale))
        name="icon_${size}x${size}@${scale}x.png"
        rsvg-convert -w "$px" -h "$px" design/AppIcon.svg -o "$out/$name"
        images="$images{\"idiom\":\"mac\",\"size\":\"${size}x${size}\",\"scale\":\"${scale}x\",\"filename\":\"$name\"},"
    done
done
printf '{"images":[%s],"info":{"author":"xcode","version":1}}\n' "${images%,}" > "$out/Contents.json"
