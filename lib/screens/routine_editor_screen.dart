import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:calendar_bridge/calendar_bridge.dart';

import '../data/routine_store.dart';
import '../models/routine.dart';
import '../services/calendar_export_service.dart';
import '../services/reminder_service.dart';

class RoutineEditorScreen extends StatefulWidget {
  const RoutineEditorScreen({
    required this.store,
    this.routine,
    this.reminderService,
    this.calendarExportService,
    super.key,
  });

  final RoutineStore store;
  final Routine? routine;
  final RoutineReminderSync? reminderService;
  final RoutineCalendarSync? calendarExportService;

  RoutineReminderSync get _reminderService =>
      reminderService ?? ReminderService.instance;
  RoutineCalendarSync get _calendarExportService =>
      calendarExportService ?? CalendarExportService.instance;

  @override
  State<RoutineEditorScreen> createState() => _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends State<RoutineEditorScreen> {
  late final TextEditingController _titleController;
  late final TextEditingController _noteController;
  late RoutineFrequency _frequency;
  late Set<int> _weekdays;
  late List<int> _times;
  late int _monthDay;
  late String? _reduceOnRoutineId;
  late bool _remindersEnabled;
  late bool _exportToCalendar;
  List<DeviceCalendar> _calendars = [];
  String? _selectedCalendarId;
  bool _loadingCalendars = false;
  bool _saving = false;

  bool get _isEditing => widget.routine != null;

  @override
  void initState() {
    super.initState();
    final routine = widget.routine;
    _titleController = TextEditingController(text: routine?.title ?? '');
    _noteController = TextEditingController(text: routine?.note ?? '');
    _frequency = routine?.frequency ?? RoutineFrequency.daily;
    _weekdays = routine?.weekdays.toSet() ?? {1, 2, 3, 4, 5, 6, 7};
    _times = routine?.times.toList() ?? [540];
    _monthDay = routine?.monthDay ?? DateTime.now().day;
    _reduceOnRoutineId = routine?.reduceOnRoutineId;
    _remindersEnabled = routine?.remindersEnabled ?? false;
    _exportToCalendar = routine?.exportToCalendar ?? false;
    if (_exportToCalendar) _loadCalendarChoices();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit routine' : 'New routine'),
        actions: [
          IconButton(
            tooltip: 'Save routine',
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.check_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                TextField(
                  controller: _titleController,
                  autofocus: !_isEditing,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 48,
                  decoration: const InputDecoration(
                      labelText: 'Routine name',
                      hintText: 'What do you want to make a habit?'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _noteController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLength: 90,
                  decoration: const InputDecoration(
                      labelText: 'Note',
                      hintText: 'Optional context or a gentle nudge'),
                ),
                const SizedBox(height: 22),
                _sectionLabel('REPEAT'),
                const SizedBox(height: 10),
                SegmentedButton<RoutineFrequency>(
                  segments: const [
                    ButtonSegment(
                        value: RoutineFrequency.daily, label: Text('Daily')),
                    ButtonSegment(
                        value: RoutineFrequency.weekly, label: Text('Weekly')),
                    ButtonSegment(
                        value: RoutineFrequency.monthly,
                        label: Text('Monthly')),
                    ButtonSegment(
                        value: RoutineFrequency.custom, label: Text('Custom')),
                  ],
                  selected: {_frequency},
                  showSelectedIcon: false,
                  onSelectionChanged: (selection) => setState(() {
                    _frequency = selection.first;
                    if ((_frequency == RoutineFrequency.weekly ||
                            _frequency == RoutineFrequency.custom) &&
                        _weekdays.isEmpty) {
                      _weekdays = {DateTime.now().weekday};
                    }
                  }),
                ),
                if (_frequency == RoutineFrequency.weekly ||
                    _frequency == RoutineFrequency.custom) ...[
                  const SizedBox(height: 18),
                  _sectionLabel('DAYS OF THE WEEK'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 7,
                    children: List.generate(7, (index) {
                      final day = index + 1;
                      final selected = _weekdays.contains(day);
                      return FilterChip(
                        label: Text(_dayLabel(day)),
                        selected: selected,
                        onSelected: (value) => setState(() {
                          if (value) {
                            _weekdays.add(day);
                          } else if (_weekdays.length > 1) {
                            _weekdays.remove(day);
                          }
                        }),
                      );
                    }),
                  ),
                ],
                if (_frequency == RoutineFrequency.monthly) ...[
                  const SizedBox(height: 18),
                  _sectionLabel('DAY OF THE MONTH'),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      IconButton.filledTonal(
                          onPressed: _monthDay > 1
                              ? () => setState(() => _monthDay--)
                              : null,
                          icon: const Icon(Icons.remove_rounded)),
                      Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Text('$_monthDay',
                              style: theme.textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w700))),
                      IconButton.filledTonal(
                          onPressed: _monthDay < 31
                              ? () => setState(() => _monthDay++)
                              : null,
                          icon: const Icon(Icons.add_rounded)),
                      const SizedBox(width: 10),
                      Text('of each month',
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(child: _sectionLabel('TIME OF DAY')),
                    TextButton.icon(
                      onPressed: _addTime,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Add time'),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                ..._times
                    .asMap()
                    .entries
                    .map((entry) => _timeRow(entry.key, entry.value)),
                const SizedBox(height: 22),
                _sectionLabel('ON OVERLAPPING DAYS'),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _reduceOnRoutineId,
                  decoration: const InputDecoration(
                      labelText: 'Reduce this routine to once when…'),
                  items: [
                    const DropdownMenuItem<String?>(
                        value: null, child: Text('No adjustment')),
                    ...widget.store.routines
                        .where((routine) => routine.id != widget.routine?.id)
                        .map((routine) => DropdownMenuItem<String?>(
                            value: routine.id,
                            child: Text('“${routine.title}” is scheduled'))),
                  ],
                  onChanged: (value) =>
                      setState(() => _reduceOnRoutineId = value),
                ),
                const SizedBox(height: 10),
                Text(
                  'For example, schedule minoxidil morning and evening, then choose Derma roll here to show just one application on roller days.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 22),
                Card(
                  child: SwitchListTile.adaptive(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    title: const Text('Remind me'),
                    subtitle:
                        const Text('A notification at each scheduled time'),
                    value: _remindersEnabled,
                    onChanged: (value) async {
                      if (value) {
                        final granted =
                            await widget._reminderService.requestPermission();
                        if (!context.mounted) return;
                        if (!granted) {
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                              content: Text(
                                  'Notifications are not enabled for Ethos.')));
                          return;
                        }
                      }
                      if (!mounted) return;
                      setState(() => _remindersEnabled = value);
                    },
                  ),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        title: const Text('Export to calendar'),
                        subtitle: const Text(
                          'Add this routine to a device calendar',
                        ),
                        trailing: Switch.adaptive(
                          key: const ValueKey('calendar-export-switch'),
                          value: _exportToCalendar,
                          onChanged: _loadingCalendars
                              ? null
                              : (value) => value
                                  ? _enableCalendarExport()
                                  : setState(
                                      () => _exportToCalendar = false,
                                    ),
                        ),
                      ),
                      if (_exportToCalendar && _calendars.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: DropdownButtonFormField<String>(
                            initialValue: _calendars.any((calendar) =>
                                    calendar.id == _selectedCalendarId)
                                ? _selectedCalendarId
                                : null,
                            decoration: const InputDecoration(
                              labelText: 'Device calendar',
                            ),
                            items: _calendars
                                .map((calendar) => DropdownMenuItem(
                                      value: calendar.id,
                                      child: Text(calendar.name),
                                    ))
                                .toList(),
                            onChanged: (calendarId) async {
                              setState(() => _selectedCalendarId = calendarId);
                              await widget._calendarExportService
                                  .selectCalendar(calendarId);
                            },
                          ),
                        ),
                      if (_exportToCalendar && _calendars.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _loadingCalendars
                                    ? 'Loading calendars…'
                                    : 'Choose a writable device calendar to export this routine.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              if (!_loadingCalendars)
                                TextButton.icon(
                                  onPressed: _enableCalendarExport,
                                  icon: const Icon(Icons.calendar_month),
                                  label: const Text('Choose calendar'),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check_rounded),
                  label: Text(_isEditing ? 'Save changes' : 'Create routine'),
                  style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _timeRow(int index, int minutes) {
    final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.schedule_rounded),
          title: Text(_timePeriod(minutes),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(time.format(context)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                  tooltip: 'Choose time',
                  onPressed: () => _pickTime(index),
                  icon: const Icon(Icons.edit_outlined)),
              if (_times.length > 1)
                IconButton(
                    tooltip: 'Remove time',
                    onPressed: () => setState(() => _times.removeAt(index)),
                    icon: const Icon(Icons.close_rounded)),
            ],
          ),
          onTap: () => _pickTime(index),
        ),
      ),
    );
  }

