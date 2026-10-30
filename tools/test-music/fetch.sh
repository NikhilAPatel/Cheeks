#!/bin/sh
# Downloads two Creative Commons tracks (Kevin MacLeod, incompetech.com, CC BY 4.0) to test with.
# They aren't kept in the repo. Usage: tools/test-music/fetch.sh [folder], default /tmp/cheeks-music.
set -e
DIR="${1:-/tmp/cheeks-music}"
mkdir -p "$DIR"
curl -sSL -o "$DIR/Exhilarate.mp3" "https://incompetech.com/music/royalty-free/mp3-royaltyfree/Exhilarate.mp3"
curl -sSL -o "$DIR/Severe Tire Damage.mp3" "https://incompetech.com/music/royalty-free/mp3-royaltyfree/Severe%20Tire%20Damage.mp3"
ls -la "$DIR"
