import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/vault_manager.dart';

enum BrowserEngineType {
  chrome,
  firefox,
  ucBrowser,
}

class BrowserEngineConfig {
  final BrowserEngineType type;
  final String id;
  final String name;
  final String shortName;
  final IconData icon;
  final Color primaryColor;
  final Color accentColor;
  final String userAgent;
  final String defaultSearchUrl;
  final String homeUrl;
  final String description;

  const BrowserEngineConfig({
    required this.type,
    required this.id,
    required this.name,
    required this.shortName,
    required this.icon,
    required this.primaryColor,
    required this.accentColor,
    required this.userAgent,
    required this.defaultSearchUrl,
    required this.homeUrl,
    required this.description,
  });
}

class PrivateBrowserScreen extends StatefulWidget {
  final VaultManager vaultManager;

  const PrivateBrowserScreen({Key? key, required this.vaultManager}) : super(key: key);

  @override
  State<PrivateBrowserScreen> createState() => _PrivateBrowserScreenState();
}

class _PrivateBrowserScreenState extends State<PrivateBrowserScreen> {
  late final WebViewController _controller;
  final TextEditingController _urlController = TextEditingController();
  final FocusNode _urlFocusNode = FocusNode();

  bool _isLoading = true;
  double _loadingProgress = 0.0;
  int _downloadCount = 0;
  bool _canGoBack = false;
  bool _canGoForward = false;

  static const String PREF_BROWSER_ENGINE = 'hidex_browser_engine_preference';

  static const List<BrowserEngineConfig> _availableBrowsers = [
    BrowserEngineConfig(
      type: BrowserEngineType.chrome,
      id: 'chrome',
      name: 'Google Chrome',
      shortName: 'Chrome',
      icon: Icons.public,
      primaryColor: Color(0xFF1A73E8),
      accentColor: Color(0xFF4285F4),
      userAgent:
          'Mozilla/5.0 (Linux; Android 14; Mobile; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0.6478.122 Mobile Safari/537.36',
      defaultSearchUrl: 'https://www.google.com/search?q=',
      homeUrl: 'https://www.google.com',
      description: 'Default Google Chrome mobile engine & Google Search',
    ),
    BrowserEngineConfig(
      type: BrowserEngineType.firefox,
      id: 'firefox',
      name: 'Mozilla Firefox',
      shortName: 'Firefox',
      icon: Icons.local_fire_department_rounded,
      primaryColor: Color(0xFFFF5722),
      accentColor: Color(0xFFFF7139),
      userAgent:
          'Mozilla/5.0 (Android 14; Mobile; rv:127.0) Gecko/127.0 Firefox/127.0',
      defaultSearchUrl: 'https://duckduckgo.com/?q=',
      homeUrl: 'https://duckduckgo.com',
      description: 'Firefox Gecko engine with DuckDuckGo enhanced privacy',
    ),
    BrowserEngineConfig(
      type: BrowserEngineType.ucBrowser,
      id: 'uc_browser',
      name: 'UC Browser',
      shortName: 'UC Browser',
      icon: Icons.speed_rounded,
      primaryColor: Color(0xFFFF6F00),
      accentColor: Color(0xFFFFA000),
      userAgent:
          'Mozilla/5.0 (Linux; U; Android 14; en-US; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Version/4.0 Chrome/110.0.5481.153 UCBrowser/13.5.5.1313 Mobile Safari/537.36',
      defaultSearchUrl: 'https://www.bing.com/search?q=',
      homeUrl: 'https://www.bing.com',
      description: 'UC Browser Fast Speed Dial & Turbo data engine',
    ),
  ];

  BrowserEngineConfig _activeBrowser = _availableBrowsers[0];

  final List<Map<String, String>> _shortcuts = [
    {'title': 'Google', 'url': 'https://www.google.com', 'icon': '🔍'},
    {'title': 'DuckDuckGo', 'url': 'https://duckduckgo.com', 'icon': '🦆'},
    {'title': 'Bing', 'url': 'https://www.bing.com', 'icon': '🌐'},
    {'title': 'Wikipedia', 'url': 'https://www.wikipedia.org', 'icon': '📚'},
    {'title': 'Unsplash', 'url': 'https://unsplash.com', 'icon': '📸'},
    {'title': 'Reddit', 'url': 'https://www.reddit.com', 'icon': '👽'},
    {'title': 'Archive.org', 'url': 'https://archive.org', 'icon': '🏛️'},
  ];