  Widget _sectionLabel(String label) => Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.15,
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      );

  Future<void> _addTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    if (_times.contains(minutes)) return;
    setState(() => _times = [..._times, minutes]..sort());
  }

  Future<void> _pickTime(int index) async {
    final current = _times[index];
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    setState(() {
      _times[index] = minutes;
      _times = _times.toSet().toList()..sort();
    });
  }

  Future<void> _save() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Give your routine a name first.')));
      return;
    }
    setState(() => _saving = true);
    final previous = widget.routine;
    final routine = Routine(
      id: previous?.id ??
          'routine-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(10000)}',
      title: title,
      note: _noteController.text.trim(),
      frequency: _frequency,
      times: _times.toList()..sort(),
      weekdays: _weekdays,
      monthDay: _monthDay,
      reduceOnRoutineId: _reduceOnRoutineId,
      remindersEnabled: _remindersEnabled,
      exportToCalendar: _exportToCalendar,
    );
    await widget.store.saveRoutine(routine);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    if (_exportToCalendar || previous?.exportToCalendar == true) {
      try {
        await widget._calendarExportService.syncRoutine(routine);
      } on CalendarBridgeException catch (error) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Routine saved, but calendar export could not be updated: '
            '${error.message}',
          ),
        ));
      } on PlatformException catch (error) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Routine saved, but calendar export could not be updated: '
            '${error.message ?? error.code}',
          ),
        ));
      } on MissingPluginException catch (error) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Routine saved, but calendar export could not be updated: '
            '${error.message}',
          ),
        ));
      } on StateError catch (error) {
        messenger.showSnackBar(SnackBar(
          content: Text(
            'Routine saved, but calendar export could not be updated: $error',
          ),
        ));
      }
    }
    try {
      await widget._reminderService.sync(widget.store.routines);
    } on PlatformException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Routine saved, but reminders could not be updated: '
          '${error.message ?? error.code}',
        ),
      ));
    } on MissingPluginException catch (error) {
      messenger.showSnackBar(SnackBar(
        content: Text(
          'Routine saved, but reminders could not be updated: ${error.message}',
        ),
      ));
    }
  }

  Future<void> _enableCalendarExport() async {
    setState(() => _loadingCalendars = true);
    try {
      final calendars = await widget._calendarExportService
          .calendars(requestPermission: true);
      if (!mounted) return;
      if (calendars.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
            'No writable calendars were found, or calendar access was denied.',
          ),
        ));
        return;
      }

      final savedCalendar =
          await widget._calendarExportService.selectedCalendarId();
      final selected = calendars.any((calendar) => calendar.id == savedCalendar)
          ? savedCalendar
          : calendars.first.id;
      await widget._calendarExportService.selectCalendar(selected);
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        _selectedCalendarId = selected;
        _exportToCalendar = true;
      });
    } on CalendarBridgeException catch (error) {
      _showCalendarError(error.message);
    } on PlatformException catch (error) {
      _showCalendarError(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      _showCalendarError(error.message ?? 'Calendar access is unavailable.');
    } finally {
      if (mounted) setState(() => _loadingCalendars = false);
    }
  }

  Future<void> _loadCalendarChoices() async {
    setState(() => _loadingCalendars = true);
    try {
      final calendars = await widget._calendarExportService.calendars();
      final selected = await widget._calendarExportService.selectedCalendarId();
      if (!mounted) return;
      setState(() {
        _calendars = calendars;
        _selectedCalendarId = selected;
      });
    } on CalendarBridgeException catch (error) {
      _showCalendarError(error.message);
    } on PlatformException catch (error) {
      _showCalendarError(error.message ?? error.code);
    } on MissingPluginException catch (error) {
      _showCalendarError(error.message ?? 'Calendar access is unavailable.');
    } finally {
      if (mounted) setState(() => _loadingCalendars = false);
    }
  }

  void _showCalendarError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Calendar access failed: $message')),
    );
  }

  String _timePeriod(int minutes) {
    if (minutes < 720) return 'Morning';
    if (minutes < 1020) return 'Afternoon';
    return 'Evening';
  }

  String _dayLabel(int day) =>
      const ['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'][day - 1];
}
