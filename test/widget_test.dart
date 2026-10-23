import 'dart:ui' show PointerDeviceKind;
import 'dart:ui' as ui;
import 'dart:io';
import 'package:dynamic_island/island_controller.dart';
import 'package:dynamic_island/main.dart';
import 'package:dynamic_island/services/local_store.dart';
import 'package:dynamic_island/services/media_service.dart';
import 'package:dynamic_island/services/window_region.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingRegion extends WindowRegion {
  RecordingRegion() : super(0);
  Rect? bounds;
  double? radius;
  @override
  void update(Rect bounds, double radius, double dpr) {
    this.bounds = bounds;
    this.radius = radius;
  }
}

class FakePlayer extends MediaService {
  final commands = <String>[];
  bool playing = true;
  @override
  Future<MediaSnapshot> read() async => MediaSnapshot(
    title: 'Midnight City',
    artist: 'M83',
    playing: playing,
    canPlay: true,
    canPause: true,
    canNext: true,
    canPrevious: true,
  );
  @override
  Future<void> command(String action) async {
    commands.add(action);
    if (action == 'pause') playing = false;
    if (action == 'play') playing = true;
  }
}

void main() {
  testWidgets('centered album controls music and focus presets start timers', (
    tester,
  ) async {
    const renderPreview = bool.fromEnvironment('NOX_UI_PREVIEW');
    if (renderPreview) {
      await tester.runAsync(() async {
        final font = await File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytes();
        await (FontLoader(
          'Segoe UI',
        )..addFont(Future.value(ByteData.sublistView(font)))).load();
        await (FontLoader(
          'MaterialIcons',
        )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      });
    }
    tester.view.physicalSize = const Size(600, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = (await tester.runAsync(() => LocalStore.openAt(':memory:')))!;
    final player = FakePlayer();
    final controller = IslandController(store, player)
      ..media = await player.read()
      ..selectTab(IslandTab.media);
    final preview = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: preview,
        child: IslandApp(controller: controller, region: RecordingRegion()),
      ),
    );
    await tester.pumpAndSettle();
    final album = find.byKey(const ValueKey('album-control'));
    final previous = find.byKey(const ValueKey('media-previous'));
    final next = find.byKey(const ValueKey('media-next'));
    final navigation = find.byKey(const ValueKey('navigation-rail'));
    expect(find.byKey(const ValueKey('nox-brand')), findsNothing);
    expect(find.text('Media'), findsNothing);
    expect(find.text('Timer'), findsNothing);
    expect(find.text('Jadwal'), findsNothing);
    final navMedia = tester.getCenter(find.byKey(const ValueKey('nav-media')));
    final navTimer = tester.getCenter(find.byKey(const ValueKey('nav-timer')));
    expect(navMedia.dy, navTimer.dy);
    expect(navMedia.dx, lessThan(navTimer.dx));
    final actions = find.byKey(const ValueKey('window-actions'));
    expect(
      tester.getTopLeft(actions).dx,
      greaterThan(tester.getBottomRight(navigation).dx),
    );
    expect(
      tester.getBottomRight(actions).dy,
      lessThan(tester.getTopLeft(album).dy),
    );
    expect(tester.getSize(album).width, 46);
    expect(tester.getSize(previous).width, 38);
    expect(tester.getCenter(album).dx, closeTo(300, .1));
    expect(tester.getCenter(previous).dx, lessThan(tester.getCenter(album).dx));
    expect(tester.getCenter(next).dx, greaterThan(tester.getCenter(album).dx));
    expect(
      tester.getBottomLeft(find.byKey(const ValueKey('media-title'))).dy,
      lessThan(tester.getTopLeft(album).dy),
    );

    Future<void> capture(String name) async {
      if (!renderPreview) return;
      final boundary =
          preview.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('.tools/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    }

    await tester.runAsync(() => capture('nox-media-preview'));
    for (final action in ['pause', 'play', 'previous', 'next']) {
      await tester.tap(
        action == 'previous'
            ? previous
            : action == 'next'
            ? next
            : album,
      );
      await tester.pumpAndSettle();
      expect(player.commands.last, action);
    }
    await tester.tap(find.byKey(const ValueKey('nav-timer')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => capture('nox-timer-preview'));
    await tester.tap(find.text('15 m'));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();
    expect(controller.remaining.inSeconds, inInclusiveRange(899, 900));
    expect(find.text('Akhiri'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byKey(const ValueKey('nav-reminders')));
    await tester.pumpAndSettle();
    await tester.runAsync(() => capture('nox-schedule-preview'));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    await tester.runAsync(store.close);
  });

  testWidgets(
    'shell and native region follow idle, media and expansion geometry',
    (tester) async {
      tester.view.physicalSize = const Size(600, 200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = await tester.runAsync(() => LocalStore.openAt(':memory:'));
      final controller = IslandController(store!, MediaService());
      final region = RecordingRegion();
      await tester.pumpWidget(
        IslandApp(controller: controller, region: region),
      );
      await tester.pump();
      expect(region.bounds!.size, const Size(200, 30));
      expect(region.bounds!.left, 200);
      expect(region.radius, 15);

      controller.hover(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(region.bounds!.size, const Size(400, 150));
      controller.hover(false);
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pumpAndSettle();
      expect(region.bounds!.size, const Size(200, 30));

      controller.media = const MediaSnapshot(title: 'Track', artist: 'Artist');
      controller.clearError();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(region.bounds!.width, greaterThan(200));
      expect(region.bounds!.width, lessThan(405));
      await tester.pumpAndSettle();
      expect(region.bounds!.size, const Size(400, 30));

      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(20, 190));
      await mouse.moveTo(const Offset(300, 20));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));
      expect(region.bounds!.height, greaterThan(30));
      expect(region.bounds!.height, lessThan(150));
      expect(region.radius, greaterThan(15));
      expect(region.radius, lessThan(24.1));
      await tester.pumpAndSettle();
      expect(region.bounds!.size, const Size(400, 150));
      expect(find.text('Artist'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('nav-reminders')));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(2));
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      await tester.runAsync(store.close);
    },
  );
}
