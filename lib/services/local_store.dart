import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class Reminder {
  const Reminder(this.id, this.title, this.due, this.repeatMinutes);
  final int id;
  final String title;
  final DateTime due;
  final int? repeatMinutes;

  factory Reminder.fromRow(Map<String, Object?> row) => Reminder(
    row['id']! as int,
    row['title']! as String,
    DateTime.fromMillisecondsSinceEpoch(row['due_ms']! as int, isUtc: true),
    row['repeat_minutes'] as int?,
  );
}

class LocalStore {
  LocalStore(this.db);
  final Database db;

  static Future<LocalStore> open() async {
    sqfliteFfiInit();
    final supportDirectory = await getApplicationSupportDirectory();
    // Keep the original storage key across product-name changes so reminders
    // and timer deadlines remain available after a branding update.
    final directory = Directory(
      p.join(p.dirname(supportDirectory.path), 'dynamic_island'),
    );
    await directory.create(recursive: true);
    return openAt(p.join(directory.path, 'island.sqlite'));
  }

  static Future<LocalStore> openAt(String path) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''CREATE TABLE reminders (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            title TEXT NOT NULL,
            due_ms INTEGER NOT NULL,
            repeat_minutes INTEGER,
            completed INTEGER NOT NULL DEFAULT 0
          )''');
          await db.execute(
            'CREATE INDEX reminders_due ON reminders(completed, due_ms)',
          );
          await db.execute(
            'CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
        },
      ),
    );
    return LocalStore(db);
  }

  Future<void> addReminder(
    String title,
    DateTime due, {
    int? repeatMinutes,
  }) async {
    await db.insert('reminders', {
      'title': title,
      'due_ms': due.toUtc().millisecondsSinceEpoch,
      'repeat_minutes': repeatMinutes,
    });
  }

  Future<List<Reminder>> pending(DateTime now) async => (await db.query(
    'reminders',
    where: 'completed = 0 AND due_ms <= ?',
    whereArgs: [now.toUtc().millisecondsSinceEpoch],
    orderBy: 'due_ms, id',
  )).map(Reminder.fromRow).toList();

  Future<int> pendingCount() async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM reminders WHERE completed = 0',
    );
    return rows.single['count']! as int;
  }

  Future<void> dismiss(Reminder reminder, DateTime now) async {
    await db.update(
      'reminders',
      reminder.repeatMinutes == null
          ? {'completed': 1}
          : {
              'due_ms': now
                  .toUtc()
                  .add(Duration(minutes: reminder.repeatMinutes!))
                  .millisecondsSinceEpoch,
            },
      where: 'id = ?',
      whereArgs: [reminder.id],
    );
  }

  Future<DateTime?> readTimer() async {
    final rows = await db.query(
      'settings',
      where: 'key = ?',
      whereArgs: ['timer_end'],
    );
    if (rows.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      int.parse(rows.first['value']! as String),
      isUtc: true,
    );
  }

  Future<void> saveTimer(DateTime? deadline) async {
    if (deadline == null) {
      await db.delete('settings', where: 'key = ?', whereArgs: ['timer_end']);
    } else {
      await db.insert('settings', {
        'key': 'timer_end',
        'value': '${deadline.toUtc().millisecondsSinceEpoch}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  // Atomically clear an expired timer and persist its notification.
  Future<void> finishTimer(DateTime deadline) async {
    await db.transaction((txn) async {
      await txn.delete('settings', where: 'key = ?', whereArgs: ['timer_end']);
      await txn.insert('reminders', {
        'title': 'Timer selesai',
        'due_ms': deadline.toUtc().millisecondsSinceEpoch,
      });
    });
  }

  Future<void> close() => db.close();
}
