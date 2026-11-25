import 'package:workmanager/workmanager.dart';

/// Shared by main() and the About toggle so register and cancel agree.
const kUpdateCheckTask = 'opendash-update-check';

Future<void> scheduleUpdateCheck() {
  return Workmanager().registerPeriodicTask(
    kUpdateCheckTask,
    kUpdateCheckTask,
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> cancelUpdateCheck() => Workmanager().cancelByUniqueName(kUpdateCheckTask);
