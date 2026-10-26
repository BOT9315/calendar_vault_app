class CalendarEvent {
  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String time;

  CalendarEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.time,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'date': date.toIso8601String(),
      'time': time,
    };
  }

  factory CalendarEvent.fromJson(Map<String, dynamic> json) {
    return CalendarEvent(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      date: DateTime.parse(json['date'] as String),
      time: json['time'] as String,
    );
  }
}
