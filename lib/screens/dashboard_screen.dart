import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../data/routine_store.dart';
import '../models/routine.dart';
import '../services/reminder_service.dart';
import 'routine_editor_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.store,
    this.reminderService,
    super.key,
  });

  final RoutineStore store;
  final RoutineReminderSync? reminderService;

  RoutineReminderSync get _reminderService =>
      reminderService ?? ReminderService.instance;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  DateTime _selectedDate = DateTime.now();
  late DateTime _weekStart;
  bool _isMonthlyView = false;

  @override
  void initState() {
    super.initState();
    final today = DateTime.now();
    _weekStart = DateTime(today.year, today.month, today.day)
        .subtract(Duration(days: today.weekday - 1));
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        if (!widget.store.isReady) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        final occurrences = occurrencesForDate(
          widget.store.routines,
          _selectedDate,
        );
        final periodStats = _periodStats();
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 22,
            title: Row(
              children: [
                Icon(Icons.spa_rounded,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text('ethos',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: widget.store.syncError == null
                    ? widget.store.isSignedIn
                        ? 'Account and cloud sync'
                        : 'Sync across devices'
                    : 'Cloud sync needs attention',
                onPressed: _showAccountDialog,
                icon: Icon(
                  widget.store.syncError != null
                      ? Icons.cloud_off_outlined
                      : widget.store.isSignedIn
                          ? Icons.account_circle_outlined
                          : Icons.cloud_sync_outlined,
                ),
              ),
              IconButton(
                tooltip: 'Add a routine',
                onPressed: () => _openEditor(),
                icon: const Icon(Icons.add_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final content = _dashboardContent(occurrences, periodStats);
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: content,
                  ),
                );
              },
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _openEditor(),
            icon: const Icon(Icons.add_rounded),
            label: const Text('New routine'),
          ),
        );
      },
    );
  }

  Future<void> _showAccountDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: widget.store,
        builder: (context, _) => AlertDialog(
          title: Text(
            widget.store.isSignedIn ? 'Cloud sync' : 'Sync across devices',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!widget.store.supportsCloudSync)
                const Text('Cloud sync is available on Android and iOS.')
              else if (widget.store.isSignedIn)
                Text(
                    'Signed in as ${widget.store.accountEmail ?? 'Google user'}')
              else
                const Text(
                  'Sign in with Google to back up your routines and completion history.',
                ),
              if (widget.store.syncError != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.store.syncError!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              if (widget.store.isSyncing) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: widget.store.isSyncing
                  ? null
                  : () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            if (widget.store.isSignedIn) ...[
              if (widget.store.syncError != null)
                TextButton(
                  onPressed: widget.store.isSyncing
                      ? null
                      : () => _retryCloudSync(context),
                  child: const Text('Retry sync'),
                ),
              TextButton(
                onPressed:
                    widget.store.isSyncing ? null : () => _signOut(context),
                child: const Text('Sign out'),
              ),
            ] else if (widget.store.supportsCloudSync)
              FilledButton(
                onPressed:
                    widget.store.isSyncing ? null : () => _signIn(context),
                child: const Text('Continue with Google'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _signIn(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    try {
      await widget.store.signInWithGoogle();
    } on FirebaseException catch (error) {
      _showAccountError(error.message ?? error.code);
    } on PlatformException catch (error) {
      _showAccountError(error.message ?? error.code);
    } on GoogleSignInException catch (error) {
      if (error.code != GoogleSignInExceptionCode.canceled) {
        _showAccountError(error.description ?? error.code.name);
      }
    } on UnsupportedError catch (error) {
      _showAccountError(error.message ?? 'Google sign-in is unavailable.');
    }
  }

  Future<void> _retryCloudSync(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    await widget.store.retryCloudSync();
  }

  Future<void> _signOut(BuildContext dialogContext) async {
    Navigator.of(dialogContext).pop();
    try {
      await widget.store.signOut();
    } on FirebaseException catch (error) {
      _showAccountError(error.message ?? error.code);
    } on PlatformException catch (error) {
      _showAccountError(error.message ?? error.code);
    }
  }

  void _showAccountError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Account sync failed: $message')),
    );
  }

  Widget _dashboardContent(
    List<RoutineOccurrence> occurrences,
    ({int done, int total}) periodStats,
  ) {
    final theme = Theme.of(context);
    final fraction =
        periodStats.total == 0 ? 0.0 : periodStats.done / periodStats.total;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 100),
      children: [
        Text(
          _isToday(_selectedDate)
              ? 'A steady day starts here.'
              : _dateHeadline(_selectedDate),
          style: theme.textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text(
          _isToday(_selectedDate)
              ? 'Small promises. Kept, one at a time.'
              : 'Your routine, one day at a time.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 22),
        _viewToggle(),
        const SizedBox(height: 14),
        _weekProgressCard(periodStats, fraction),
        const SizedBox(height: 18),
        _periodNavigation(),
        const SizedBox(height: 10),
        _isMonthlyView ? _monthSelector() : _weekSelector(),
        const SizedBox(height: 26),
        Row(
          children: [
            Expanded(
              child: Text(
                _isToday(_selectedDate)
                    ? "Today's routine"
                    : _dateHeadline(_selectedDate),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
                '${_doneForDate(occurrences, _selectedDate)}/${occurrences.length}',
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 12),
        if (occurrences.isEmpty)
          _emptyDay()
        else
          ..._groupedOccurrences(occurrences),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
                child: Text('Your routines',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700))),
            TextButton.icon(
              onPressed: () => _openEditor(),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...widget.store.routines.map(_routineSummary),
      ],
    );
  }

  Widget _viewToggle() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(
            value: false,
            label: Text('Weekly'),
            icon: Icon(Icons.view_week_outlined)),
        ButtonSegment(
            value: true,
            label: Text('Monthly'),
            icon: Icon(Icons.calendar_month_outlined)),
      ],
      selected: {_isMonthlyView},
      onSelectionChanged: (selection) {
        setState(() {
          _isMonthlyView = selection.first;
        });
      },
    );
  }

  Widget _periodNavigation() {
    final theme = Theme.of(context);
    final title = _isMonthlyView
        ? '${_monthLong(_selectedDate.month)} ${_selectedDate.year}'
        : _weekLabel();
    return Row(
      children: [
        IconButton(
          tooltip: _isMonthlyView ? 'Previous month' : 'Previous week',
          onPressed: _movePeriodBackward,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Expanded(
          child: Center(
            child: Text(
              title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        IconButton(
          tooltip: _isMonthlyView ? 'Next month' : 'Next week',
          onPressed: _movePeriodForward,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
        TextButton(
          onPressed: () => _selectDate(DateTime.now()),
          child: const Text('Today'),
        ),
      ],
    );
  }

  Widget _weekProgressCard(({int done, int total}) stats, double fraction) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _isMonthlyView ? 'THIS MONTH' : 'THIS WEEK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text('${stats.done} of ${stats.total} done',
                          style: theme.textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ],
                  ),
                ),
                Text('${(fraction * 100).round()}%',
                    style: theme.textTheme.titleLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 8,
                backgroundColor: color.withValues(alpha: 0.12),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              stats.total == 0
                  ? 'Add a routine to shape your ${_isMonthlyView ? 'month' : 'week'}.'
                  : '${stats.total - stats.done} ${stats.total - stats.done == 1 ? 'step' : 'steps'} still on your list',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  Widget _weekSelector() {
    final theme = Theme.of(context);
    return Row(
      children: List.generate(7, (index) {
        final date = _weekStart.add(Duration(days: index));
        final isSelected = _sameDate(date, _selectedDate);
        final occurrences = occurrencesForDate(widget.store.routines, date);
        final done = _doneForDate(occurrences, date);
        final allDone = occurrences.isNotEmpty && done == occurrences.length;
        return Expanded(
          child: Semantics(
            button: true,
            selected: isSelected,
            label: '${_weekdayShort(date.weekday)}, ${date.day}',
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _selectDate(date),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 170),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  children: [
                    Text(
                      _weekdayShort(date.weekday),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${date.day}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? theme.colorScheme.onPrimary.withValues(alpha: 0.8)
                            : allDone
                                ? theme.colorScheme.primary
                                : occurrences.isEmpty
                                    ? Colors.transparent
                                    : theme.colorScheme.outlineVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _monthSelector() {
    final theme = Theme.of(context);
    final firstOfMonth = DateTime(_selectedDate.year, _selectedDate.month);
    final leadingDays = firstOfMonth.weekday - 1;
    final daysInMonth =
        DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    final cellCount = ((leadingDays + daysInMonth + 6) ~/ 7) * 7;
    const weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(
      children: [
        Row(
          children: [
            for (final weekday in weekdays)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      weekday,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            mainAxisSpacing: 4,
            crossAxisSpacing: 4,
          ),
          itemCount: cellCount,
          itemBuilder: (context, index) {
            final day = index - leadingDays + 1;
            if (day < 1 || day > daysInMonth) return const SizedBox.shrink();

            final date = DateTime(_selectedDate.year, _selectedDate.month, day);
            final selected = _sameDate(date, _selectedDate);
            final today = _isToday(date);
            final occurrences = occurrencesForDate(widget.store.routines, date);
            final done = _doneForDate(occurrences, date);
            final allDone =
                occurrences.isNotEmpty && done == occurrences.length;
            final dayTextColor = selected
                ? theme.colorScheme.onPrimary
                : theme.colorScheme.onSurface;

            return Semantics(
              button: true,
              selected: selected,
              label: '${_monthLong(date.month)} ${date.day}',
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => _selectDate(date),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 170),
                  decoration: BoxDecoration(
                    color: selected
                        ? theme.colorScheme.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    border: today && !selected
                        ? Border.all(color: theme.colorScheme.primary)
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$day',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: dayTextColor,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: selected
                              ? theme.colorScheme.onPrimary
                                  .withValues(alpha: 0.8)
                              : allDone
                                  ? theme.colorScheme.primary
                                  : occurrences.isEmpty
                                      ? Colors.transparent
                                      : theme.colorScheme.outlineVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  List<Widget> _groupedOccurrences(List<RoutineOccurrence> occurrences) {
    const groups = <String, (int, int)>{
      'Morning': (0, 720),
      'Afternoon': (720, 1020),
      'Evening': (1020, 1440),
    };
    final widgets = <Widget>[];
    for (final entry in groups.entries) {
      final items = occurrences
          .where((item) =>
              item.minuteOfDay >= entry.value.$1 &&
              item.minuteOfDay < entry.value.$2)
          .toList();
      if (items.isEmpty) continue;
      widgets.add(Padding(
        padding: const EdgeInsets.only(top: 10, bottom: 7),
        child: Text(entry.key.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                letterSpacing: 1.1,
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ));
      widgets.addAll(items.map(_occurrenceTile));
    }
    return widgets;
  }

  Widget _occurrenceTile(RoutineOccurrence occurrence) {
    final key = occurrence.completionKey(_selectedDate);
    final done = widget.store.completions.contains(key);
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: [
            Icon(Icons.circle_outlined,
                size: 19,
                color: theme.colorScheme.primary.withValues(alpha: 0.75)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(occurrence.routine.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  if (occurrence.routine.note.isNotEmpty)
                    Text(occurrence.routine.note,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            Text(occurrence.time.format(context),
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            const SizedBox(width: 8),
            Checkbox.adaptive(
              value: done,
              onChanged: (_) => widget.store.toggleCompletion(key),
              shape: const CircleBorder(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyDay() {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.spa_outlined,
                color: theme.colorScheme.primary, size: 28),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                widget.store.routines.isEmpty
                    ? 'Start with one routine that matters to you.'
                    : 'A clear day. Enjoy the breathing room.',
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _routineSummary(Routine routine) {
    final theme = Theme.of(context);
    final schedule = _scheduleLabel(routine);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          leading: CircleAvatar(
            radius: 19,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Icon(Icons.check_rounded,
                color: theme.colorScheme.onPrimaryContainer, size: 19),
          ),
          title: Text(routine.title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          subtitle:
              Text(schedule, maxLines: 2, overflow: TextOverflow.ellipsis),
          trailing: PopupMenuButton<String>(
            tooltip: 'Routine options',
            onSelected: (value) async {
              if (value == 'edit') {
                await _openEditor(routine: routine);
              } else if (value == 'delete') {
                await widget.store.deleteRoutine(routine.id);
                await widget._reminderService.sync(widget.store.routines);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
      ),
    );
  }

  ({int done, int total}) _periodStats() {
    var total = 0;
    var done = 0;
    final today = DateTime.now();
    final start = _isMonthlyView
        ? DateTime(_selectedDate.year, _selectedDate.month)
        : _weekStart;
    final dayCount = _isMonthlyView
        ? DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day
        : 7;
    for (var index = 0; index < dayCount; index++) {
      final date = start.add(Duration(days: index));
      if (date.isAfter(DateTime(today.year, today.month, today.day))) continue;
      final items = occurrencesForDate(widget.store.routines, date);
      total += items.length;
      done += _doneForDate(items, date);
    }
    return (done: done, total: total);
  }

  void _selectDate(DateTime date) {
    setState(() {
      _selectedDate = date;
      _weekStart = DateTime(date.year, date.month, date.day)
          .subtract(Duration(days: date.weekday - 1));
    });
  }

  void _movePeriodBackward() => _movePeriod(-1);

  void _movePeriodForward() => _movePeriod(1);

  void _movePeriod(int offset) {
    final target = _isMonthlyView
        ? DateTime(_selectedDate.year, _selectedDate.month + offset, 1)
        : _selectedDate.add(Duration(days: 7 * offset));
    if (_isMonthlyView) {
      final lastDay = DateTime(target.year, target.month + 1, 0).day;
      _selectDate(DateTime(
          target.year, target.month, _selectedDate.day.clamp(1, lastDay)));
    } else {
      _selectDate(target);
    }
  }

  String _weekLabel() {
    final lastDay = _weekStart.add(const Duration(days: 6));
    if (_weekStart.month == lastDay.month) {
      return '${_monthShort(_weekStart.month)} ${_weekStart.day}–${lastDay.day}';
    }
    return '${_monthShort(_weekStart.month)} ${_weekStart.day}–${_monthShort(lastDay.month)} ${lastDay.day}';
  }

  int _doneForDate(List<RoutineOccurrence> items, DateTime date) => items
      .where(
          (item) => widget.store.completions.contains(item.completionKey(date)))
      .length;

  Future<void> _openEditor({Routine? routine}) async {
    await Navigator.of(context).push<void>(MaterialPageRoute(
      builder: (_) => RoutineEditorScreen(
        store: widget.store,
        routine: routine,
        reminderService: widget.reminderService,
      ),
    ));
  }

  bool _isToday(DateTime date) => _sameDate(date, DateTime.now());

  bool _sameDate(DateTime first, DateTime second) =>
      first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;

  String _dateHeadline(DateTime date) =>
      '${_weekdayLong(date.weekday)}, ${_monthShort(date.month)} ${date.day}';

  String _weekdayShort(int weekday) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][weekday - 1];

  String _weekdayLong(int weekday) => const [
        'Monday',
        'Tuesday',
        'Wednesday',
        'Thursday',
        'Friday',
        'Saturday',
        'Sunday'
      ][weekday - 1];

  String _monthShort(int month) => const [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][month - 1];

  String _monthLong(int month) => const [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ][month - 1];

  String _scheduleLabel(Routine routine) {
    final times = routine.times.map((minutes) {
      final time = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
      return time.format(context);
    }).join(' · ');
    final frequency = switch (routine.frequency) {
      RoutineFrequency.daily => 'Daily',
      RoutineFrequency.weekly => 'Weekly · ${_weekdayNames(routine.weekdays)}',
      RoutineFrequency.custom => _weekdayNames(routine.weekdays),
      RoutineFrequency.monthly => 'Monthly · day ${routine.monthDay}',
    };
    return '$frequency · $times${routine.remindersEnabled ? ' · Reminders on' : ''}';
  }

  String _weekdayNames(Set<int> days) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return (days.toList()..sort()).map((day) => names[day - 1]).join(', ');
  }
}
