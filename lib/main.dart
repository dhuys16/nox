import 'dart:io';
import 'package:flutter/material.dart';
import 'package:smtc_windows/smtc_windows.dart';
import 'package:window_manager/window_manager.dart';
import 'island_controller.dart';
import 'island_view.dart';
import 'services/local_store.dart';
import 'services/media_service.dart';
import 'services/window_region.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!Platform.isWindows) {
    throw UnsupportedError('Aplikasi ini khusus Windows 11.');
  }
  await windowManager.ensureInitialized();
  // Initialize the publisher runtime without creating a fake media session.
  // Other applications are discovered and controlled by the GSMTC bridge.
  try {
    await SMTCWindows.initialize();
  } catch (e) {
    debugPrint('SMTC publisher unavailable: $e');
  }
  final store = await LocalStore.open();
  final controller = IslandController(store, MediaService());
  await controller.initialize();
  final hwnd = await MediaService.channel.invokeMethod<int>('windowHandle');
  if (hwnd == null || hwnd == 0) throw StateError('HWND tidak tersedia.');
  final region = WindowRegion(hwnd);
  const options = WindowOptions(
    size: Size(600, 200),
    minimumSize: Size(600, 200),
    maximumSize: Size(600, 200),
    backgroundColor: Colors.transparent,
    titleBarStyle: TitleBarStyle.hidden,
    skipTaskbar: true,
    title: 'Nox Panel',
  );
  await windowManager.waitUntilReadyToShow(options);
  // waitUntilReadyToShow accepts a VoidCallback, which would not await an async
  // callback. Keep this sequence explicitly awaited before runApp/show.
  Future<void> configureWindow() async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);
    await windowManager.setResizable(false);
    await windowManager.setMaximizable(false);
    await windowManager.setMinimizable(false);
    await windowManager.setHasShadow(false);
    await windowManager.setAlwaysOnTop(true);
    await windowManager.setSkipTaskbar(true);
    await windowManager.setAlignment(Alignment.topCenter);
    final dpr =
        WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    region.update(const Rect.fromLTWH(200, 8, 200, 30), 15, dpr);
  }

  await configureWindow();
  runApp(IslandApp(controller: controller, region: region));
  WidgetsBinding.instance.addPostFrameCallback(
    (_) => windowManager.show(inactive: true),
  );
}

class IslandApp extends StatelessWidget {
  const IslandApp({super.key, required this.controller, required this.region});
  final IslandController controller;
  final WindowRegion region;
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xffbea6ff),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: 'Segoe UI',
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        filled: true,
        fillColor: const Color(0xff211e2b),
        hintStyle: const TextStyle(color: Color(0xff8d899c), fontSize: 11),
        suffixStyle: const TextStyle(color: Color(0xff8d899c), fontSize: 10),
        prefixIconColor: const Color(0xffa49bb9),
        prefixIconConstraints: const BoxConstraints(
          minWidth: 32,
          minHeight: 32,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(11),
          borderSide: const BorderSide(color: Color(0xffbea6ff), width: .8),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size(28, 28),
          padding: const EdgeInsets.all(2),
          iconSize: 18,
        ),
      ),
    ),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: child!,
    ),
    home: IslandView(controller: controller, region: region),
  );
}
