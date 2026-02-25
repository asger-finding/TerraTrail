#!/usr/bin/env bash

# Generer MBTiles for Sjælland med Planetiler
# https://github.com/onthegomap/planetiler/releases
# Kræver Java

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCES_DIR="$PROJECT_ROOT/data/sources"
OUTPUT_DIR="$PROJECT_ROOT/lfs"
PLANETILER_JAR="$SCRIPT_DIR/planetiler.jar"

OSM_FILE="$SOURCES_DIR/denmark-latest.osm.pbf"
OUTPUT_FILE="$OUTPUT_DIR/map.mbtiles"

# Sjællands bounding box (koordinater)
BOUNDS="10.8,55.1,12.75,56.15"

mkdir -p "$SOURCES_DIR"

if [ ! -f "$OSM_FILE" ]; then
  echo "Henter Denmark OSM fra Geofabrik ..."
  curl -L -o "$OSM_FILE" "https://download.geofabrik.de/europe/denmark-latest.osm.pbf"
  echo "Downloadd"
else
  echo "Danmark OSM file fines allerede: $OSM_FILE"
fi

# Check Planetiler jar exists
if [ ! -f "$PLANETILER_JAR" ]; then
  echo "ERROR: planetiler.jar ikke fundet ved $PLANETILER_JAR"
  echo "Hent fra https://github.com/onthegomap/planetiler/releases og placer planetiler.jar i denne mappe"
  exit 1
fi

echo "Kører Planetiler for Sjælland (bounding box: $BOUNDS)..."
java -Xmx2g -jar "$PLANETILER_JAR" \
  --osm-path="$OSM_FILE" \
  --output="$OUTPUT_FILE" \
  --bounds="$BOUNDS" \
  --download \
  --force

echo "Output: $OUTPUT_FILE"
