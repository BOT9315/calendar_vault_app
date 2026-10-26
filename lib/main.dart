import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/theme_service.dart';
import 'views/calendar/calendar_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize saved theme mode (Light or Dark)
  await ThemeService.instance.init();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );

  runApp(const CalendarVaultApp());
}

class CalendarVaultApp extends StatelessWidget {
  const CalendarVaultApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeService.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'Calendar Hidex App',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeService.instance.themeMode,
          // Clean Light Theme
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.light,
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Colors.white,
              foregroundColor: Colors.black87,
            ),
            scaffoldBackgroundColor: Colors.white,
            cardColor: Colors.grey.shade100,
          ),
          // Sleek Dark Theme
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo,
              brightness: Brightness.dark,
            ),
            appBarTheme: const AppBarTheme(
              centerTitle: false,
              elevation: 0,
              backgroundColor: Color(0xFF1E1E1E),
              foregroundColor: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFF121212),
            cardColor: const Color(0xFF1E1E1E),
          ),
          home: const CalendarScreen(),
        );
      },
    );
  }
}
