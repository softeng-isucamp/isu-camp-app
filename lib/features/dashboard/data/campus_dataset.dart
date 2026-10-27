import 'package:latlong2/latlong.dart';
import '../models/campus_models.dart';

// ISU Echague campus focal point used by the frontend map.
const LatLng isuCampusCenter = LatLng(16.721646458577446, 121.69173144090183);

// Mock navigation entrance until the admin-provided gate is available.
const LatLng isuMainGateNode = LatLng(16.7187243115489, 121.68845169376614);

// Loaded from the backend; no sample buildings are used as a fallback.
final List<CampusBuilding> isuCampusBuildings = [];

// Map tile source, shared by the live map and the offline tile download so
// both read from exactly the same cache keys.
const String campusTileUrlTemplate =
    'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const String campusTileUserAgent = 'com.isucamp.app';

// OpenStreetMap asks bulk clients to identify themselves, so the offline
// download sends this rather than a bare package name.
const String campusDownloadUserAgent =
    'KUMPAS/1.0 (com.isucamp.app; ISU Echague campus map)';

// Campus camera bounds. The offline pack downloads the tiles inside this box
// for every zoom the map allows, so panning offline never hits a blank tile.
const double isuCampusSouth = 16.7120;
const double isuCampusWest = 121.6830;
const double isuCampusNorth = 16.7310;
const double isuCampusEast = 121.7010;
const int offlineTileMinZoom = 15;
const int offlineTileMaxZoom = 19;
