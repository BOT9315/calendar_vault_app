import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/calendar_event.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/cloud_backup_service.dart';
import '../../services/persistent_storage_service.dart';
import '../../services/sequence_detector_service.dart';
import '../../services/theme_service.dart';
import '../vault/vault_home_screen.dart';
import 'add_event_dialog.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _currentMonth = DateTime.now();
  DateTime _selectedDate = DateTime.now();
  final List<CalendarEvent> _events = [];
  late SequenceDetectorService _sequenceDetector;

  // Default secret sequence if none set yet: e.g. dates 7 -> 14 -> 21 -> 28
  List<int> _secretSequence = [7, 14, 21, 28];
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _initDetector();
    _loadSettingsAndEvents();
  }

  void _initDetector() {
    _sequenceDetector = SequenceDetectorService(
      targetSequence: _secretSequence,
      onMatched: _unlockVault,
      onCandidateCheck: (candidate) async {
        final restored = await AuthService.restoreVaultWithPassword(candidate);
        if (restored) {
          if (mounted) {
            setState(() {
              _secretSequence = List.from(candidate);
            });
          }
          return true;
        }
        return false;
      },
    );
  }

  Future<void> _loadSettingsAndEvents() async {
    // Request storage permissions on Android to ensure persistent vault mirror directory access
    await PersistentStorageService.requestStoragePermissions();

    final prefs = await SharedPreferences.getInstance();

    // Check biometric unlock setting
    _biometricEnabled = await BiometricService.isBiometricEnabled();

    // Check if an existing persistent vault survived reinstallation
    final hasPendingRecovery = await AuthService.hasExistingVaultPendingRecovery();

    // Load permanently saved password sequence from AuthService (FlutterSecureStorage & SharedPreferences)
    final activeSeq = await AuthService.getPasswordSequence();
    if (mounted) {
      setState(() {
        _secretSequence = List.from(activeSeq);
      });
      _sequenceDetector.updateTargetSequence(_secretSequence);
    }

    final hasSeenGuide = prefs.getBool('has_seen_onboarding_guide') ?? false;

    if (hasPendingRecovery) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showExistingVaultRecoveredDialog();
      });
    } else if (!hasSeenGuide) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showFirstTimeGuide();
      });
    }

    // Load decoy events
    final savedEvents = prefs.getString('decoy_events');
    if (savedEvents != null) {
      final List<dynamic> list = jsonDecode(savedEvents);
      setState(() {
        _events.clear();
        _events.addAll(list.map((e) => CalendarEvent.fromJson(e as Map<String, dynamic>)));
      });
    } else {
      // Add a couple of realistic default events so the decoy looks authentic
      final today = DateTime.now();
      setState(() {
        _events.add(CalendarEvent(
          id: '1',
          title: 'Dentist Appointment',
          description: 'Routine checkup and cleaning',
          date: today,
          time: '10:30 AM',
        ));
        _events.add(CalendarEvent(
          id: '2',
          title: 'Grocery Shopping',
          description: 'Vegetables, milk, fruits',
          date: today,
          time: '06:00 PM',
        ));
      });
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = jsonEncode(_events.map((e) => e.toJson()).toList());
    await prefs.setString('decoy_events', jsonStr);
  }

  void _unlockVault() async {
    final currentStored = await AuthService.getPasswordSequence();
    if (!mounted) return;

    if (currentStored.isEmpty) {
      _showExistingVaultRecoveredDialog();
      return;
    }

    setState(() {
      _secretSequence = List.from(currentStored);
    });

    final secretKey = _secretSequence.join('-');
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VaultHomeScreen(
          secretKey: secretKey,
          secretSequence: _secretSequence,
          onSequenceChanged: (newSeq) async {
            await AuthService.setPasswordSequence(newSeq);
            if (mounted) {
              setState(() {
                _secretSequence = List.from(newSeq);
              });
              _sequenceDetector.updateTargetSequence(newSeq);
            }
          },
        ),
      ),
    );

    // Refresh biometric settings
    final bio = await BiometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricEnabled = bio;
      });
    }
  }

  Future<void> _tryBiometricUnlock() async {
    final authenticated = await BiometricService.authenticate(
      reason: 'Scan fingerprint or face to open HideX Vault',
      errorCallback: (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(msg),
              backgroundColor: Colors.redAccent,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
    );
    if (authenticated && mounted) {
      _unlockVault();
    }
  }

  void _showExistingVaultRecoveredDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = ThemeService.instance.isDarkMode;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: const Row(
            children: [
              Icon(Icons.shield_moon_rounded, color: Colors.greenAccent, size: 26),
              SizedBox(width: 10),
              Expanded(
                child: Text('Restore Existing Vault', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HideX detected your existing encrypted vault from your previous installation.\n\n'
                  'Your private photos, videos, albums, and documents are safe and preserved on this device.',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black87,
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.greenAccent.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.greenAccent.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.lock_open_rounded, color: Colors.greenAccent, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Enter your original 4-date password to recover and decrypt your vault immediately.',
                          style: TextStyle(color: Colors.greenAccent, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ElevatedButton.icon(
                  icon: const Icon(Icons.key, size: 18),
                  label: const Text('Unlock Existing Vault'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.indigo,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showManualSequenceRestoreDialog();
                  },
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.cloud_download_outlined, size: 18),
                  label: const Text('Restore from Cloud Backup'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark ? Colors.cyanAccent : Colors.indigo,
                    side: BorderSide(color: isDark ? Colors.cyanAccent : Colors.indigo),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _showCloudRestoreDialog();
                  },
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('has_seen_onboarding_guide', true);
                    if (mounted) Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tip: Tap your 4 secret dates directly on the calendar grid anytime to unlock.'),
                        duration: Duration(seconds: 4),
                      ),
                    );
                  },
                  child: Text('Tap Dates on Calendar Grid', style: TextStyle(color: isDark ? Colors.white60 : Colors.black54)),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  void _showManualSequenceRestoreDialog() {
    final controller = TextEditingController();
    String? errorMessage;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = ThemeService.instance.isDarkMode;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            title: const Text('Enter Vault Password', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter your 4 secret dates (e.g. 7-14-21-28 or separated by space):',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.text,
                  autofocus: true,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black87, fontSize: 16, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    hintText: 'e.g. 7-14-21-28',
                    hintStyle: const TextStyle(color: Colors.grey),
                    errorText: errorMessage,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                onPressed: () async {
                  final input = controller.text.trim();
                  final parts = input
                      .split(RegExp(r'[\s\-,\.]+'))
                      .where((s) => s.isNotEmpty)
                      .map((s) => int.tryParse(s))
                      .where((n) => n != null)
                      .map((n) => n!)
                      .toList();

                  if (parts.length != 4) {
                    setDialogState(() {
                      errorMessage = 'Please enter exactly 4 valid dates.';
                    });
                    return;
                  }

                  final success = await AuthService.restoreVaultWithPassword(parts);
                  if (success) {
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setBool('has_seen_onboarding_guide', true);
                    if (mounted) {
                      Navigator.pop(ctx);
                      setState(() {
                        _secretSequence = List.from(parts);
                      });
                      _sequenceDetector.updateTargetSequence(parts);
                      _unlockVault();
                    }
                  } else {
                    setDialogState(() {
                      errorMessage = 'Incorrect password. Does not match existing vault.';
                    });
                  }
                },
                child: const Text('Unlock'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCloudRestoreDialog() async {
    final savedConfig = await CloudBackupService.loadConfig();
    final urlController = TextEditingController(text: savedConfig?.serverUrl ?? '');
    final tokenController = TextEditingController(text: savedConfig?.authToken ?? '');
    final passwordController = TextEditingController();

    bool isRestoring = false;
    String status = '';

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isDark = ThemeService.instance.isDarkMode;
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            title: const Row(
              children: [
                Icon(Icons.cloud_download, color: Colors.cyanAccent),
                SizedBox(width: 8),
                Text('Cloud Restore', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: urlController,
                    enabled: !isRestoring,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Cloud Server URL',
                      hintText: 'https://cloud.example.com/vault.hidexenc',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: tokenController,
                    enabled: !isRestoring,
                    obscureText: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Bearer Auth Token (Optional)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: passwordController,
                    enabled: !isRestoring,
                    obscureText: true,
                    style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                    decoration: const InputDecoration(
                      labelText: 'Vault Password / Sequence',
                      hintText: 'e.g. 7-14-21-28',
                    ),
                  ),
                  if (status.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Text(status, style: const TextStyle(fontSize: 12, color: Colors.cyanAccent)),
                  ],
                  if (isRestoring) ...[
                    const SizedBox(height: 12),
                    const LinearProgressIndicator(),
                  ],
                ],
              ),
            ),
            actions: [
              if (!isRestoring)
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              if (!isRestoring)
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: () async {
                    final url = urlController.text.trim();
                    final token = tokenController.text.trim();
                    final pwd = passwordController.text.trim();

                    if (url.isEmpty || pwd.isEmpty) {
                      setDialogState(() {
                        status = 'Please provide Cloud URL and Vault Password.';
                      });
                      return;
                    }

                    setDialogState(() {
                      isRestoring = true;
                      status = 'Downloading encrypted package...';
                    });

                    final result = await CloudBackupService.restoreVaultFromCloud(
                      serverUrl: url,
                      authToken: token,
                      secretKey: pwd,
                      onProgress: (p, msg) {
                        setDialogState(() {
                          status = msg;
                        });
                      },
                    );

                    if (result.isSuccess) {
                      // Parse sequence if entered as numbers
                      final parts = pwd
                          .split(RegExp(r'[\s\-,\.]+'))
                          .where((s) => s.isNotEmpty)
                          .map((s) => int.tryParse(s))
                          .where((n) => n != null)
                          .map((n) => n!)
                          .toList();

                      if (parts.length == 4) {
                        await AuthService.setPasswordSequence(parts);
                        if (mounted) {
                          setState(() {
                            _secretSequence = List.from(parts);
                          });
                          _sequenceDetector.updateTargetSequence(parts);
                        }
                      }

                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('has_seen_onboarding_guide', true);

                      if (mounted) {
                        Navigator.pop(ctx);
                        _unlockVault();
                      }
                    } else {
                      setDialogState(() {
                        isRestoring = false;
                        status = 'Failed: ${result.message}';
                      });
                    }
                  },
                  child: const Text('Restore Now'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _onDayTapped(int day) {
    setState(() {
      _selectedDate = DateTime(_currentMonth.year, _currentMonth.month, day);
    });

    // Pass the tapped day number to the secret detector
    _sequenceDetector.onDateTapped(day);
  }

  void _showFirstTimeGuide() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final isDark = ThemeService.instance.isDarkMode;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.auto_awesome, color: Colors.indigoAccent, size: 22),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Welcome to HideX App',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This looks like a standard Calendar app with event management, but it conceals a military-grade private vault.',
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white70 : Colors.black87,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 14),

                // Access instructions card
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.indigo.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.indigoAccent.withOpacity(0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.key, color: Colors.indigoAccent, size: 18),
                          SizedBox(width: 8),
                          Text(
                            'How to Unlock Hidden Vault:',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.indigoAccent),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text.rich(
                        TextSpan(
                          text: 'Tap these 4 dates consecutively on the calendar grid:\n',
                          style: TextStyle(fontSize: 12, color: isDark ? Colors.white70 : Colors.black87, height: 1.4),
                          children: const [
                            TextSpan(
                              text: '7  ➔  14  ➔  21  ➔  28',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.indigoAccent),
                            ),
                            TextSpan(
                              text: '\n(Default combination. You can customize this anytime inside the vault!)',
                              style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 14),
                const Text(
                  '✨ Key HideX Features:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),

                _buildGuideFeatureItem(
                  icon: Icons.snippet_folder,
                  iconColor: Colors.teal,
                  title: 'Store Any File Type',
                  desc: 'Encrypt PDF, Word docs, Excel sheets, audio, photos, videos, and archives with AES-256.',
                  isDark: isDark,
                ),
                _buildGuideFeatureItem(
                  icon: Icons.language,
                  iconColor: Colors.cyanAccent,
                  title: 'Private Browser & Downloads',
                  desc: 'Browse incognito. Downloaded files save directly inside the vault without appearing in phone downloads.',
                  isDark: isDark,
                ),
                _buildGuideFeatureItem(
                  icon: Icons.password,
                  iconColor: Colors.amber,
                  title: 'Protected Password Change',
                  desc: 'Password can ONLY be changed from inside the vault after verifying your current password.',
                  isDark: isDark,
                ),
                _buildGuideFeatureItem(
                  icon: Icons.masks,
                  iconColor: Colors.purpleAccent,
                  title: 'Multiple App Disguise Icons',
                  desc: 'Switch launcher icons (Calculator, Notes, Clock, Weather) directly from HideX settings.',
                  isDark: isDark,
                ),
                _buildGuideFeatureItem(
                  icon: Icons.shield,
                  iconColor: Colors.green,
                  title: 'Reinstall Protection',
                  desc: 'Encrypted files are saved to persistent storage and survive app uninstallation.',
                  isDark: isDark,
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                await prefs.setBool('has_seen_onboarding_guide', true);
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Got it! Start Using App', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildGuideFeatureItem({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: iconColor, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                Text(desc, style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showAboutDeveloperDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isDark = ThemeService.instance.isDarkMode;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              backgroundColor: isDark ? const Color(0xFF18181B) : Colors.white,
              title: Row(
                children: [
                  Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 22),
                  const SizedBox(width: 8),
                  const Text('About This App', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Bot Robot Logo provided by Ankush Kumar
                    Container(
                      width: 110,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.6), width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.blueAccent.withOpacity(0.25),
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        'assets/logo.png',
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Calendar-Hidex-App',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Privacy-focused calendar with a secure, hidden vault.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black87),
                    ),
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.blueAccent.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.blueAccent.withOpacity(0.3)),
                      ),
                      child: const Text.rich(
                        TextSpan(
                          text: 'Designed and developed by ',
                          style: TextStyle(fontSize: 13, color: Colors.blueAccent),
                          children: [
                            TextSpan(
                              text: 'Ankush Kumar',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    Text(
                      '© 2026 Ankush Kumar\nVersion 1.0.0',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12, color: isDark ? Colors.white38 : Colors.grey.shade600, height: 1.5),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Close'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateUtils.getDaysInMonth(_currentMonth.year, _currentMonth.month);
    final firstDayOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final startingWeekday = firstDayOfMonth.weekday % 7; // 0 for Sunday

    final selectedDayEvents = _events.where((e) =>
      e.date.year == _selectedDate.year &&
      e.date.month == _selectedDate.month &&
      e.date.day == _selectedDate.day
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month, color: Colors.indigo),
            const SizedBox(width: 8),
            Text(
              '${_getMonthName(_currentMonth.month)} ${_currentMonth.year}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ],
        ),
        actions: [
          // Light / Dark Mode Toggle
          IconButton(
            tooltip: ThemeService.instance.isDarkMode ? 'Switch to Light Mode' : 'Switch to Dark Mode',
            icon: Icon(ThemeService.instance.isDarkMode ? Icons.light_mode : Icons.dark_mode),
            onPressed: () => ThemeService.instance.toggleTheme(),
          ),
          IconButton(
            tooltip: 'Previous Month',
            icon: const Icon(Icons.chevron_left),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
            },
          ),
          IconButton(
            tooltip: 'Next Month',
            icon: const Icon(Icons.chevron_right),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
              });
            },
          ),
          // 3-Dots Menu for Discreet About & Guide
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (val) {
              if (val == 'about') {
                _showAboutDeveloperDialog();
              } else if (val == 'today') {
                setState(() {
                  _currentMonth = DateTime.now();
                  _selectedDate = DateTime.now();
                });
              } else if (val == 'guide') {
                _showFirstTimeGuide();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'today',
                child: Row(
                  children: [
                    Icon(Icons.today, size: 20),
                    SizedBox(width: 8),
                    Text('Today'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'guide',
                child: Row(
                  children: [
                    Icon(Icons.help_outline, size: 20),
                    SizedBox(width: 8),
                    Text('How to Use / Guide'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 20),
                    SizedBox(width: 8),
                    Text('App Info & Creator'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
        children: [
          // Days of week header (Sun, Mon, Tue, etc.)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: const [
                Text('Sun', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text('Mon', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text('Tue', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text('Wed', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text('Thu', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text('Fri', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                Text('Sat', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          const Divider(height: 1),

          // Calendar Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
                childAspectRatio: 1.1,
              ),
              itemCount: startingWeekday + daysInMonth,
              itemBuilder: (context, index) {
                if (index < startingWeekday) {
                  return const SizedBox.shrink();
                }
                final day = index - startingWeekday + 1;
                final isToday = DateTime.now().year == _currentMonth.year &&
                    DateTime.now().month == _currentMonth.month &&
                    DateTime.now().day == day;
                final isSelected = _selectedDate.year == _currentMonth.year &&
                    _selectedDate.month == _currentMonth.month &&
                    _selectedDate.day == day;

                final hasEvents = _events.any((e) =>
                    e.date.year == _currentMonth.year &&
                    e.date.month == _currentMonth.month &&
                    e.date.day == day);

                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => _onDayTapped(day),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : (isToday
                              ? (ThemeService.instance.isDarkMode ? Colors.indigo.shade900.withOpacity(0.5) : Colors.indigo.shade50)
                              : Colors.transparent),
                      borderRadius: BorderRadius.circular(12),
                      border: isToday
                          ? Border.all(color: Colors.indigoAccent, width: 1.5)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: (isSelected || isToday) ? FontWeight.bold : FontWeight.normal,
                            color: isSelected
                                ? Colors.white
                                : (isToday
                                    ? Colors.indigoAccent
                                    : (ThemeService.instance.isDarkMode ? Colors.white70 : Colors.black87)),
                          ),
                        ),
                        if (hasEvents)
                          Container(
                            margin: const EdgeInsets.only(top: 2),
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isSelected ? Colors.white : Colors.indigoAccent,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),

          // Events header for selected day
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: ThemeService.instance.isDarkMode ? const Color(0xFF1E1E1E) : Colors.grey.shade100,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Events for ${_selectedDate.day} ${_getMonthName(_selectedDate.month)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_biometricEnabled)
                      IconButton(
                        tooltip: 'Biometric Unlock',
                        icon: const Icon(Icons.fingerprint, color: Colors.indigo),
                        onPressed: _tryBiometricUnlock,
                      ),
                    TextButton.icon(
                      onPressed: () async {
                        final newEvent = await showDialog<CalendarEvent>(
                          context: context,
                          builder: (_) => AddEventDialog(selectedDate: _selectedDate),
                        );
                        if (newEvent != null) {
                          setState(() => _events.add(newEvent));
                          _saveEvents();
                        }
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Event'),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Events List
          if (selectedDayEvents.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24.0),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'No events planned for this day.',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                    if (_biometricEnabled) ...[
                      const SizedBox(height: 12),
                      IconButton(
                        tooltip: 'Biometric Unlock',
                        icon: const Icon(Icons.fingerprint, color: Colors.indigo, size: 28),
                        onPressed: _tryBiometricUnlock,
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: selectedDayEvents.length,
              itemBuilder: (context, index) {
                final event = selectedDayEvents[index];
                return ListTile(
                  leading: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _tryBiometricUnlock,
                    child: CircleAvatar(
                      backgroundColor: Colors.indigo.shade100,
                      child: Icon(
                        _biometricEnabled ? Icons.fingerprint : Icons.event_note,
                        color: Colors.indigo,
                        size: 20,
                      ),
                    ),
                  ),
                  title: Text(event.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('${event.time} • ${event.description}'),
                  trailing: IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20, color: Colors.grey),
                    onPressed: () {
                      setState(() => _events.remove(event));
                      _saveEvents();
                    },
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}

  String _getMonthName(int month) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[month - 1];
  }
}
