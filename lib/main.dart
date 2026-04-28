import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/library_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  runApp(const RSVPApp());
}

class RSVPApp extends StatelessWidget {
  const RSVPApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RSVP Reader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: const ColorScheme.dark(primary: Color(0xFF00b4d8), surface: Color(0xFF1a1a2e)),
        scaffoldBackgroundColor: const Color(0xFF0d0d1a),
        appBarTheme: const AppBarTheme(backgroundColor: Color(0xFF1a1a2e), foregroundColor: Colors.white),
      ),
      home: const LibraryScreen(),
    );
  }
}
