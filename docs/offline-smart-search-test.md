# Offline smart search and map test build

This is an Android test build. It does not change the live API deployment.

## Test on the device

1. Open **Profile → Offline Campus Map** while online.
2. Download the pinned **Experimental Smart Search model** (about 252 MB). The app verifies the model and tokenizer SHA-256 values before enabling them.
3. Keep the campus catalog installed. The OSM-derived and satellite tile archive is included in this test APK and extracts to app storage on first map open.
4. Return to **Map**, tap the sparkle icon in the search bar, and enter queries. The result subtitle identifies model suggestions. The model only ranks known campus building records; relevance and no-match quality have not been evaluated by the required human-authored ranking set.
5. Turn on Airplane mode, restart the app, and repeat searches. Switch between map styles to test the offline OSM-derived layer and offline Sentinel-2 image layer. Offline imagery covers only the ISU Echague campus bounds. Satellite data is 10 m source imagery from 2025-11-12, so details are coarser than online Esri imagery.

## Tile sources and attribution

- OSM tiles in the test bundle were rendered locally from one campus-bounds OpenStreetMap data extract. The public OSM raster tile server was not bulk-downloaded. The app displays **© OpenStreetMap contributors (ODbL)** and links to the OSM copyright page through the layer manifest.
- The satellite layer was rendered locally from the Sentinel-2 L2A scene `S2B_51QUU_20251112_0_L2A`. The app displays **Contains modified Copernicus Sentinel data 2025**, as required for adapted Sentinel data. Source and notice are recorded in the bundle manifest.
- `tools/generate_offline_test_tiles.py` recreates the bundle from those sources. Its small OSM XML input is cached at `/tmp/kumpas-campus-osm.xml` during generation.

## Restore the previous Android app build

The previous installed APK was saved before installing this test build. Run:

```bash
tools/restore_pre_smart_search_android.sh
```

This reinstalls the old APK with `adb install -r`, preserving app data. The backup SHA-256 is checked by the script. The API deployment is separate and was not changed for this test.
