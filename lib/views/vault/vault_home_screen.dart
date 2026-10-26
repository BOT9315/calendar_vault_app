import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../models/vault_item.dart';
import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/vault_manager.dart';
import '../gallery/album_detail_screen.dart';
import '../widgets/media_grid_item.dart';
import 'app_icon_screen.dart';
import 'backup_restore_screen.dart';
import 'import_confirmation_dialog.dart';
import 'photo_viewer_screen.dart';
import 'private_browser_screen.dart';
import 'sequence_setup_screen.dart';
import 'video_player_screen.dart';

enum GalleryFilter { photos, videos, albums, favorites, recent }
enum SortOrder { newest, oldest, name, size }

class VaultHomeScreen extends StatefulWidget {
  final String secretKey;
  final List<int> secretSequence;
  final Function(List<int>)? onSequenceChanged;

  const VaultHomeScreen({
    Key? key,
    required this.secretKey,
    required this.secretSequence,
    this.onSequenceChanged,
  }) : super(key: key);

  @override
  State<VaultHomeScreen> createState() => _VaultHomeScreenState();
}

class _VaultHomeScreenState extends State<VaultHomeScreen> with SingleTickerProviderStateMixin {
  late VaultManager _vaultManager;
  late TabController _mainTabController;
  final ImagePicker _picker = ImagePicker();
  late List<int> _activeSequence;

  // Gallery Sub-Filter & Search
  GalleryFilter _galleryFilter = GalleryFilter.photos;
  SortOrder _sortOrder = SortOrder.newest;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  // Multi-select state
  bool _isSelectionMode = false;
  final Set<String> _selectedItemIds = {};

  // Biometrics
  bool _biometricEnabled = false;
  bool _canUseBiometrics = false;

  @override
  void initState() {
    super.initState();
    _activeSequence = List.from(widget.secretSequence);
    _mainTabController = TabController(length: 4, vsync: this);
    _vaultManager = VaultManager(secretKey: widget.secretKey);
    _vaultManager.initialize();
    _checkBiometrics();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _vaultManager.cleanupTempFiles();
    _mainTabController.dispose();
    super.dispose();
  }

