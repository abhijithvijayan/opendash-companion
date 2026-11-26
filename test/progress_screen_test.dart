import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide StepState;
import 'package:opendash_companion/scooter/operations.dart';
import 'package:opendash_companion/state/providers.dart';
import 'package:opendash_companion/ui/progress_screen.dart';

class _Fixed extends OperationNotifier {
  _Fixed(this.initial);
  final OperationState initial;
  @override
  OperationState? build() => initial;
}

OpStep _step(StepState s) => OpStep('verify', 'Check the signature')..state = s;

Future<void> _show(WidgetTester t, OperationState op) => t.pumpWidget(ProviderScope(
      overrides: [operationProvider.overrideWith(() => _Fixed(op))],
      child: const MaterialApp(home: ProgressScreen()),
    ));

const _manual = (url: 'https://github.com/abhijithvijayan/opendash-companion/releases/latest', hint: 'Get it by hand.');

void main() {
  testWidgets('a failed update offers the release page to download it by hand', (t) async {
    await _show(t, OperationState('Updating this app to 0.2.1', [_step(StepState.failed)], running: false, manual: _manual));
    expect(find.text('Download from GitHub'), findsOneWidget);
    expect(find.text('Get it by hand.'), findsOneWidget);
  });

  testWidgets('not while it runs, not once it worked, and not for an operation with no such page', (t) async {
    await _show(t, OperationState('Updating', [_step(StepState.running)], running: true, manual: _manual));
    expect(find.text('Download from GitHub'), findsNothing);
    await _show(t, OperationState('Updating', [_step(StepState.done)], running: false, manual: _manual));
    expect(find.text('Download from GitHub'), findsNothing);
    await _show(t, OperationState('Installing OpenDash', [_step(StepState.failed)], running: false));
    expect(find.text('Download from GitHub'), findsNothing);
  });
}
