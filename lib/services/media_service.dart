import 'package:flutter/services.dart';

class MediaSnapshot {
  const MediaSnapshot({
    this.title = '',
    this.artist = '',
    this.artwork,
    this.playing = false,
    this.canPlay = false,
    this.canPause = false,
    this.canNext = false,
    this.canPrevious = false,
  });
  final String title;
  final String artist;
  final Uint8List? artwork;
  final bool playing, canPlay, canPause, canNext, canPrevious;
  bool get available => title.isNotEmpty || artist.isNotEmpty;

  factory MediaSnapshot.fromMap(Map<Object?, Object?> map) => MediaSnapshot(
    title: map['title'] as String? ?? '',
    artist: map['artist'] as String? ?? '',
    artwork: map['artwork'] as Uint8List?,
    playing: map['playing'] == true,
    canPlay: map['canPlay'] == true,
    canPause: map['canPause'] == true,
    canNext: map['canNext'] == true,
    canPrevious: map['canPrevious'] == true,
  );
}

class MediaService {
  static const channel = MethodChannel('dev.notch/windows');

  Future<MediaSnapshot> read() async {
    final result = await channel.invokeMapMethod<Object?, Object?>(
      'mediaSnapshot',
    );
    return MediaSnapshot.fromMap(result ?? {});
  }

  Future<void> command(String action) async {
    final accepted = await channel.invokeMethod<bool>('mediaCommand', action);
    if (accepted != true) throw StateError('Pemutar menolak perintah $action.');
  }
}
