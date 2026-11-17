import 'package:latlong2/latlong.dart';
import '../models/campus_models.dart';

class CampusSearchResult {
  final CampusBuilding building;
  final CampusRoom? room;
  final double? meters;
  final int score;
  const CampusSearchResult(this.building, this.room, this.meters, this.score);
  String get title => room?.title ?? building.name;
  bool get estimatedDistance => room != null && room!.coordinate == null;
}

/// Local, deterministic search. No trained model or ML endpoint is used.
class CampusSearch {
  static bool matchesCategory(CampusBuilding b, String filter,
      {CampusRoom? room, bool includeContents = true}) {
    if (filter == 'All') return true;
    if (room != null) {
      final title = normalize(room.title);
      final category = room.category;
      return switch (filter) {
        'Room' => !title.contains('restroom') &&
            (category == RoomCategory.room ||
                category == RoomCategory.classroom),
        'Office' => category == RoomCategory.office ||
            category == RoomCategory.administrative ||
            category == RoomCategory.faculty,
        'Laboratory' =>
          category == RoomCategory.laboratory || title.contains('lab'),
        'Restroom' => category == RoomCategory.restroom ||
            title.contains('restroom') ||
            title.contains('toilet'),
        'Parking' =>
          category == RoomCategory.parking || title.contains('parking'),
        'Food' => RegExp(r'food|canteen|cafeteria|dining').hasMatch(title),
        'Facility' => category == RoomCategory.facility ||
            category == RoomCategory.studyArea,
        'Campus services' => category == RoomCategory.administrative ||
            category == RoomCategory.office ||
            RegExp(r'clinic|library|registrar|cashier|guidance')
                .hasMatch(title),
        _ => matchesCategory(b, filter),
      };
    }
    final rooms = includeContents ? b.rooms : const <CampusRoom>[];

    final name = b.name.toLowerCase();
    final acronym = b.acronym.toLowerCase();
    final category = b.category.toLowerCase();
    final description = b.description.toLowerCase();
    final combined = '$category $name $acronym $description';

    final isParkingLocation = b.isParking ||
        category.contains('parking') ||
        name.contains('parking') ||
        acronym.contains('parking');

    if (filter == 'Parking' || filter == 'Parkings') {
      return isParkingLocation ||
          rooms.any((r) =>
              r.category == RoomCategory.parking ||
              r.title.toLowerCase().contains('parking'));
    }

    // Never show parking lots under non-parking category filters
    if (isParkingLocation) return false;

    switch (filter) {
      case 'College':
      case 'Colleges':
        return category.contains('college') ||
            category.contains('academic') ||
            name.contains('college') ||
            name.contains('school') ||
            name.contains('institute') ||
            const {
              'ccsict',
              'coe',
              'cbapa',
              'ca',
              'ced',
              'cas',
              'ccje',
              'cf',
              'con',
              'svm',
            }.contains(acronym);

      case 'Campus services':
        return category.contains('service') ||
            category.contains('admin') ||
            combined.contains('campus service') ||
            combined.contains('administration') ||
            combined.contains('osas') ||
            combined.contains('student affairs') ||
            combined.contains('student service') ||
            combined.contains('infirmary') ||
            combined.contains('clinic') ||
            combined.contains('health') ||
            combined.contains('library') ||
            combined.contains('security') ||
            combined.contains('guard') ||
            combined.contains('registrar') ||
            combined.contains('cashier') ||
            combined.contains('guidance') ||
            rooms.any((r) {
              final rt = r.title.toLowerCase();
              return r.category == RoomCategory.administrative ||
                  rt.contains('service') ||
                  rt.contains('registrar') ||
                  rt.contains('cashier') ||
                  rt.contains('clinic') ||
                  rt.contains('osas') ||
                  rt.contains('guidance');
            });

      case 'Food':
        return category.contains('food') ||
            combined.contains('canteen') ||
            combined.contains('cafeteria') ||
            combined.contains('food') ||
            combined.contains('dining') ||
            combined.contains('eatery') ||
            rooms.any((r) {
              final rt = r.title.toLowerCase();
              return rt.contains('canteen') ||
                  rt.contains('cafeteria') ||
                  rt.contains('food');
            });

      case 'Facility':
        return category.contains('facility') ||
            category.contains('facilities') ||
            combined.contains('gym') ||
            combined.contains('grandstand') ||
            combined.contains('auditorium') ||
            combined.contains('oval') ||
            combined.contains('court') ||
            combined.contains('dorm') ||
            combined.contains('hostel') ||
            combined.contains('chapel') ||
            combined.contains('church') ||
            combined.contains('center') ||
            combined.contains('hall') ||
            rooms.any((r) =>
                r.category == RoomCategory.facility ||
                r.category == RoomCategory.studyArea ||
                r.title.toLowerCase().contains('facility'));

      case 'Room':
        return category == 'room' ||
            rooms.any((r) =>
                r.category == RoomCategory.room ||
                r.category == RoomCategory.classroom ||
                r.title.toLowerCase().contains('room'));

      case 'Office':
        return category.contains('office') ||
            category.contains('admin') ||
            name.contains('office') ||
            name.contains('administration') ||
            rooms.any((r) =>
                r.category == RoomCategory.office ||
                r.category == RoomCategory.administrative ||
                r.category == RoomCategory.faculty ||
                r.title.toLowerCase().contains('office'));

      case 'Laboratory':
        return category.contains('lab') ||
            name.contains('lab') ||
            rooms.any((r) =>
                r.category == RoomCategory.laboratory ||
                r.title.toLowerCase().contains('lab'));

      case 'Restroom':
        final hasCrWord = RegExp(r'cr').hasMatch(combined);
        return category.contains('restroom') ||
            combined.contains('restroom') ||
            combined.contains('comfort room') ||
            combined.contains('toilet') ||
            combined.contains('washroom') ||
            hasCrWord ||
            rooms.any((r) {
              final rt = r.title.toLowerCase();
              final rd = (r.description ?? '').toLowerCase();
              return r.category == RoomCategory.restroom ||
                  rt.contains('restroom') ||
                  rt.contains('comfort room') ||
                  rt.contains('toilet') ||
                  rt.contains('washroom') ||
                  RegExp(r'cr').hasMatch(rt) ||
                  RegExp(r'cr').hasMatch(rd);
            });

      case 'Shaded':
        return b.hasShadedPath;

      default:
        return true;
    }
  }

