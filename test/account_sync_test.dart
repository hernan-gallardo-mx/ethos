import 'package:ethos/models/routine.dart';
import 'package:ethos/services/account_sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('merges local and cloud data with local routines taking precedence', () {
    const localRoutine = Routine(
      id: 'shared',
      title: 'Local edit',
      frequency: RoutineFrequency.daily,
      times: [480],
    );
    const cloudRoutine = Routine(
      id: 'shared',
      title: 'Cloud edit',
      frequency: RoutineFrequency.daily,
      times: [600],
    );
    const cloudOnlyRoutine = Routine(
      id: 'cloud-only',
      title: 'Cloud routine',
      frequency: RoutineFrequency.weekly,
      times: [540],
      weekdays: {1},
    );

    final merged = mergeRoutineData(
      const CloudRoutineData(
        routines: [localRoutine],
        completions: {'local-completion'},
      ),
      const CloudRoutineData(
        routines: [cloudRoutine, cloudOnlyRoutine],
        completions: {'cloud-completion'},
      ),
    );

    expect(merged.routines, contains(localRoutine));
    expect(merged.routines, contains(cloudOnlyRoutine));
    expect(merged.routines, hasLength(2));
    expect(
      merged.completions,
      {'local-completion', 'cloud-completion'},
    );
  });
}
