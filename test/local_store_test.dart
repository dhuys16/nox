import 'dart:io';
import 'package:dynamic_island/services/local_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'overdue reminders survive restart until dismissed; repeats reschedule',
    () async {
      final directory = await Directory.systemTemp.createTemp('island-test-');
      final path = '${directory.path}/test.sqlite';
      final now = DateTime.utc(2026, 10, 19, 8);
      var store = await LocalStore.openAt(path);
      try {
        await store.addReminder(
          'Minum',
          now.subtract(const Duration(minutes: 2)),
          repeatMinutes: 60,
        );
        await store.addReminder('Rapat', now.add(const Duration(hours: 2)));
        await store.close();
        store = await LocalStore.openAt(path);
        final due = await store.pending(now);
        expect(due.single.title, 'Minum');
        expect(await store.pendingCount(), 2);
        await store.dismiss(due.single, now);
        expect(await store.pending(now), isEmpty);
        expect(
          (await store.pending(now.add(const Duration(hours: 1)))).single.title,
          'Minum',
        );
      } finally {
        await store.close();
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'timer deadline persists and expiry is atomically converted to a reminder',
    () async {
      final store = await LocalStore.openAt(':memory:');
      try {
        final deadline = DateTime.utc(2026, 10, 19, 9, 30);
        await store.saveTimer(deadline);
        expect(await store.readTimer(), deadline);
        await store.finishTimer(deadline);
        expect(await store.readTimer(), isNull);
        final due = await store.pending(deadline);
        expect(due.single.title, 'Timer selesai');
        await store.dismiss(due.single, deadline);
        expect(await store.pending(deadline), isEmpty);
      } finally {
        await store.close();
      }
    },
  );
}
