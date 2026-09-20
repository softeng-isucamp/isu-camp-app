enum NavigationHistoryStatus {
  previewed,
  navigationStarted,
  endedEarly,
  completed
}

class NavigationHistoryEntry {
  final String id;
  final String destinationId;
  final String destinationName;
  final String destinationAcronym;
  final String? roomId;
  final String? roomName;
  final DateTime createdAt;

  const NavigationHistoryEntry(
      {required this.id,
      required this.destinationId,
      required this.destinationName,
      required this.destinationAcronym,
      this.roomId,
      this.roomName,
      required this.createdAt});

  factory NavigationHistoryEntry.fromJson(Map<String, dynamic> json) =>
      NavigationHistoryEntry(
        id: json['id'] as String,
        destinationId: json['destinationId'] as String,
        destinationName: json['destinationName'] as String,
        destinationAcronym: json['destinationAcronym'] as String,
        roomId: json['roomId'] as String?,
        roomName: json['roomName'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String).toLocal(),
      );
}