  Future<void> _checkBiometrics() async {
    final available = await BiometricService.isBiometricAvailable();
    final enabled = await BiometricService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _canUseBiometrics = available;
        _biometricEnabled = enabled;
      });
    }
  }

  void _panicExit() {
    _vaultManager.cleanupTempFiles();
    Navigator.of(context).pop();
  }

  // ================= IMPORT WORKFLOW =================

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Add to Secret Vault',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 14),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.indigo,
                    child: Icon(Icons.photo_library, color: Colors.white),
                  ),
                  title: const Text('Import Photos & Videos', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Encrypt media from phone gallery', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickFromGallery();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.teal,
                    child: Icon(Icons.snippet_folder, color: Colors.white),
                  ),
                  title: const Text('Import Documents & Files', style: TextStyle(color: Colors.white)),
                  subtitle: Text('PDF, Word, Excel, Audio, Archives', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAnyFiles();
                  },
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: Colors.deepOrange,
                    child: Icon(Icons.camera_alt, color: Colors.white),
                  ),
                  title: const Text('Take Private Photo / Video', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Directly into encrypted vault', style: TextStyle(color: Colors.white.withOpacity(0.6))),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showCameraChoice();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickFromGallery() async {
    final List<XFile> picked = await _picker.pickMultipleMedia();
    if (picked.isEmpty) return;
    _handleImportWorkflow(picked.map((x) => File(x.path)).toList());
  }

  Future<void> _pickAnyFiles() async {
    final pickedFiles = await FilePicker.pickFiles(
      type: FileType.any,
    );
    if (pickedFiles.isEmpty) return;
    final files = pickedFiles.where((p) => p.path != null).map((p) => File(p.path!)).toList();
    _handleImportWorkflow(files);
  }

  Future<void> _handleImportWorkflow(List<File> files) async {
    // Show confirmation dialog with Option A and Option B
    final deleteOriginals = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => ImportConfirmationDialog(files: files),
    );

    if (deleteOriginals == null) return; // User cancelled

    final result = await _vaultManager.importMediaFilesWithVerification(
      files: files,
      deleteOriginals: deleteOriginals,
    );

    if (mounted) {
      if (deleteOriginals && result.verification.allVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            content: Text(
              '🔒 ${result.totalImported} file(s) encrypted into vault & ${result.deletedOriginalsCount} phone original(s) safely removed!',
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.indigo,
            content: Text('🔒 ${result.totalImported} file(s) encrypted and stored in HideX Vault!'),
          ),
        );
      }
    }
  }

  void _showCameraChoice() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Capture Secret Media', style: TextStyle(color: Colors.white)),
        children: [
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _captureMedia(isVideo: false);
            },
            child: const Row(
              children: [
                Icon(Icons.photo_camera, color: Colors.blueAccent),
                SizedBox(width: 12),
                Text('Take Private Photo', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () {
              Navigator.pop(ctx);
              _captureMedia(isVideo: true);
            },
            child: const Row(
              children: [
                Icon(Icons.videocam, color: Colors.purpleAccent),
                SizedBox(width: 12),
                Text('Record Private Video', style: TextStyle(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _captureMedia({required bool isVideo}) async {
    final XFile? captured = isVideo
        ? await _picker.pickVideo(source: ImageSource.camera)
        : await _picker.pickImage(source: ImageSource.camera);

    if (captured == null) return;

    final result = await _vaultManager.importMediaFilesWithVerification(
      files: [File(captured.path)],
      deleteOriginals: true,
    );

    if (mounted && result.totalImported > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.indigo,
          content: Text(isVideo ? 'Private video captured & encrypted in vault!' : 'Private photo captured & encrypted in vault!'),
        ),
      );
    }
  }

  // ================= ALBUM CREATION =================

  Future<void> _createNewAlbumDialog() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Create New Album', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Album Name (e.g. Vacation, Documents)',
            hintStyle: TextStyle(color: Colors.white30),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.indigoAccent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      await _vaultManager.createAlbum(name);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Album "$name" created!')),
        );
      }
    }
  }

  // ================= PROFILE AVATAR =================

  Future<void> _pickAndSetProfileAvatar() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, maxWidth: 400, maxHeight: 400);
    if (image == null) return;

    final bytes = await image.readAsBytes();
    await _vaultManager.setProfileAvatar(bytes);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile picture updated and encrypted in vault!')),
      );
    }
  }

  // ================= MULTI-SELECT ACTIONS =================

  void _toggleSelect(VaultItem item) {
    setState(() {
      if (_selectedItemIds.contains(item.id)) {
        _selectedItemIds.remove(item.id);
        if (_selectedItemIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedItemIds.add(item.id);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll(List<VaultItem> items) {
    setState(() {
      if (_selectedItemIds.length == items.length) {
        _selectedItemIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedItemIds.addAll(items.map((e) => e.id));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _deleteSelectedItems(List<VaultItem> allFiltered) async {
    final selected = allFiltered.where((e) => _selectedItemIds.contains(e.id)).toList();
    if (selected.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Selected Items?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Permanently delete ${selected.length} item(s) from your secret vault?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final count = await _vaultManager.deleteMultipleItems(selected);
      setState(() {
        _selectedItemIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted $count item(s) permanently.')),
        );
      }
    }
  }

  Future<void> _moveSelectedToAlbum(List<VaultItem> allFiltered) async {
    final selected = allFiltered.where((e) => _selectedItemIds.contains(e.id)).toList();
    if (selected.isEmpty) return;

    final albums = _vaultManager.albums;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No albums created yet. Please create an album first.')),
      );
      return;
    }

    final chosenAlbumId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Move to Album', style: TextStyle(color: Colors.white)),
        children: [
          ...albums.map(
            (a) => SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, a.id),
              child: Row(
                children: [
                  const Icon(Icons.photo_album, color: Colors.indigoAccent),
                  const SizedBox(width: 10),
                  Text(a.name, style: const TextStyle(color: Colors.white)),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    if (chosenAlbumId != null) {
      await _vaultManager.moveMultipleItemsToAlbum(selected, chosenAlbumId);
      setState(() {
        _selectedItemIds.clear();
        _isSelectionMode = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Moved ${selected.length} item(s) to album.')),
        );
      }
    }
  }

  Future<void> _exportSelected(List<VaultItem> allFiltered) async {
    final selected = allFiltered.where((e) => _selectedItemIds.contains(e.id)).toList();
    if (selected.isEmpty) return;

    const defaultExportDir = '/storage/emulated/0/Download';
    final count = await _vaultManager.exportMultipleItems(selected, defaultExportDir);
    setState(() {
      _selectedItemIds.clear();
      _isSelectionMode = false;
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Exported $count item(s) to phone Downloads folder!')),
      );
    }
  }

  // ================= NAVIGATION =================

  void _openDetails(VaultItem item) {
    if (_isSelectionMode) {
      _toggleSelect(item);
      return;
    }

    if (item.type == VaultMediaType.photo) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PhotoViewerScreen(
            item: item,
            vaultManager: _vaultManager,
          ),
        ),
      ).then((_) => setState(() {}));
    } else if (item.type == VaultMediaType.video) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            item: item,
            vaultManager: _vaultManager,
          ),
        ),
      ).then((_) => setState(() {}));
    } else {
      _showGenericFileOptions(item);
    }
  }

  void _showGenericFileOptions(VaultItem item) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(item.icon, color: item.color, size: 30),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.originalName, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16), maxLines: 1, overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Text('${item.type.name.toUpperCase()} • ${_formatBytes(item.fileSizeBytes)}', style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.open_in_new, color: Colors.blueAccent),
                  title: const Text('Open / View File Securely', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Decrypts to temporary memory to view', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  onTap: () async {
                    Navigator.pop(ctx);
                    await _vaultManager.openVaultItem(item);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.file_download, color: Colors.greenAccent),
                  title: const Text('Export / Save to Phone Storage', style: TextStyle(color: Colors.white)),
                  subtitle: Text('Decrypts back to public Downloads folder', style: TextStyle(color: Colors.white.withOpacity(0.5))),
                  onTap: () async {
                    Navigator.pop(ctx);
                    final success = await _vaultManager.exportItemToPublicStorage(item, '/storage/emulated/0/Download');
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(success ? 'Exported to phone Downloads folder!' : 'Failed to export.')),
                      );
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.redAccent),
                  title: const Text('Delete Permanently', style: TextStyle(color: Colors.redAccent)),
                  onTap: () {
                    Navigator.pop(ctx);
                    _confirmAndDeleteItem(item);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmAndDeleteItem(VaultItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Permanently?', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: Text(
          'Are you sure you want to permanently delete "${item.originalName}"?\n\n'
          'This file will be completely erased from device storage, secondary backup mirrors, and cloud sync.',
          style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _vaultManager.deleteItem(item);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent.shade700,
            content: Text('Permanently deleted "${item.originalName}"'),
          ),
        );
      }
    }
  }

  void _openPrivateBrowser() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PrivateBrowserScreen(vaultManager: _vaultManager),
      ),
    );
  }

  void _openAppIconDisguise() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const AppIconScreen(),
      ),
    );
  }

  void _openBackupRestoreScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BackupRestoreScreen(vaultManager: _vaultManager),
      ),
    ).then((_) => setState(() {}));
  }

  Future<void> _changeVaultPassword() async {
    final newSeq = await Navigator.push<List<int>>(
      context,
      MaterialPageRoute(
        builder: (_) => SequenceSetupScreen(currentSequence: _activeSequence),
      ),
    );

    if (newSeq != null && newSeq.isNotEmpty) {
      setState(() {
        _activeSequence = List.from(newSeq);
      });
      await _vaultManager.updateSecretKey(newSeq.join('-'));
      if (widget.onSequenceChanged != null) {
        widget.onSequenceChanged!(newSeq);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('✅ Secret vault combination updated successfully!'),
          ),
        );
      }
    }
  }

  void _showAboutDeveloperDialog() {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          backgroundColor: const Color(0xFF1E1E1E),
          title: const Row(
            children: [
              Icon(Icons.shield_outlined, color: Colors.blueAccent, size: 22),
              SizedBox(width: 8),
              Text('About This App', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(20),
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
                const SizedBox(height: 14),
                const Text(
                  'Calendar-Hidex-App',
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Privacy-focused calendar with a secure, hidden vault.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5, color: Colors.white70),
                ),
                const SizedBox(height: 12),
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
                      style: TextStyle(fontSize: 12, color: Colors.blueAccent),
                      children: [
                        TextSpan(
                          text: 'Ankush Kumar',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, color: Colors.white12),
                const SizedBox(height: 10),
                const Text(
                  '© 2026 Ankush Kumar\nVersion 1.0.0',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.5),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Colors.cyanAccent)),
            ),
          ],
        );
      },
    );
  }

  // ================= FILTER & SORT LOGIC =================

  List<VaultItem> _getFilteredItems() {
    List<VaultItem> list;
    switch (_galleryFilter) {
      case GalleryFilter.photos:
        list = _vaultManager.photos;
        break;
      case GalleryFilter.videos:
        list = _vaultManager.videos;
        break;
      case GalleryFilter.favorites:
        list = _vaultManager.favorites;
        break;
      case GalleryFilter.recent:
        list = _vaultManager.recentlyAdded;
        break;
      case GalleryFilter.albums:
        list = [];
        break;
    }

    if (_searchQuery.isNotEmpty) {
      list = list.where((e) => e.originalName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();
    }

    // Apply sorting
    final sorted = List<VaultItem>.from(list);
    switch (_sortOrder) {
      case SortOrder.newest:
        sorted.sort((a, b) => b.dateAdded.compareTo(a.dateAdded));
        break;
      case SortOrder.oldest:
        sorted.sort((a, b) => a.dateAdded.compareTo(b.dateAdded));
        break;
      case SortOrder.name:
        sorted.sort((a, b) => a.originalName.toLowerCase().compareTo(b.originalName.toLowerCase()));
        break;
      case SortOrder.size:
        sorted.sort((a, b) => b.fileSizeBytes.compareTo(a.fileSizeBytes));
        break;
    }

    return sorted;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  // ================= BUILD UI =================

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _vaultManager,
      builder: (context, _) {
        final totalBytes = _vaultManager.getTotalStorageBytes();
        final photoBytes = _vaultManager.getStorageBytesForType(VaultMediaType.photo);
        final videoBytes = _vaultManager.getStorageBytesForType(VaultMediaType.video);
        final docBytes = _vaultManager.getStorageBytesForType(VaultMediaType.document);
        final audioBytes = _vaultManager.getStorageBytesForType(VaultMediaType.audio);

        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E1E1E),
            foregroundColor: Colors.white,
            elevation: 0,
            leading: GestureDetector(
              onTap: _pickAndSetProfileAvatar,
              child: Padding(
                padding: const EdgeInsets.all(8.0),
                child: CircleAvatar(
                  backgroundColor: Colors.indigoAccent,
                  backgroundImage: _vaultManager.profileAvatarBytes != null
                      ? MemoryImage(_vaultManager.profileAvatarBytes!)
                      : null,
                  child: _vaultManager.profileAvatarBytes == null
                      ? const Icon(Icons.person, color: Colors.white, size: 20)
                      : null,
                ),
              ),
            ),
            title: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('HideX Vault', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                Text('AES-256 Protected', style: TextStyle(fontSize: 10, color: Colors.greenAccent)),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Backup & Recovery',
                icon: const Icon(Icons.cloud_sync_outlined, color: Colors.cyanAccent),
                onPressed: _openBackupRestoreScreen,
              ),
              IconButton(
                tooltip: 'Panic Lock (Exit Immediately)',
                icon: const Icon(Icons.lock, color: Colors.amber),
                onPressed: _panicExit,
              ),
            ],
            bottom: TabBar(
              controller: _mainTabController,
              indicatorColor: Colors.cyanAccent,
              labelColor: Colors.cyanAccent,
              unselectedLabelColor: Colors.white60,
              tabs: const [
                Tab(icon: Icon(Icons.photo_library_outlined, size: 20), text: 'Gallery'),
                Tab(icon: Icon(Icons.folder_outlined, size: 20), text: 'Documents'),
                Tab(icon: Icon(Icons.public, size: 20), text: 'Browser'),
                Tab(icon: Icon(Icons.tune, size: 20), text: 'Settings'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _mainTabController,
            children: [
              _buildGalleryTab(),
              _buildDocumentsTab(),
              _buildBrowserTab(),
              _buildSettingsTab(totalBytes, photoBytes, videoBytes, docBytes, audioBytes),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            backgroundColor: Colors.indigo,
            foregroundColor: Colors.white,
            onPressed: _showImportOptions,
            icon: const Icon(Icons.add),
            label: const Text('Add to Vault', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        );
      },
    );
  }

  // ================= TAB 1: GALLERY =================

  Widget _buildGalleryTab() {
    final filteredItems = _getFilteredItems();

    return Column(
      children: [
        // Sub-filter pills (Photos, Videos, Albums, Favorites, Recent)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          color: const Color(0xFF181818),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _buildFilterChip(GalleryFilter.photos, 'Photos (${_vaultManager.photos.length})', Icons.image),
                const SizedBox(width: 6),
                _buildFilterChip(GalleryFilter.videos, 'Videos (${_vaultManager.videos.length})', Icons.videocam),
                const SizedBox(width: 6),
                _buildFilterChip(GalleryFilter.albums, 'Albums (${_vaultManager.albums.length})', Icons.photo_album),
                const SizedBox(width: 6),
                _buildFilterChip(GalleryFilter.favorites, 'Favorites (${_vaultManager.favorites.length})', Icons.favorite),
                const SizedBox(width: 6),
                _buildFilterChip(GalleryFilter.recent, 'Recent (${_vaultManager.recentlyAdded.length})', Icons.schedule),
              ],
            ),
          ),
        ),

        // Search & Sort bar (if not Albums tab)
        if (_galleryFilter != GalleryFilter.albums)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF222222),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search files...',
                        hintStyle: const TextStyle(color: Colors.white30, fontSize: 13),
                        prefixIcon: const Icon(Icons.search, size: 18, color: Colors.white38),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16, color: Colors.white38),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<SortOrder>(
                  icon: const Icon(Icons.sort, color: Colors.cyanAccent),
                  tooltip: 'Sort by',
                  onSelected: (order) => setState(() => _sortOrder = order),
                  itemBuilder: (ctx) => [
                    const PopupMenuItem(value: SortOrder.newest, child: Text('Newest First')),
                    const PopupMenuItem(value: SortOrder.oldest, child: Text('Oldest First')),
                    const PopupMenuItem(value: SortOrder.name, child: Text('Name (A-Z)')),
                    const PopupMenuItem(value: SortOrder.size, child: Text('Size (Largest)')),
                  ],
                ),
              ],
            ),
          ),

        // Multi-select action bar
        if (_isSelectionMode && _galleryFilter != GalleryFilter.albums)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            color: Colors.indigo.shade900.withOpacity(0.5),
            child: Row(
              children: [
                Text(
                  '${_selectedItemIds.length} Selected',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Select All',
                  icon: const Icon(Icons.select_all, size: 20, color: Colors.white),
                  onPressed: () => _selectAll(filteredItems),
                ),
                IconButton(
                  tooltip: 'Move to Album',
                  icon: const Icon(Icons.drive_file_move_outlined, size: 20, color: Colors.amberAccent),
                  onPressed: () => _moveSelectedToAlbum(filteredItems),
                ),
                IconButton(
                  tooltip: 'Export to Phone',
                  icon: const Icon(Icons.file_download_outlined, size: 20, color: Colors.greenAccent),
                  onPressed: () => _exportSelected(filteredItems),
                ),
                IconButton(
                  tooltip: 'Delete Permanently',
                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.redAccent),
                  onPressed: () => _deleteSelectedItems(filteredItems),
                ),
              ],
            ),
          ),

        // Main content (Albums grid OR Items grid)
        Expanded(
          child: _vaultManager.isLoading
              ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
              : _galleryFilter == GalleryFilter.albums
                  ? _buildAlbumsView()
                  : _buildMediaGrid(filteredItems),
        ),
      ],
    );
  }

  Widget _buildFilterChip(GalleryFilter filter, String label, IconData icon) {
    final isSelected = _galleryFilter == filter;
    return GestureDetector(
      onTap: () {
        setState(() {
          _galleryFilter = filter;
          _selectedItemIds.clear();
          _isSelectionMode = false;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.indigoAccent : Colors.white.withOpacity(0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? Colors.indigoAccent : Colors.white12,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.white70),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlbumsView() {
    final albums = _vaultManager.albums;

    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.1,
        ),
        itemCount: albums.length + 1, // +1 for "Create Album" card
        itemBuilder: (context, index) {
          if (index == 0) {
            // "Create Album" card
            return InkWell(
              onTap: _createNewAlbumDialog,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.indigoAccent.withOpacity(0.4), style: BorderStyle.solid),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      backgroundColor: Colors.indigoAccent,
                      radius: 24,
                      child: Icon(Icons.add, color: Colors.white, size: 26),
                    ),
                    SizedBox(height: 10),
                    Text('New Album', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
              ),
            );
          }

          final album = albums[index - 1];
          final albumItems = _vaultManager.getItemsForAlbum(album.id);

          return InkWell(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AlbumDetailScreen(
                    album: album,
                    vaultManager: _vaultManager,
                  ),
                ),
              ).then((_) => setState(() {}));
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.photo_album, size: 44, color: Colors.indigoAccent),
                  const SizedBox(height: 8),
                  Text(
                    album.name,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${albumItems.length} item(s)',
                    style: const TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaGrid(List<VaultItem> items) {
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.shield_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 12),
            const Text(
              'No Media In This View',
              style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Tap "+ Add to Vault" to import photos and videos.',
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.95,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          final isSelected = _selectedItemIds.contains(item.id);

          return MediaGridItem(
            item: item,
            vaultManager: _vaultManager,
            isSelected: isSelected,
            isSelectionMode: _isSelectionMode,
            onTap: () => _openDetails(item),
            onLongPress: () {
              if (!_isSelectionMode) {
                _toggleSelect(item);
              }
            },
          );
        },
      ),
    );
  }

  // ================= TAB 2: DOCUMENTS =================

  Widget _buildDocumentsTab() {
    final docs = _vaultManager.items.where((e) => e.type == VaultMediaType.document || e.type == VaultMediaType.audio || e.type == VaultMediaType.other).toList();

    if (docs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.white.withOpacity(0.2)),
            const SizedBox(height: 12),
            const Text('No Documents or Audio Stored', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Import PDF, Word, Excel, Audio, and ZIP files securely.', style: TextStyle(color: Colors.white38, fontSize: 12)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(10),
      itemCount: docs.length,
      itemBuilder: (context, index) {
        final item = docs[index];
        return Card(
          color: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: item.color.withOpacity(0.2),
              child: Icon(item.icon, color: item.color),
            ),
            title: Text(item.originalName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text('${item.type.name.toUpperCase()} • ${_formatBytes(item.fileSizeBytes)} • ${DateFormat('MMM dd, yyyy').format(item.dateAdded)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white54, size: 18),
              onSelected: (val) {
                if (val == 'open') _vaultManager.openVaultItem(item);
                if (val == 'export') _vaultManager.exportItemToPublicStorage(item, '/storage/emulated/0/Download');
                if (val == 'delete') _confirmAndDeleteItem(item);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 'open', child: Text('Open File')),
                const PopupMenuItem(value: 'export', child: Text('Export to Downloads')),
                const PopupMenuItem(value: 'delete', child: Text('Delete Permanently', style: TextStyle(color: Colors.redAccent))),
              ],
            ),
            onTap: () => _openDetails(item),
          ),
        );
      },
    );
  }

  // ================= TAB 3: BROWSER =================

  Widget _buildBrowserTab() {
    final downloads = _vaultManager.downloads;

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Launch Card
          InkWell(
            onTap: _openPrivateBrowser,
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyanAccent.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: Colors.cyanAccent,
                    child: Icon(Icons.language, color: Colors.black, size: 28),
                  ),
                  SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Launch Private Browser', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                        SizedBox(height: 4),
                        Text('Incognito navigation with direct-to-vault downloads.', style: TextStyle(color: Colors.white70, fontSize: 12)),
                      ],
                    ),
                  ),
                  Icon(Icons.arrow_forward_ios, color: Colors.white70, size: 16),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Private Downloads section
          Text('Private Browser Downloads (${downloads.length})', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 8),

          Expanded(
            child: downloads.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download_done_outlined, size: 54, color: Colors.white.withOpacity(0.2)),
                        const SizedBox(height: 10),
                        const Text('No Downloads Yet', style: TextStyle(color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 4),
                        const Text('Files downloaded in Private Browser appear here exclusively.', style: TextStyle(color: Colors.white38, fontSize: 11)),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: downloads.length,
                    itemBuilder: (context, index) {
                      final item = downloads[index];
                      return Card(
                        color: const Color(0xFF1E1E1E),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: item.color.withOpacity(0.2),
                            child: Icon(item.icon, color: item.color),
                          ),
                          title: Text(item.originalName, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: Text('${_formatBytes(item.fileSizeBytes)} • ${DateFormat('MMM dd, yyyy').format(item.dateAdded)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                          trailing: const Icon(Icons.arrow_forward_ios, size: 12, color: Colors.white38),
                          onTap: () => _openDetails(item),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // ================= TAB 4: SETTINGS & VAULT =================

  Widget _buildSettingsTab(int totalBytes, int photoBytes, int videoBytes, int docBytes, int audioBytes) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Storage Breakdown Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1E1E1E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Vault Storage Breakdown', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_formatBytes(totalBytes), style: const TextStyle(color: Colors.cyanAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      _buildStorageBarSegment(photoBytes, totalBytes, Colors.blue),
                      _buildStorageBarSegment(videoBytes, totalBytes, Colors.purple),
                      _buildStorageBarSegment(docBytes, totalBytes, Colors.green),
                      _buildStorageBarSegment(audioBytes, totalBytes, Colors.orange),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 6,
                  children: [
                    _buildLegendDot('Photos', Colors.blue, _formatBytes(photoBytes)),
                    _buildLegendDot('Videos', Colors.purple, _formatBytes(videoBytes)),
                    _buildLegendDot('Docs', Colors.green, _formatBytes(docBytes)),
                    _buildLegendDot('Audio', Colors.orange, _formatBytes(audioBytes)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Security Settings
          const Text('Security & Access', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),

          // Biometric Unlock Toggle
          if (_canUseBiometrics)
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: SwitchListTile(
                value: _biometricEnabled,
                activeColor: Colors.cyanAccent,
                secondary: const Icon(Icons.fingerprint, color: Colors.cyanAccent),
                title: const Text('Biometric Quick Unlock', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                subtitle: const Text('Unlock secret vault with Fingerprint or Face ID', style: TextStyle(color: Colors.white54, fontSize: 11)),
                onChanged: (val) async {
                  if (val) {
                    final authenticated = await BiometricService.authenticate(
                      reason: 'Verify identity to enable biometric unlock',
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
                    if (authenticated) {
                      await BiometricService.setBiometricEnabled(true);
                      setState(() => _biometricEnabled = true);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('✅ Biometric Quick Unlock enabled!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    }
                  } else {
                    await BiometricService.setBiometricEnabled(false);
                    setState(() => _biometricEnabled = false);
                  }
                },
              ),
            ),
          const SizedBox(height: 10),

          _buildSettingsActionTile(
            icon: Icons.password,
            iconColor: Colors.amber,
            title: 'Change Vault Password',
            subtitle: 'Update your secret 4-date sequence combination',
            onTap: _changeVaultPassword,
          ),
          const SizedBox(height: 10),

          _buildSettingsActionTile(
            icon: Icons.masks,
            iconColor: Colors.purpleAccent,
            title: 'Change App Disguise Icon',
            subtitle: 'Disguise HideX as Calculator, Notes, Clock, or Weather',
            onTap: _openAppIconDisguise,
          ),
          const SizedBox(height: 20),

          // Backup & Recovery
          const Text('Data Protection', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),

          _buildSettingsActionTile(
            icon: Icons.cloud_sync,
            iconColor: Colors.cyanAccent,
            title: 'Encrypted Backup & Recovery',
            subtitle: 'Survive app uninstall and export .hidexenc archives',
            onTap: _openBackupRestoreScreen,
          ),
          const SizedBox(height: 10),

          _buildSettingsActionTile(
            icon: Icons.account_circle_outlined,
            iconColor: Colors.indigoAccent,
            title: 'Customize Profile Avatar',
            subtitle: 'Choose a private avatar stored inside the encrypted vault',
            onTap: _pickAndSetProfileAvatar,
          ),
          const SizedBox(height: 20),

          // About App
          _buildSettingsActionTile(
            icon: Icons.info_outline,
            iconColor: Colors.blueAccent,
            title: 'About This App',
            subtitle: 'Designed & Developed by Ankush Kumar',
            onTap: _showAboutDeveloperDialog,
          ),
          const SizedBox(height: 20),

          // Danger Zone
          const Text('Danger Zone', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold, fontSize: 15)),
          const SizedBox(height: 10),

          _buildSettingsActionTile(
            icon: Icons.delete_forever_rounded,
            iconColor: Colors.redAccent,
            title: 'Permanently Wipe Entire Vault',
            subtitle: 'Permanently delete all files, photos, albums, and persistent backups from phone',
            onTap: _promptWipeEntireVault,
          ),
        ],
      ),
    );
  }

  Future<void> _promptWipeEntireVault() async {
    final passwordController = TextEditingController();
    String? errorText;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 28),
              SizedBox(width: 10),
              Expanded(
                child: Text('Wipe Entire Vault Permanently', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'DANGER: This action is permanent and IRREVERSIBLE.\n\n'
                  'All encrypted photos, videos, albums, browser downloads, settings, and local backup mirrors will be permanently deleted from your phone storage.\n\n'
                  'To confirm, enter your vault password below:',
                  style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    labelText: 'Vault Password / Sequence',
                    labelStyle: const TextStyle(color: Colors.white60),
                    hintText: 'e.g. 7-14-21-28',
                    hintStyle: const TextStyle(color: Colors.white30),
                    errorText: errorText,
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.redAccent)),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () async {
                final pwd = passwordController.text.trim();
                final parts = pwd
                    .split(RegExp(r'[\s\-,\.]+'))
                    .where((s) => s.isNotEmpty)
                    .map((s) => int.tryParse(s))
                    .where((n) => n != null)
                    .map((n) => n!)
                    .toList();

                bool isValid = false;
                if (parts.length == 4) {
                  isValid = await AuthService.verifyCurrentPassword(parts);
                }
                if (!isValid) {
                  isValid = (pwd == _vaultManager.secretKey);
                }

                if (!isValid) {
                  setDialogState(() {
                    errorText = 'Incorrect password. Cannot wipe vault.';
                  });
                  return;
                }

                Navigator.pop(ctx, true);
              },
              child: const Text('Permanently Wipe Everything'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && mounted) {
      await _vaultManager.wipeVault();
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Vault completely wiped and reset. All private data deleted.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Widget _buildStorageBarSegment(int bytes, int totalBytes, Color color) {
    if (totalBytes == 0 || bytes == 0) return const SizedBox.shrink();
    final flex = ((bytes / totalBytes) * 100).toInt();
    return Expanded(
      flex: flex > 0 ? flex : 1,
      child: Container(height: 10, color: color),
    );
  }

  Widget _buildLegendDot(String label, Color color, String sizeStr) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 5),
        Text('$label ($sizeStr)', style: const TextStyle(color: Colors.white70, fontSize: 11)),
      ],
    );
  }

  Widget _buildSettingsActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withOpacity(0.15),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}