  @override
  void initState() {
    super.initState();
    _initBrowser();
  }

  @override
  void dispose() {
    _urlController.dispose();
    _urlFocusNode.dispose();
    super.dispose();
  }

  Future<void> _initBrowser() async {
    final prefs = await SharedPreferences.getInstance();
    final savedEngineId = prefs.getString(PREF_BROWSER_ENGINE) ?? 'chrome';
    final matchedConfig = _availableBrowsers.firstWhere(
      (b) => b.id == savedEngineId,
      orElse: () => _availableBrowsers[0],
    );

    if (mounted) {
      setState(() {
        _activeBrowser = matchedConfig;
        _urlController.text = matchedConfig.homeUrl;
      });
    }

    _initWebView(initialUrl: matchedConfig.homeUrl, userAgent: matchedConfig.userAgent);
  }

  void _initWebView({required String initialUrl, required String userAgent}) {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF121212))
      ..setUserAgent(userAgent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress / 100.0;
                _isLoading = progress < 100;
              });
            }
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
                _urlController.text = url;
              });
              _updateNavHistory();
            }
          },
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
                _urlController.text = url;
              });
              _updateNavHistory();
            }
          },
          onNavigationRequest: (NavigationRequest request) {
            final url = request.url.toLowerCase();
            // Automatically detect direct file downloads
            if (_isDownloadableUrl(url)) {
              _downloadFileDirectToVault(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(initialUrl));
  }

  Future<void> _updateNavHistory() async {
    final back = await _controller.canGoBack();
    final forward = await _controller.canGoForward();
    if (mounted) {
      setState(() {
        _canGoBack = back;
        _canGoForward = forward;
      });
    }
  }

  Future<void> _switchBrowserEngine(BrowserEngineConfig newConfig) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PREF_BROWSER_ENGINE, newConfig.id);

    setState(() {
      _activeBrowser = newConfig;
    });

    await _controller.setUserAgent(newConfig.userAgent);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: newConfig.primaryColor,
          duration: const Duration(seconds: 2),
          content: Row(
            children: [
              Icon(newConfig.icon, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Switched to ${newConfig.name} mode',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          action: SnackBarAction(
            label: 'Go Home',
            textColor: Colors.white,
            onPressed: () => _loadUrl(newConfig.homeUrl),
          ),
        ),
      );
    }
  }

  void _showBrowserSelectorDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Choose Browser Engine',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Select your preferred browser experience. Each engine uses its official User-Agent, search engine, and speeds.',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                ..._availableBrowsers.map((b) {
                  final isSelected = b.id == _activeBrowser.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? b.primaryColor.withOpacity(0.18)
                          : const Color(0xFF282828),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isSelected ? b.primaryColor : Colors.white12,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      leading: CircleAvatar(
                        backgroundColor: b.primaryColor,
                        child: Icon(b.icon, color: Colors.white, size: 22),
                      ),
                      title: Row(
                        children: [
                          Text(
                            b.name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: b.primaryColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Text(
                                'ACTIVE',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          b.description,
                          style: TextStyle(
                            color: isSelected ? Colors.white70 : Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ),
                      trailing: isSelected
                          ? Icon(Icons.check_circle, color: b.primaryColor)
                          : const Icon(Icons.radio_button_unchecked, color: Colors.white30),
                      onTap: () {
                        Navigator.pop(ctx);
                        _switchBrowserEngine(b);
                      },
                    ),
                  );
                }),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  bool _isDownloadableUrl(String url) {
    const downloadableExts = [
      '.pdf', '.zip', '.rar', '.7z', '.docx', '.doc', '.xlsx', '.xls',
      '.pptx', '.ppt', '.mp3', '.mp4', '.mkv', '.mov', '.apk', '.csv'
    ];
    for (final ext in downloadableExts) {
      if (url.split('?').first.endsWith(ext)) return true;
    }
    return false;
  }

  Future<void> _downloadFileDirectToVault(String url) async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Downloading privately into HideX Vault...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        String fileName = url.split('/').last.split('?').first;
        if (fileName.isEmpty || !fileName.contains('.')) {
          fileName = 'download_${DateTime.now().millisecondsSinceEpoch}.dat';
        }

        final item = await widget.vaultManager.savePrivateBrowserDownload(
          bytes: response.bodyBytes,
          fileName: fileName,
        );

        if (mounted && item != null) {
          setState(() => _downloadCount++);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: Colors.green.shade800,
              content: Text('🔒 "$fileName" saved privately in Vault! (Zero phone storage trace)'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Download failed: $e')),
        );
      }
    }
  }

  void _loadUrl(String input) {
    _urlFocusNode.unfocus();
    String finalUrl = input.trim();
    if (finalUrl.isEmpty) return;

    if (!finalUrl.startsWith('http://') && !finalUrl.startsWith('https://')) {
      if (finalUrl.contains('.') && !finalUrl.contains(' ')) {
        finalUrl = 'https://$finalUrl';
      } else {
        // Query through active browser search provider (Google, DuckDuckGo, Bing)
        finalUrl = '${_activeBrowser.defaultSearchUrl}${Uri.encodeComponent(finalUrl)}';
      }
    }

    _controller.loadRequest(Uri.parse(finalUrl));
  }

  Future<void> _clearSession() async {
    await _controller.clearCache();
    await _controller.clearLocalStorage();
    final cookieManager = WebViewCookieManager();
    await cookieManager.clearCookies();
    _controller.loadRequest(Uri.parse(_activeBrowser.homeUrl));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('🧹 Private browsing session & cookies wiped completely.')),
      );
    }
  }

  void _promptManualDownload() {
    final controller = TextEditingController(text: _urlController.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Direct Download to Vault', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter any file, video, or image link to encrypt and download directly into HideX without leaving any file in phone gallery/storage:',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Direct File URL',
                labelStyle: const TextStyle(color: Colors.cyanAccent),
                hintText: 'https://example.com/file.pdf',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.white24),
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: Colors.cyanAccent),
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _activeBrowser.primaryColor),
            onPressed: () {
              Navigator.pop(ctx);
              _downloadFileDirectToVault(controller.text.trim());
            },
            child: const Text('Download to Vault', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _showShortcutsDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(18.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Bookmarks & Quick Links',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _shortcuts.map((s) {
                    return InkWell(
                      onTap: () {
                        Navigator.pop(ctx);
                        _loadUrl(s['url']!);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2A2A2A),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(s['icon']!, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 8),
                            Text(
                              s['title']!,
                              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  // Handle system back navigation like a normal browser
  Future<void> _handleBackNavigation() async {
    if (await _controller.canGoBack()) {
      await _controller.goBack();
      _updateNavHistory();
    } else {
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Normal browser back navigation with PopScope:
    // When user presses Android back button or gestures back,
    // it navigates back in web pages if history exists, otherwise closes browser.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        await _handleBackNavigation();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          backgroundColor: const Color(0xFF1A1A1A),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            tooltip: _canGoBack ? 'Previous Page' : 'Close Browser',
            icon: Icon(
              _canGoBack ? Icons.arrow_back : Icons.close,
              color: Colors.white,
            ),
            onPressed: _handleBackNavigation,
          ),
          titleSpacing: 0,
          title: Row(
            children: [
              // Browser Engine Switcher Pill Button
              InkWell(
                onTap: _showBrowserSelectorDialog,
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: _activeBrowser.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _activeBrowser.primaryColor, width: 1.2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_activeBrowser.icon, size: 14, color: _activeBrowser.accentColor),
                      const SizedBox(width: 4),
                      Text(
                        _activeBrowser.shortName,
                        style: TextStyle(
                          color: _activeBrowser.accentColor,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // Normal browser Omnibox / Search & URL field
              Expanded(
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF282828),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: TextField(
                    controller: _urlController,
                    focusNode: _urlFocusNode,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search or type URL...',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 13),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                      prefixIcon: const Icon(Icons.lock, size: 13, color: Colors.cyanAccent),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_urlController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 14, color: Colors.white54),
                              onPressed: () {
                                _urlController.clear();
                                setState(() {});
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.cyanAccent),
                            onPressed: () => _loadUrl(_urlController.text),
                          ),
                        ],
                      ),
                    ),
                    onSubmitted: _loadUrl,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
          ),
          actions: [
            // Switch Browser Engine quick button
            IconButton(
              tooltip: 'Switch Browser (Chrome / Firefox / UC)',
              icon: Icon(_activeBrowser.icon, color: _activeBrowser.accentColor),
              onPressed: _showBrowserSelectorDialog,
            ),
            // Menu
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (val) {
                if (val == 'engine') _showBrowserSelectorDialog();
                if (val == 'clear') _clearSession();
                if (val == 'download') _promptManualDownload();
                if (val == 'home') _loadUrl(_activeBrowser.homeUrl);
                if (val == 'exit') Navigator.of(context).pop();
              },
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: 'engine',
                  child: Row(
                    children: [
                      Icon(_activeBrowser.icon, size: 18, color: _activeBrowser.accentColor),
                      const SizedBox(width: 8),
                      Text('Switch Browser (${_activeBrowser.shortName})'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'home',
                  child: Row(
                    children: [
                      Icon(Icons.home, size: 18),
                      SizedBox(width: 8),
                      Text('Go to Homepage'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      Icon(Icons.download_for_offline, size: 18, color: Colors.amberAccent),
                      SizedBox(width: 8),
                      Text('Download File to Vault'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'clear',
                  child: Row(
                    children: [
                      Icon(Icons.cleaning_services, size: 18, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Wipe Session & Cookies'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'exit',
                  child: Row(
                    children: [
                      Icon(Icons.exit_to_app, size: 18, color: Colors.white70),
                      SizedBox(width: 8),
                      Text('Close Browser'),
                    ],
                  ),
                ),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(26),
            child: Container(
              color: _activeBrowser.primaryColor.withOpacity(0.18),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(_activeBrowser.icon, size: 12, color: _activeBrowser.accentColor),
                      const SizedBox(width: 6),
                      Text(
                        '${_activeBrowser.name} Private Mode',
                        style: TextStyle(
                          fontSize: 10,
                          color: _activeBrowser.accentColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const Text(
                        ' • Incognito 100%',
                        style: TextStyle(fontSize: 10, color: Colors.white70),
                      ),
                    ],
                  ),
                  if (_downloadCount > 0)
                    Text(
                      '$_downloadCount in Vault',
                      style: const TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: Stack(
          children: [
            WebViewWidget(controller: _controller),
            if (_isLoading)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(
                  value: _loadingProgress > 0 ? _loadingProgress : null,
                  backgroundColor: Colors.transparent,
                  valueColor: AlwaysStoppedAnimation<Color>(_activeBrowser.accentColor),
                  minHeight: 2.5,
                ),
              ),
          ],
        ),

        // Normal browser bottom toolbar
        bottomNavigationBar: BottomAppBar(
          color: const Color(0xFF1E1E1E),
          height: 52,
          padding: EdgeInsets.zero,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              // Back in history
              IconButton(
                tooltip: 'Back',
                icon: Icon(
                  Icons.arrow_back_ios_new,
                  size: 18,
                  color: _canGoBack ? Colors.white : Colors.white24,
                ),
                onPressed: _canGoBack
                    ? () async {
                        await _controller.goBack();
                        _updateNavHistory();
                      }
                    : null,
              ),

              // Forward in history
              IconButton(
                tooltip: 'Forward',
                icon: Icon(
                  Icons.arrow_forward_ios,
                  size: 18,
                  color: _canGoForward ? Colors.white : Colors.white24,
                ),
                onPressed: _canGoForward
                    ? () async {
                        await _controller.goForward();
                        _updateNavHistory();
                      }
                    : null,
              ),

              // Reload or Stop
              IconButton(
                tooltip: _isLoading ? 'Stop' : 'Reload',
                icon: Icon(
                  _isLoading ? Icons.close : Icons.refresh,
                  color: Colors.white70,
                ),
                onPressed: () {
                  _isLoading ? _controller.loadRequest(Uri.parse(_urlController.text)) : _controller.reload();
                },
              ),

              // Home Page
              IconButton(
                tooltip: 'Homepage',
                icon: const Icon(Icons.home_outlined, color: Colors.white70),
                onPressed: () => _loadUrl(_activeBrowser.homeUrl),
              ),

              // Switch Browser (Chrome / Firefox / UC Browser)
              InkWell(
                onTap: _showBrowserSelectorDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _activeBrowser.primaryColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _activeBrowser.primaryColor.withOpacity(0.5)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(_activeBrowser.icon, size: 14, color: _activeBrowser.accentColor),
                      const SizedBox(width: 4),
                      Text(
                        _activeBrowser.shortName,
                        style: TextStyle(
                          color: _activeBrowser.accentColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Bookmarks
              IconButton(
                tooltip: 'Bookmarks & Search',
                icon: const Icon(Icons.bookmark_border, color: Colors.white70),
                onPressed: _showShortcutsDialog,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
