import 'package:flutter/material.dart';

enum RoutineFrequency { daily, weekly, monthly, custom }

class Routine {
  const Routine({
    required this.id,
    required this.title,
    required this.frequency,
    required this.times,
    this.note = '',
    this.weekdays = const {},
    this.monthDay = 1,
    this.reduceOnRoutineId,
    this.remindersEnabled = false,
    this.exportToCalendar = false,
  });

  final String id;
  final String title;
  final String note;
  final RoutineFrequency frequency;
  final List<int> times;
  final Set<int> weekdays;
  final int monthDay;
  final String? reduceOnRoutineId;
  final bool remindersEnabled;
  final bool exportToCalendar;

  bool isScheduledOn(DateTime date) {
    switch (frequency) {
      case RoutineFrequency.daily:
        return true;
      case RoutineFrequency.weekly:
      case RoutineFrequency.custom:
        return weekdays.contains(date.weekday);
      case RoutineFrequency.monthly:
        return date.day == monthDay;
    }
  }

  Routine copyWith({
    String? id,
    String? title,
    String? note,
    RoutineFrequency? frequency,
    List<int>? times,
    Set<int>? weekdays,
    int? monthDay,
    String? reduceOnRoutineId,
    bool clearReduceOnRoutineId = false,
    bool? remindersEnabled,
    bool? exportToCalendar,
  }) {
    return Routine(
      id: id ?? this.id,
      title: title ?? this.title,
      note: note ?? this.note,
      frequency: frequency ?? this.frequency,
      times: times ?? this.times,
      weekdays: weekdays ?? this.weekdays,
      monthDay: monthDay ?? this.monthDay,
      reduceOnRoutineId: clearReduceOnRoutineId
          ? null
          : reduceOnRoutineId ?? this.reduceOnRoutineId,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      exportToCalendar: exportToCalendar ?? this.exportToCalendar,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'title': title,
        'note': note,
        'frequency': frequency.name,
        'times': times,
        'weekdays': weekdays.toList(),
        'monthDay': monthDay,
        'reduceOnRoutineId': reduceOnRoutineId,
        'remindersEnabled': remindersEnabled,
        'exportToCalendar': exportToCalendar,
      };

  factory Routine.fromJson(Map<String, Object?> json) {
    return Routine(
      id: json['id'] as String,
      title: json['title'] as String,
      note: json['note'] as String? ?? '',
      frequency: RoutineFrequency.values.firstWhere(
        (value) => value.name == json['frequency'],
        orElse: () => RoutineFrequency.daily,
      ),
      times: (json['times'] as List<Object?>? ?? const [540])
          .map((value) => value as int)
          .toList()
        ..sort(),
      weekdays: (json['weekdays'] as List<Object?>? ?? const [])
          .map((value) => value as int)
          .toSet(),
      monthDay: json['monthDay'] as int? ?? 1,
      reduceOnRoutineId: json['reduceOnRoutineId'] as String?,
      remindersEnabled: json['remindersEnabled'] as bool? ?? false,
      exportToCalendar: json['exportToCalendar'] as bool? ?? false,
    );
  }
}

class RoutineOccurrence {
  const RoutineOccurrence({
    required this.routine,
    required this.slot,
    required this.minuteOfDay,
  });

  final Routine routine;
  final int slot;
  final int minuteOfDay;

  String completionKey(DateTime date) =>
      '${routine.id}:${date.year}-${date.month}-${date.day}:$slot';

  TimeOfDay get time => TimeOfDay(
        hour: minuteOfDay ~/ 60,
        minute: minuteOfDay % 60,
      );
}

List<RoutineOccurrence> occurrencesForDate(
  List<Routine> routines,
  DateTime date,
) {
  final byId = {for (final routine in routines) routine.id: routine};
  final occurrences = <RoutineOccurrence>[];

  for (final routine in routines) {
    if (!routine.isScheduledOn(date)) continue;

    final linkedRoutine = routine.reduceOnRoutineId == null
        ? null
        : byId[routine.reduceOnRoutineId];
    // On overlap days, keep only the earliest slot of the linked routine.
    final reduceToday =
        linkedRoutine != null && linkedRoutine.isScheduledOn(date);
    final times = routine.times.toList()..sort();
    final visibleTimes = reduceToday ? times.take(1) : times;

    for (var slot = 0; slot < visibleTimes.length; slot++) {
      occurrences.add(RoutineOccurrence(
        routine: routine,
        slot: slot,
        minuteOfDay: visibleTimes.elementAt(slot),
      ));
    }
  }

  occurrences.sort((a, b) => a.minuteOfDay.compareTo(b.minuteOfDay));
  return occurrences;
}
