import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'island_controller.dart';
import 'services/media_service.dart';
import 'services/window_region.dart';

const _accent = Color(0xffbea6ff);
const _ink = Color(0xfff0edf8);
const _muted = Color(0xff8d899c);
const _mint = Color(0xff8de2c6);

class IslandSpring extends Curve {
  const IslandSpring();
  @override
  double transformInternal(double t) {
    final spring = SpringSimulation(
      const SpringDescription(mass: 1, stiffness: 260, damping: 25),
      0,
      1,
      0,
    );
    return spring.x(t * .65) / spring.x(.65);
  }
}

class IslandView extends StatefulWidget {
  const IslandView({super.key, required this.controller, required this.region});
  final IslandController controller;
  final WindowRegion region;
  @override
  State<IslandView> createState() => _IslandViewState();
}

class _IslandViewState extends State<IslandView> {
  final _minutes = TextEditingController(text: '5');
  final _title = TextEditingController(text: 'Minum air');
  final _schedule = TextEditingController(text: '09:00');
  bool _repeat = false, _saving = false;
  String? _feedback;
  IslandController get c => widget.controller;

  @override
  void dispose() {
    _minutes.dispose();
    _title.dispose();
    _schedule.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: c,
    builder: (context, _) {
      final expanded = c.expanded;
      final wide = expanded || c.media.available || c.timerActive;
      return Scaffold(
        backgroundColor: Colors.transparent,
        body: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.only(top: 8),
            child: RegionTracking(
              region: widget.region,
              child: MouseRegion(
                onEnter: (_) => c.hover(true),
                onExit: (_) => c.hover(false),
                child: AnimatedContainer(
                  key: const ValueKey('island-shell'),
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : const Duration(milliseconds: 650),
                  curve: const IslandSpring(),
                  width: wide ? 400 : 200,
                  height: expanded ? 150 : 30,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xff1b1727),
                        Color(0xff0c0d12),
                        Color(0xff10121a),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(expanded ? 24 : 15),
                    border: Border.all(
                      color: const Color(0xff393243),
                      width: .7,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: LayoutBuilder(
                    builder: (context, constraints) => OverflowBox(
                      alignment: Alignment.topCenter,
                      // Final-width contents stay clipped inside the animated
                      // shell, so there is no flex overflow during expansion.
                      minWidth: expanded ? 400 : 0,
                      maxWidth: expanded ? 400 : constraints.maxWidth,
                      minHeight: 150,
                      maxHeight: 150,
                      child: expanded
                          ? _expanded()
                          : Align(
                              alignment: Alignment.topCenter,
                              child: SizedBox(height: 30, child: _compact()),
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _compact() => Semantics(
    button: true,
    label: 'Nox Panel. Klik untuk menyematkan panel.',
    child: InkWell(
      onTap: c.togglePin,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            if (!c.media.available || c.timerActive || c.due.isNotEmpty) ...[
              Icon(
                c.timerActive
                    ? Icons.timelapse_rounded
                    : Icons.dark_mode_rounded,
                size: 14,
                color: _accent,
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                c.due.isNotEmpty
                    ? c.due.first.title
                    : c.timerActive
                    ? 'Fokus  ${c.countdown}'
                    : c.media.available
                    ? c.media.title
                    : c.clock,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: c.media.available || c.timerActive
                    ? TextAlign.left
                    : TextAlign.center,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .7,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: 10),
            if (c.media.available && !c.timerActive)
              _Waveform(playing: c.media.playing)
            else
              const _StatusDot(color: _accent),
          ],
        ),
      ),
    ),
  );

  Widget _expanded() => Stack(
    children: [
      Positioned(left: 0, right: 0, top: 34, bottom: 0, child: _body()),
      Positioned(left: 14, top: 5, child: _navigation()),
      Positioned(
        right: 13,
        top: 8,
        child: Row(
          key: const ValueKey('window-actions'),
          children: [
            _SmallButton(
              label: c.pinned ? 'Lepas sematan' : 'Sematkan panel',
              icon: c.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              color: c.pinned ? _accent : _muted,
              onTap: c.togglePin,
            ),
            const SizedBox(width: 3),
            _SmallButton(
              label: 'Keluar aplikasi',
              icon: Icons.close_rounded,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    ],
  );
  Widget _navigation() => Container(
    key: const ValueKey('navigation-rail'),
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: const Color(0xff17151f),
      borderRadius: BorderRadius.circular(13),
      border: Border.all(color: const Color(0xff2b2636), width: .7),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final item in const [
          (IslandTab.media, 'Media', Icons.music_note_rounded),
          (IslandTab.timer, 'Timer', Icons.timelapse_rounded),
          (IslandTab.reminders, 'Jadwal', Icons.calendar_today_rounded),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Tooltip(
              message: item.$2,
              child: Semantics(
                selected: c.tab == item.$1,
                button: true,
                label: item.$2,
                child: InkWell(
                  key: ValueKey('nav-${item.$1.name}'),
                  borderRadius: BorderRadius.circular(9),
                  onTap: () {
                    c.selectTab(item.$1);
                    c.clearError();
                    setState(() => _feedback = null);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    width: 23,
                    height: 23,
                    decoration: BoxDecoration(
                      color: c.tab == item.$1
                          ? const Color(0xff352946)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Icon(
                      item.$3,
                      size: 15,
                      color: c.tab == item.$1 ? _accent : _muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
  Widget _body() {
    if (c.due.isNotEmpty) return _notification();
    if (c.error != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
        child: InkWell(
          onTap: c.clearError,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xff292020),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xfff0be8d),
                  size: 22,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '${c.error}\nKlik untuk menutup',
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _ink, fontSize: 10),
                  ),
                ),
                const Icon(Icons.close_rounded, color: _muted, size: 14),
              ],
            ),
          ),
        ),
      );
    }
    return AnimatedSwitcher(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      child: SizedBox.expand(
        key: ValueKey(c.tab),
        child: switch (c.tab) {
          IslandTab.media => _media(),
          IslandTab.timer => _timer(),
          IslandTab.reminders => _reminders(),
        },
      ),
    );
  }

  Widget _media() {
    final media = c.media;
    final enabled =
        !c.commandBusy && (media.playing ? media.canPause : media.canPlay);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 5),
      child: Column(
        children: [
          SizedBox(
            height: 18,
            child: Center(
              child: SizedBox(
                width: 220,
                child: Text(
                  media.available ? media.title : 'Your next favourite song.',
                  key: const ValueKey('media-title'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.2,
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            height: 13,
            child: Center(
              child: Text(
                media.available
                    ? media.artist
                    : 'Putar musik di Spotify atau browser',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 10),
              ),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 46,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TransportButton(
                  key: const ValueKey('media-previous'),
                  label: 'Lagu sebelumnya',
                  icon: Icons.skip_previous_rounded,
                  onTap: media.canPrevious && !c.commandBusy
                      ? () => c.control('previous')
                      : null,
                ),
                const SizedBox(width: 25),
                _AlbumControl(
                  key: const ValueKey('album-control'),
                  media: media,
                  busy: c.commandBusy,
                  onTap: enabled
                      ? () => c.control(media.playing ? 'pause' : 'play')
                      : null,
                ),
                const SizedBox(width: 25),
                _TransportButton(
                  key: const ValueKey('media-next'),
                  label: 'Lagu berikutnya',
                  icon: Icons.skip_next_rounded,
                  onTap: media.canNext && !c.commandBusy
                      ? () => c.control('next')
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 10,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _StatusDot(color: media.playing ? _mint : _muted, size: 4),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    media.available
                        ? media.playing
                              ? 'Sedang diputar  ·  klik sampul untuk jeda'
                              : 'Dijeda  ·  klik sampul untuk putar'
                        : 'Musik Anda, satu sentuhan dari sini.',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 8.5,
                      letterSpacing: .2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _timer() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
    child: c.timerActive
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const _StatusDot(color: _accent, size: 5),
                  const SizedBox(width: 6),
                  const Text(
                    'SESI FOKUS',
                    style: TextStyle(
                      color: _accent,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Selesai ${_time(c.deadline!.toLocal())}',
                    style: const TextStyle(color: _muted, fontSize: 10),
                  ),
                ],
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        c.countdown,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 36,
                          fontWeight: FontWeight.w300,
                          letterSpacing: 2,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => c.attempt(() => c.setTimer(null)),
                      icon: const Icon(Icons.stop_rounded, size: 15),
                      label: const Text('Akhiri'),
                      style: TextButton.styleFrom(
                        foregroundColor: _accent,
                        backgroundColor: const Color(0xff292236),
                        textStyle: const TextStyle(fontSize: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Text(
                'Satu hal pada satu waktu.',
                style: TextStyle(color: _muted, fontSize: 10),
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'MAKE TIME FOR FOCUS',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: _muted,
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.3,
                      ),
                    ),
                  ),
                  for (final minutes in const [5, 15, 25])
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _startTimer(minutes),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xff25212f),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$minutes m',
                            style: const TextStyle(
                              color: _accent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 9),
              SizedBox(
                height: 35,
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _minutes,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(4),
                        ],
                        style: const TextStyle(color: _ink, fontSize: 12),
                        decoration: const InputDecoration(
                          hintText: 'Durasi',
                          suffixText: 'menit',
                          prefixIcon: Icon(
                            Icons.hourglass_bottom_rounded,
                            size: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    FilledButton.icon(
                      onPressed: () => _startTimer(int.tryParse(_minutes.text)),
                      icon: const Icon(Icons.play_arrow_rounded, size: 17),
                      label: const Text('Mulai'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(92, 35),
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                _feedback ?? 'Pilih preset atau atur ritme Anda sendiri.',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: _feedback == null ? _muted : _accent,
                  fontSize: 9,
                  height: 1.2,
                ),
              ),
            ],
          ),
  );

  Future<void> _startTimer(int? minutes) async {
    if (minutes == null || minutes < 1 || minutes > 1440) {
      setState(() => _feedback = 'Masukkan durasi antara 1 dan 1440 menit.');
      return;
    }
    await c.attempt(() => c.setTimer(Duration(minutes: minutes)));
  }

  Widget _reminders() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 9, 20, 8),
    child: Column(
      children: [
        SizedBox(
          height: 37,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _title,
                  maxLength: 120,
                  style: const TextStyle(color: _ink, fontSize: 11),
                  decoration: const InputDecoration(
                    hintText: 'Ingatkan saya…',
                    counterText: '',
                    prefixIcon: Icon(
                      Icons.notifications_none_rounded,
                      size: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 7),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: _schedule,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d:]')),
                    LengthLimitingTextInputFormatter(5),
                  ],
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(hintText: 'HH:mm'),
                ),
              ),
              const SizedBox(width: 7),
              SizedBox.square(
                dimension: 36,
                child: IconButton.filled(
                  tooltip: 'Simpan jadwal',
                  onPressed: _saving ? null : _saveSchedule,
                  style: IconButton.styleFrom(
                    backgroundColor: _accent,
                    foregroundColor: const Color(0xff1b122d),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 14,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.add_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 26,
          child: Row(
            children: [
              Semantics(
                button: true,
                selected: _repeat,
                label: 'Ulang setiap 60 menit',
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _repeat = !_repeat),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _repeat
                          ? const Color(0xff30263f)
                          : const Color(0xff1d1c25),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _repeat
                              ? Icons.check_circle_rounded
                              : Icons.repeat_rounded,
                          size: 12,
                          color: _repeat ? _accent : _muted,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Tiap 60 menit',
                          style: TextStyle(
                            color: _repeat ? _accent : _muted,
                            fontSize: 9.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Spacer(),
              const _StatusDot(color: _mint, size: 4),
              const SizedBox(width: 5),
              Text(
                '${c.reminderCount} jadwal aktif',
                style: const TextStyle(color: _muted, fontSize: 9),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _feedback ?? 'Waktu lokal · jadwal terlewat disimpan untuk besok.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: _feedback == null ? _muted : _accent,
              fontSize: 8.5,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _notification() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 10),
    child: Row(
      children: [
        Container(
          width: 50,
          height: 64,
          decoration: BoxDecoration(
            color: const Color(0xff332839),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(
            Icons.notifications_active_rounded,
            size: 25,
            color: _accent,
          ),
        ),
        const SizedBox(width: 15),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'WAKTUNYA UNTUK ANDA  ·  ${c.due.length}',
                style: const TextStyle(
                  color: _accent,
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 4),
              Expanded(
                child: Text(
                  c.due.first.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                height: 28,
                child: TextButton.icon(
                  onPressed: () => c.attempt(c.dismissReminder),
                  icon: const Icon(Icons.check_rounded, size: 14),
                  label: Text(
                    c.due.first.repeatMinutes == null
                        ? 'Selesai'
                        : 'Selesai · ingatkan lagi',
                  ),
                  style: TextButton.styleFrom(
                    foregroundColor: _accent,
                    padding: const EdgeInsets.symmetric(horizontal: 0),
                    textStyle: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  Future<void> _saveSchedule() async {
    final parts = RegExp(
      r'^(\d{1,2}):(\d{2})$',
    ).firstMatch(_schedule.text.trim());
    final hour = int.tryParse(parts?.group(1) ?? '');
    final minute = int.tryParse(parts?.group(2) ?? '');
    if (_title.text.trim().isEmpty ||
        hour == null ||
        hour > 23 ||
        minute == null ||
        minute > 59) {
      setState(() => _feedback = 'Isi pengingat dan waktu HH:mm yang valid.');
      return;
    }
    final now = DateTime.now();
    var due = DateTime(now.year, now.month, now.day, hour, minute);
    if (!due.isAfter(now)) {
      due = DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
    setState(() => _saving = true);
    await c.attempt(() async {
      await c.addReminder(
        _title.text.trim(),
        due,
        repeatMinutes: _repeat ? 60 : null,
      );
      if (mounted) {
        setState(
          () => _feedback =
              'Tersimpan untuk ${due.day}/${due.month} pukul ${_time(due)}.',
        );
      }
    });
    if (mounted) setState(() => _saving = false);
  }

  static String _time(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = _muted,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 23,
    child: IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon, size: 12, color: color),
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size(23, 23),
      ),
    ),
  );
}

class _TransportButton extends StatelessWidget {
  const _TransportButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 38,
    child: IconButton(
      tooltip: label,
      onPressed: onTap,
      icon: Icon(icon, size: 25),
      style: IconButton.styleFrom(
        foregroundColor: _ink,
        disabledForegroundColor: const Color(0xff494653),
        backgroundColor: const Color(0xff24212e),
        disabledBackgroundColor: const Color(0xff19181f),
        hoverColor: const Color(0xff3b304e),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
      ),
    ),
  );
}

class _AlbumControl extends StatefulWidget {
  const _AlbumControl({
    super.key,
    required this.media,
    required this.busy,
    required this.onTap,
  });
  final MediaSnapshot media;
  final bool busy;
  final VoidCallback? onTap;
  @override
  State<_AlbumControl> createState() => _AlbumControlState();
}

class _AlbumControlState extends State<_AlbumControl> {
  bool _hovered = false, _pressed = false;
  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: widget.onTap != null,
    label: widget.media.playing
        ? 'Jeda musik dengan klik sampul'
        : 'Putar musik dengan klik sampul',
    child: AnimatedScale(
      scale: _pressed ? .95 : 1,
      duration: const Duration(milliseconds: 130),
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _hovered ? _accent : const Color(0xff514461),
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0x38a68be8),
              blurRadius: 13,
              spreadRadius: -2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _Artwork(media: widget.media),
              IgnorePointer(
                child: AnimatedOpacity(
                  opacity: widget.busy || _hovered || !widget.media.playing
                      ? 1
                      : 0,
                  duration: const Duration(milliseconds: 160),
                  child: ColoredBox(
                    color: const Color(0x24000000),
                    child: Center(
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xb31a1524),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: const Color(0x44ffffff)),
                        ),
                        child: widget.busy
                            ? const Padding(
                                padding: EdgeInsets.all(8),
                                child: CircularProgressIndicator(
                                  strokeWidth: 1.5,
                                  color: _ink,
                                ),
                              )
                            : Icon(
                                widget.media.playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 20,
                                color: _ink,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              Material(
                type: MaterialType.transparency,
                child: InkWell(
                  onTap: widget.onTap,
                  onHover: (value) => setState(() => _hovered = value),
                  onHighlightChanged: (value) =>
                      setState(() => _pressed = value),
                  splashColor: const Color(0x44bea6ff),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _Artwork extends StatelessWidget {
  const _Artwork({required this.media});
  final MediaSnapshot media;
  @override
  Widget build(BuildContext context) => media.artwork == null
      ? const CustomPaint(painter: _RecordPainter())
      : Image.memory(
          media.artwork!,
          gaplessPlayback: true,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder: (_, _, _) =>
              const CustomPaint(painter: _RecordPainter()),
        );
}

class _RecordPainter extends CustomPainter {
  const _RecordPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xff8070a9), Color(0xff33283f), Color(0xff171d29)],
        ).createShader(rect),
    );
    final center = Offset(size.width * .5, size.height * .5);
    final radius = size.shortestSide * .41;
    canvas.drawCircle(center, radius, Paint()..color = const Color(0xff14131a));
    for (final scale in [.82, .69, .56]) {
      canvas.drawCircle(
        center,
        radius * scale,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .55
          ..color = const Color(0xff393142),
      );
    }
    canvas.drawCircle(center, radius * .29, Paint()..color = _accent);
    canvas.drawCircle(
      center,
      radius * .055,
      Paint()..color = const Color(0xff211b2c),
    );
  }

  @override
  bool shouldRepaint(covariant _RecordPainter oldDelegate) => false;
}

class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.color, this.size = 5});
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// Decorative playback indicator, isolated from the rest of the panel's paint.
class _Waveform extends StatefulWidget {
  const _Waveform({required this.playing});
  final bool playing;
  @override
  State<_Waveform> createState() => _WaveformState();
}

class _WaveformState extends State<_Waveform>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 950),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _Waveform oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.playing && !MediaQuery.disableAnimationsOf(context)) {
      if (!_animation.isAnimating) _animation.repeat();
    } else {
      _animation.stop();
    }
  }

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    child: AnimatedBuilder(
      animation: _animation,
      builder: (_, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: List.generate(
          4,
          (i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 1),
            width: 2,
            height: widget.playing
                ? 4 +
                      8 *
                          (.5 +
                              .5 * math.sin(_animation.value * math.pi * 2 + i))
                : 3,
            decoration: BoxDecoration(
              color: widget.playing ? _mint : _muted,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    ),
  );
}
