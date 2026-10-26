import 'package:flutter/material.dart';
import '../../services/app_icon_service.dart';

class AppIconScreen extends StatefulWidget {
  const AppIconScreen({Key? key}) : super(key: key);

  @override
  State<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends State<AppIconScreen> {
  String _activeDisguise = 'CalendarAlias';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadCurrentDisguise();
  }

  Future<void> _loadCurrentDisguise() async {
    final active = await AppIconService.getActiveDisguise();
    setState(() {
      _activeDisguise = active;
      _isLoading = false;
    });
  }

  Future<void> _selectDisguise(AppDisguise disguise) async {
    setState(() => _isLoading = true);
    await AppIconService.setDisguise(disguise.alias);
    setState(() {
      _activeDisguise = disguise.alias;
      _isLoading = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.indigo,
          content: Text('🎭 Home screen disguise updated to "${disguise.name}"!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: const Text('Home Screen App Disguise', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.indigoAccent))
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.indigo.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.indigo.withOpacity(0.3)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.masks, color: Colors.indigoAccent, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Choose an icon disguise for your phone\'s home screen. The app will appear as a harmless utility app to anyone looking at your phone.',
                            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Available Disguises', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: AppIconService.availableDisguises.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final disguise = AppIconService.availableDisguises[index];
                        final isSelected = _activeDisguise == disguise.alias;

                        return InkWell(
                          onTap: () => _selectDisguise(disguise),
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.indigo.withOpacity(0.2) : const Color(0xFF1E1E1E),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected ? Colors.indigoAccent : Colors.white10,
                                width: isSelected ? 1.8 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 50,
                                  height: 50,
                                  decoration: BoxDecoration(
                                    color: disguise.color.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: disguise.color.withOpacity(0.5)),
                                  ),
                                  child: Icon(disguise.icon, color: disguise.color, size: 26),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        disguise.name,
                                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        disguise.subtitle,
                                        style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12),
                                      ),
                                    ],
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, color: Colors.indigoAccent, size: 24)
                                else
                                  const Icon(Icons.radio_button_unchecked, color: Colors.white24, size: 24),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
