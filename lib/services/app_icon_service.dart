import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppDisguise {
  final String alias;
  final String name;
  final String subtitle;
  final IconData icon;
  final Color color;

  const AppDisguise({
    required this.alias,
    required this.name,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}

class AppIconService {
  static const MethodChannel _channel = MethodChannel('com.ankushkumar.calendarvault/app_icon');
  static const String PREF_DISGUISE_KEY = 'active_app_disguise';

  static const List<AppDisguise> availableDisguises = [
    AppDisguise(
      alias: 'CalendarAlias',
      name: 'Calendar Hidex',
      subtitle: 'Disguised as standard calendar & event planner',
      icon: Icons.calendar_month,
      color: Colors.indigo,
    ),
    AppDisguise(
      alias: 'CalculatorAlias',
      name: 'Calculator',
      subtitle: 'Disguised as a standard scientific calculator',
      icon: Icons.calculate,
      color: Colors.teal,
    ),
    AppDisguise(
      alias: 'NotesAlias',
      name: 'Quick Notes',
      subtitle: 'Disguised as a personal notebook & memo app',
      icon: Icons.edit_note,
      color: Colors.amber,
    ),
    AppDisguise(
      alias: 'ClockAlias',
      name: 'Clock & Timer',
      subtitle: 'Disguised as a clock and alarm app',
      icon: Icons.access_time_filled,
      color: Colors.blue,
    ),
    AppDisguise(
      alias: 'WeatherAlias',
      name: 'Weather',
      subtitle: 'Disguised as local weather forecast app',
      icon: Icons.wb_sunny,
      color: Colors.deepOrange,
    ),
  ];

  /// Get currently active disguise alias
  static Future<String> getActiveDisguise() async {
    try {
      final String? result = await _channel.invokeMethod('getCurrentIcon');
      if (result != null && result.isNotEmpty) {
        return result;
      }
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(PREF_DISGUISE_KEY) ?? 'CalendarAlias';
  }

  /// Change the home screen app icon disguise (only from inside HideX)
  static Future<bool> setDisguise(String alias) async {
    try {
      final bool? success = await _channel.invokeMethod('changeIcon', {'alias': alias});
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PREF_DISGUISE_KEY, alias);
      return success ?? true;
    } catch (e) {
      debugPrint('AppIconService: Native channel not active on this platform ($e), saved preference.');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(PREF_DISGUISE_KEY, alias);
      return true;
    }
  }
}