  static String normalize(String text) {
    var s = text.toLowerCase().replaceAll(RegExp(r"['’]"), '');
    s = s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
    s = s
        .replaceAll(RegExp(r'\bsecond\b'), '2nd')
        .replaceAll(RegExp(r'\bthird\b'), '3rd')
        .replaceAll(RegExp(r'\bfourth\b'), '4th');
    for (final group in <String, String>{
      'bathroom|bathrooms|toilet|toilets|washroom|comfortroom|pee|cr':
          'restroom',
      'deans': 'dean',
      'classroom|classrooms|rm': 'room',
      'laboratories|laboratory|labs': 'lab',
      'teachers': 'faculty',
      'fees': 'fee',
      'paying|payment|settle': 'pay',
      'borrowing': 'borrow',
      'books': 'book',
    }.entries) {
      s = s.replaceAll(RegExp('\\b(?:${group.key})\\b'), group.value);
    }
    return s
        .replaceAll('comfort room', 'restroom')
        .replaceAll(RegExp(r'school fee|tuition fee'), 'tuition')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static bool _contains(String text, String phrase) =>
      phrase.isNotEmpty && ' $text '.contains(' $phrase ');

  static const _stop = {
    'where',
    'is',
    'are',
    'the',
    'a',
    'an',
    'can',
    'could',
    'you',
    'i',
    'we',
    'me',
    'my',
    'our',
    'find',
    'locate',
    'show',
    'please',
    'help',
    'how',
    'do',
    'get',
    'to',
    'need',
    'want',
    'looking',
    'for',
    'nearest',
    'closest',
    'here',
    'this',
    'that',
    'which',
    'tell',
    'location',
    'directions',
    'of',
    'in',
    'inside',
    'at',
    'on',
    'number',
    'no',
    'go',
    'somewhere',
    'there',
    'from',
    'current',
    'position',
    'near',
    'within',
    'department',
    'building',
  };

  static List<CampusSearchResult> search(
      List<CampusBuilding> buildings, String query,
      {LatLng? origin, String category = 'All'}) {
    var q = normalize(query);
    if (q.isEmpty) return [];
    // Select the longest explicit building alias before removing scope words.
    var scope = <String>{};
    var scopePhrase = '';
    const aliases = <String, List<String>>{
      '1': ['ccsict', 'computing department'],
      '6': ['centrum', 'centrum lab building'],
      '2': ['admin', 'admin building'],
      '60': ['new admin', 'new administration building'],
      '25': ['college of medicine', 'med building', 'com', 'comahp'],
      '64': ['coe', 'engineering', 'college of engineering'],
      '65': ['coe', 'engineering', 'college of engineering'],
      '9': ['ca', 'agri', 'agriculture', 'college of agriculture'],
      '14': ['cas', 'college of arts and sciences'],
      '21': ['vetmed', 'svm', 'veterinary medicine'],
      '31': ['ced', 'education', 'college of education'],
      '47': ['ced', 'education', 'college of education'],
      '19': ['cbapa'],
      '68': ['cbapa'],
      '48': ['ccje'],
    };
    for (final b in buildings) {
      for (final alias in [b.name, b.acronym, ...?aliases[b.id]]) {
        final phrase = normalize(alias);
        if (!_contains(q, phrase)) continue;
        if (phrase.length > scopePhrase.length) {
          scopePhrase = phrase;
          scope = {b.id};
        } else if (phrase == scopePhrase) {
          scope.add(b.id);
        }
      }
    }
    if (scopePhrase.isNotEmpty) {
      q = q.replaceAll(RegExp('\\b${RegExp.escape(scopePhrase)}\\b'), ' ');
      if (scope.contains('1') && scopePhrase == 'ccsict') scope.add('6');
    }
    final explicitNearest = _contains(q, 'nearest') || _contains(q, 'closest');
    final tokens = q
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty && !_stop.contains(w))
        .toSet();
    // Unresolved short constraints must not silently search the entire campus.
    final constraintText = normalize(query).replaceAll(
        RegExp(
            r'office of (?:the )?(vice dean|dean|vice president|president|registrar)'),
        'office');
    if (scope.isEmpty &&
        RegExp(r'\b(?:in|inside|at|of)\s+\S+').hasMatch(constraintText))
      return [];
    if (tokens.isEmpty && scope.isEmpty) return [];
    final results = <CampusSearchResult>[];
    final distance = const Distance();
    for (final b in buildings) {
      // Outdoor parking is associated by its own name, not its indoor parent ID.
      final scopeMatch = scope.isEmpty ||
          scope.contains(b.id) ||
          (tokens.contains('parking') &&
              _contains(normalize('${b.name} ${b.keywords}'), scopePhrase));
      if (!scopeMatch) continue;
      void consider(CampusRoom? room) {
        if (!matchesCategory(b, category, room: room, includeContents: false))
          return;
        if (tokens.isEmpty && room != null) return;
        final title = normalize(room?.title ?? b.name);
        // Building keywords often list contained offices: use only indoor
        // records when matching those services, not the parent's keyword list.
        final keywords = room?.keywords ?? b.keywords;
        var document = normalize(
            '$title $keywords ${room?.code ?? b.acronym} ${room?.floor ?? b.category} ${room?.category.name ?? ''}');
        if (title.contains('cashier'))
          document += ' pay tuition school fee cashier';
        if (title.contains('registrar'))
          document += ' student grade enrollment record transcript certificate';
        if (title.contains('faculty') &&
            title.contains('restroom') &&
            !tokens.contains('faculty')) return;
        if (room == null &&
            b.rooms.isNotEmpty &&
            tokens.any((t) => [
                  'office',
                  'dean',
                  'faculty',
                  'room',
                  'restroom',
                  'lab',
                  'cashier',
                  'tuition',
                  'pay',
                  'registrar'
                ].contains(t))) return;
        if (tokens.any((token) => !_contains(document, token))) return;
        var score = tokens.where((t) => _contains(title, t)).length * 10;
        if (tokens.isEmpty || title == tokens.join(' ')) score += 20;
        final coordinate = room?.coordinate ?? b.coordinate;
        results.add(CampusSearchResult(b, room,
            origin == null ? null : distance(origin, coordinate), score));
      }

      consider(null);
      if (tokens.isNotEmpty) {
        for (final room in b.rooms) {
          consider(room);
        }
      }
    }
    final nearest = scope.isEmpty || explicitNearest;
    results.sort((a, b) {
      if (nearest && origin != null) {
        final d = a.meters!.compareTo(b.meters!);
        if (d != 0) return d;
      }
      return b.score.compareTo(a.score);
    });
    return nearest && origin != null ? results.take(5).toList() : results;
  }
}
