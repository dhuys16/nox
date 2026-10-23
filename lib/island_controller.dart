import 'dart:async';
import 'package:flutter/foundation.dart';
import 'services/local_store.dart';
import 'services/media_service.dart';

enum IslandTab { media, timer, reminders }

class IslandController extends ChangeNotifier {
  IslandController(this.store, this.mediaService);
  final LocalStore store;
  final MediaService mediaService;
  MediaSnapshot media = const MediaSnapshot();
  DateTime now = DateTime.now();
  DateTime? deadline;
  List<Reminder> due = [];
  int reminderCount = 0;
  String? error;
  bool hovered = false, pinned = false, commandBusy = false;
  bool _polling = false, _disposed = false;
  Timer? _ticker, _mediaTicker, _collapseTimer;
  IslandTab tab = IslandTab.media;

  bool get expanded => hovered || pinned || due.isNotEmpty;
  bool get timerActive => deadline != null;
  Duration get remaining {
    final delta = deadline?.difference(now) ?? Duration.zero;
    return delta.isNegative ? Duration.zero : delta;
  }

  String get clock =>
      '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}';
  String get countdown {
    final seconds = (remaining.inMilliseconds / 1000).ceil();
    final hours = seconds ~/ 3600;
    return '${hours > 0 ? '${_two(hours)}:' : ''}${_two(seconds ~/ 60 % 60)}:${_two(seconds % 60)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  Future<void> initialize() async {
    deadline = await store.readTimer();
    await _pollLocal();
    unawaited(_pollMedia());
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      now = DateTime.now();
      notifyListeners();
      unawaited(_pollLocal());
    });
    _mediaTicker = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollMedia(),
    );
  }

  bool _readingMedia = false;
  Future<void> _pollMedia() async {
    if (_readingMedia || _disposed) return;
    _readingMedia = true;
    try {
      final value = await mediaService.read();
      if (!_disposed) media = value;
    } catch (e) {
      if (!_disposed) {
        media = const MediaSnapshot();
        error = 'Media Windows: $e';
      }
    } finally {
      _readingMedia = false;
      if (!_disposed) notifyListeners();
    }
  }

  // Serialize DB checks, expiry and edits to avoid duplicate timer notifications.
  Future<void> _serial(Future<void> Function() action) async {
    while (_polling && !_disposed) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    if (_disposed) return;
    _polling = true;
    try {
      await action();
    } finally {
      _polling = false;
    }
  }

  DateTime? _lastLocalPoll;
  Future<void> _pollLocal() async {
    if (_polling || _disposed) return;
    if (_lastLocalPoll != null &&
        !now.isBefore(_lastLocalPoll!) &&
        now.difference(_lastLocalPoll!).inMilliseconds < 1000 &&
        !(deadline != null && !deadline!.isAfter(now))) {
      return;
    }
    await _serial(() async {
      try {
        if (deadline != null && !deadline!.isAfter(now)) {
          await store.finishTimer(deadline!);
          deadline = null;
        }
        due = await store.pending(now);
        reminderCount = await store.pendingCount();
        _lastLocalPoll = now;
      } catch (e) {
        error = 'Penyimpanan: $e';
      }
    });
    if (!_disposed) notifyListeners();
  }

  void hover(bool value) {
    _collapseTimer?.cancel();
    if (value) {
      hovered = true;
      notifyListeners();
    } else {
      _collapseTimer = Timer(const Duration(milliseconds: 350), () {
        hovered = false;
        if (!_disposed) notifyListeners();
      });
    }
  }

  void togglePin() {
    pinned = !pinned;
    notifyListeners();
  }

  void selectTab(IslandTab value) {
    tab = value;
    pinned = true;
    notifyListeners();
  }

  void clearError() {
    error = null;
    notifyListeners();
  }

  Future<void> setTimer(Duration? duration) => _serial(() async {
    final target = duration == null ? null : DateTime.now().add(duration);
    await store.saveTimer(target);
    deadline = target;
    now = DateTime.now();
    notifyListeners();
  });

  Future<void> addReminder(String title, DateTime time, {int? repeatMinutes}) =>
      _serial(() async {
        await store.addReminder(title, time, repeatMinutes: repeatMinutes);
        reminderCount = await store.pendingCount();
        notifyListeners();
      });

  Future<void> dismissReminder() => _serial(() async {
    if (due.isEmpty) return;
    await store.dismiss(due.first, DateTime.now());
    due = await store.pending(DateTime.now());
    reminderCount = await store.pendingCount();
    notifyListeners();
  });

  Future<void> control(String action) async {
    if (commandBusy) return;
    commandBusy = true;
    notifyListeners();
    try {
      await mediaService.command(action);
      await _pollMedia();
    } catch (e) {
      error = '$e';
    } finally {
      commandBusy = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> attempt(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      error = '$e';
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _mediaTicker?.cancel();
    _collapseTimer?.cancel();
    super.dispose();
  }
}
