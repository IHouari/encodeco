import 'dart:io';
import 'package:flutter/material.dart';
import 'package:device_preview/device_preview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'security/app_lock.dart' as lock_screen;
import 'screens/encrypt_decrypt_screen.dart' as main_screen;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getString('output_directory') == null) {
    Directory? dir;
    if (Platform.isAndroid) {
      dir = Directory('/storage/emulated/0/Download/encdec');
    } else if (Platform.isIOS) {
      dir = await getApplicationDocumentsDirectory();
      dir = Directory('${dir.path}/encdec');
    } else if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
      dir = await getDownloadsDirectory();
      if (dir != null) {
        dir = Directory('${dir.path}/encdec');
      }
    }
    if (dir != null && !await dir.exists()) {
      await dir.create(recursive: true);
    }
    if (dir != null) {
      await prefs.setString('output_directory', dir.path);
    }
  }

  runApp(
    DevicePreview(
      enabled: !const bool.fromEnvironment('dart.vm.product'),
      builder: (_) => const MyApp(),
    ),
  );
}

final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _isUnlocked = false;

  void _unlock() {
    setState(() {
      _isUnlocked = true;
    });
  }
@override
Widget build(BuildContext context) {
  return MaterialApp(
    // Removed useInheritedMediaQuery
    locale: DevicePreview.locale(context),
    builder: DevicePreview.appBuilder,
    debugShowCheckedModeBanner: false,
    scaffoldMessengerKey: scaffoldMessengerKey,
    title: 'EncDec AES-256-GCM',
    theme: ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF121212),
      primaryColor: const Color(0xFF1F1F1F),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFFBB86FC),
        secondary: Color(0xFF03DAC6),
        surface: Color(0xFF1E1E1E), // use this instead of background
        error: Colors.redAccent,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1F1F1F),
        elevation: 2,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1E1E1E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFF333333)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(
              color: Color.fromARGB(255, 252, 134, 134)),
        ),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFFBB86FC),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
    ),
    home: _isUnlocked
        ? const main_screen.EncryptDecryptScreen()
        : lock_screen.AppLockScreen(onUnlocked: _unlock),
  );
}
  }
