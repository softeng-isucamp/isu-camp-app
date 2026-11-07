import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:isu_camp_app/features/dashboard/models/campus_models.dart';
import 'package:isu_camp_app/features/dashboard/services/campus_search.dart';

CampusBuilding building(
        String id, String name, List<Map<String, dynamic>> rooms,
        {String keywords = '', double latitude = 16.72}) =>
    CampusBuilding.fromJson({
      'id': id,
      'name': name,
      'keywords': keywords,
      'latitude': latitude,
      'longitude': 121.69,
      'rooms': rooms.map((r) => {'floor': '2nd Floor', ...r}).toList(),
    });

void main() {
  final campus = [
    building('1', 'CCSICT', [
      {
        'id': '1',
        'title': 'Male Restroom',
        'category': 'room',
        'keywords': 'pee, toilet'
      },
      {'id': '2', 'title': 'Room 1', 'category': 'room'},
      {'id': '3', 'title': 'Room 11', 'category': 'room'},
    ]),
    building('64', 'College of Engineering', [
      {'id': '148', 'title': 'New Drawing Room', 'category': 'room'},
      {'id': '142', 'title': 'Multi-Purpose Hall', 'category': 'room'},
      {'id': '33', 'title': 'Deans Office', 'category': 'office'},
    ]),
    building('9', 'College of Agriculture', [
      {'id': '34', 'title': "Dean's Office", 'category': 'office'},
    ]),
    building(
        '2',
        'Administration Building',
        [
          {'id': '41', 'title': 'Cashiering Office', 'category': 'office'},
        ],
        keywords: 'cashier, tuition'),
    building('60', 'New Admin Building', [
      {
        'id': '61',
        'title': 'Restroom',
        'category': 'restroom',
        'keywords': 'pee'
      },
    ]),
  ];
  test('purpose phrase finds cashier and excludes parent keyword result', () {
    final r = CampusSearch.search(campus, 'Where can I pay for tuition?');
    expect(r.map((r) => r.room?.id), ['41']);
  });
  test('pee keyword scoped to CCSICT', () {
    expect(
        CampusSearch.search(campus, 'Where can I pee in CCSICT?')
            .map((r) => r.room?.id),
        ['1']);
  });
  test('named room excludes unrelated rooms', () {
    for (final scope in ['COE', 'College of Engineering']) {
      expect(
          CampusSearch.search(campus, 'Where is the drawing room of $scope?')
              .map((r) => r.room?.id),
          ['148']);
    }
  });
  test('CA limits Dean office to Agriculture', () {
    expect(
        CampusSearch.search(campus, 'Where is the deans office of CA?')
            .map((r) => r.room?.id),
        ['34']);
  });
  test('room number uses whole tokens', () {
    expect(
        CampusSearch.search(campus, 'Where is room 1 in CCSICT?')
            .map((r) => r.room?.id),
        ['2']);
  });
  test('New Admin is distinct from Admin', () {
    expect(
        CampusSearch.search(campus, 'Where can I pee in New Admin?')
            .map((r) => r.room?.id),
        ['61']);
    expect(CampusSearch.search(campus, 'New Admin').single.building.id, '60');
  });
  test('unknown constraint does not search globally', () {
    expect(CampusSearch.search(campus, 'Where is the dean office in Unknown?'),
        isEmpty);
  });
  test('nearest sorts and limits to five with real origin', () {
    final lots = List.generate(7,
        (i) => building('p$i', 'Parking $i', [], latitude: 16.72 + i * .001));
    final matches = CampusSearch.search(lots, 'parking',
        origin: const LatLng(16.72, 121.69));
    expect(matches.length, 5);
    expect(matches.first.building.id, 'p0');
  });
  test('keywords and location coordinates survive offline round trip', () {
    final b = building(
        'b',
        'Building',
        [
          {
            'id': 'r',
            'title': 'Office',
            'category': 'office',
            'keywords': 'special service',
            'latitude': 16.72,
            'longitude': 121.69
          }
        ],
        keywords: 'building keyword');
    final copy = CampusBuilding.fromJson(b.toJson());
    expect(copy.keywords, 'building keyword');
    expect(copy.rooms.single.keywords, 'special service');
    expect(copy.rooms.single.coordinate, const LatLng(16.72, 121.69));
  });
}
