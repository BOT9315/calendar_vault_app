import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/auth_service.dart';
import '../../services/backup_service.dart';
import '../../services/cloud_backup_service.dart';
import '../../services/vault_manager.dart';

class BackupRestoreScreen extends StatefulWidget {
  final VaultManager vaultManager;

  const BackupRestoreScreen({
    Key? key,
    required this.vaultManager,
  }) : super(key: key);

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isProcessing = false;
  double _progress = 0.0;
  String _statusMessage = '';
  DateTime? _lastBackupTime;
  bool _hasPendingChanges = false;
  CloudSyncConfig? _cloudConfig;

  @override
  void initState() {
    super.initState();
    _loadBackupState();
  }

  Future<void> _loadBackupState() async {
    final lastTime = await BackupService.getLastBackupTime();
    final pending = await BackupService.hasPendingChanges();
    final cloudCfg = await CloudBackupService.loadConfig();
    if (mounted) {
      setState(() {
        _lastBackupTime = lastTime;
        _hasPendingChanges = pending;
        _cloudConfig = cloudCfg;
      });
    }
  }

  Future<void> _performManualBackup() async {
    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = 'Starting encrypted vault backup...';
    });

    final defaultExportDir = Directory('/storage/emulated/0/Download');
    final nowStr = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final destPath = '${defaultExportDir.path}/hidex_backup_$nowStr.hidexenc';

    final resultFile = await BackupService.createEncryptedBackupArchive(
      secretKey: widget.vaultManager.secretKey,
      items: widget.vaultManager.items,
      albums: widget.vaultManager.albums,
      destinationFilePath: destPath,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _statusMessage = status;
          });
        }
      },
    );

    await _loadBackupState();

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (resultFile != null) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.verified, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Backup Complete & Verified', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Text(
              'Your encrypted backup package has been created and verified at:\n\n'
              '${resultFile.path}\n\n'
              'All private photos, videos, albums, and settings are securely encrypted with your vault password.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to complete backup. Please check storage permissions.'),
          ),
        );
      }
    }
  }

  Future<void> _restoreFromPackage() async {
    final picked = await FilePicker.pickFile(
      type: FileType.any,
    );

    if (picked == null || picked.path == null) {
      return;
    }

    final backupFile = File(picked.path!);
    if (!backupFile.path.endsWith('.hidexenc')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.orange,
          content: Text('Please select a valid HideX backup package (.hidexenc).'),
        ),
      );
      return;
    }

    // Prompt for password
    final passwordController = TextEditingController();
    final enteredPassword = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Enter Vault Password', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter the vault password used when this backup was created:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'e.g. 7-14-21-28',
                hintStyle: TextStyle(color: Colors.white30),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.indigoAccent)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.pop(ctx, passwordController.text.trim()),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (enteredPassword == null || enteredPassword.isEmpty) return;

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = 'Decrypting and verifying backup integrity...';
    });

    final restoreResult = await BackupService.restoreFromEncryptedBackupArchive(
      backupFile: backupFile,
      secretKey: enteredPassword,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _statusMessage = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (restoreResult.isSuccess) {
        await widget.vaultManager.initialize();
        await _loadBackupState();

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Restore Successful', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Text(
              '${restoreResult.message}\n\n'
              'Restored ${restoreResult.itemsRestored} file(s) and ${restoreResult.albumsRestored} album(s) into your vault.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK', style: TextStyle(color: Colors.cyanAccent)),
              ),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Restore Failed', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Text(
              restoreResult.message,
              style: const TextStyle(color: Colors.white70, fontSize: 13),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _configureCloudSync() async {
    final currentCfg = _cloudConfig ?? await CloudBackupService.loadConfig();
    final urlController = TextEditingController(text: currentCfg?.serverUrl ?? '');
    final tokenController = TextEditingController(text: currentCfg?.authToken ?? '');
    bool isEnabled = currentCfg?.isEnabled ?? true;
    String? testResult;
    bool isTesting = false;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1E1E1E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(
            children: [
              Icon(Icons.cloud_sync_rounded, color: Colors.cyanAccent),
              SizedBox(width: 8),
              Text('Cloud Backup Settings', style: TextStyle(color: Colors.white, fontSize: 16)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Store an encrypted master backup of your private vault on remote cloud storage (WebDAV, Nextcloud, REST, or Supabase).',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: urlController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Cloud Storage URL',
                    labelStyle: TextStyle(color: Colors.white60),
                    hintText: 'https://cloud.example.com/vault.hidexenc',
                    hintStyle: TextStyle(color: Colors.white30),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: tokenController,
                  obscureText: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Bearer Auth Token (Optional)',
                    labelStyle: TextStyle(color: Colors.white60),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.cyanAccent)),
                  ),
                ),
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable Cloud Backup', style: TextStyle(color: Colors.white, fontSize: 14)),
                  value: isEnabled,
                  activeColor: Colors.cyanAccent,
                  onChanged: (val) => setDialogState(() => isEnabled = val),
                ),
                if (testResult != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    testResult!,
                    style: TextStyle(
                      fontSize: 11,
                      color: testResult!.contains('successfully') ? Colors.greenAccent : Colors.redAccent,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: isTesting
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.network_check, size: 16),
                  label: const Text('Test Connection'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.cyanAccent,
                    side: const BorderSide(color: Colors.cyanAccent),
                  ),
                  onPressed: isTesting
                      ? null
                      : () async {
                          final url = urlController.text.trim();
                          if (url.isEmpty) {
                            setDialogState(() => testResult = 'Please enter a server URL first.');
                            return;
                          }
                          setDialogState(() {
                            isTesting = true;
                            testResult = 'Testing connection...';
                          });
                          final res = await CloudBackupService.testConnection(
                            serverUrl: url,
                            authToken: tokenController.text.trim(),
                          );
                          setDialogState(() {
                            isTesting = false;
                            testResult = res['message'] as String;
                          });
                        },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
              onPressed: () async {
                final newCfg = CloudSyncConfig(
                  serverUrl: urlController.text.trim(),
                  authToken: tokenController.text.trim(),
                  isEnabled: isEnabled,
                  lastSyncTime: currentCfg?.lastSyncTime,
                  lastStatusMessage: currentCfg?.lastStatusMessage,
                );
                await CloudBackupService.saveConfig(newCfg);
                await _loadBackupState();
                if (mounted) Navigator.pop(ctx);
              },
              child: const Text('Save Settings'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _syncToCloudNow() async {
    final cfg = _cloudConfig ?? await CloudBackupService.loadConfig();
    if (cfg == null || cfg.serverUrl.trim().isEmpty) {
      await _configureCloudSync();
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = 'Preparing encrypted cloud backup...';
    });

    final success = await CloudBackupService.uploadMasterBackupToCloud(
      secretKey: widget.vaultManager.secretKey,
      items: widget.vaultManager.items,
      albums: widget.vaultManager.albums,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _progress = progress;
            _statusMessage = status;
          });
        }
      },
    );

    await _loadBackupState();

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (success) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Cloud Backup Complete', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: const Text(
              'Your complete encrypted private vault has been verified and safely synced to your remote cloud storage.\n\n'
              'If you ever uninstall or replace your phone, you can restore all files and albums anytime.',
              style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: Colors.cyanAccent))),
            ],
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Cloud sync failed. Please check network connection and cloud settings.'),
          ),
        );
      }
    }
  }

  Future<void> _restoreFromCloud() async {
    final cfg = _cloudConfig ?? await CloudBackupService.loadConfig();
    final urlController = TextEditingController(text: cfg?.serverUrl ?? '');
    final tokenController = TextEditingController(text: cfg?.authToken ?? '');
    final passwordController = TextEditingController(text: widget.vaultManager.secretKey);

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Row(
          children: [
            Icon(Icons.cloud_download, color: Colors.cyanAccent),
            SizedBox(width: 8),
            Text('Restore From Cloud', style: TextStyle(color: Colors.white, fontSize: 16)),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Download and restore your encrypted vault archive from remote cloud storage:',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: urlController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Cloud Server URL',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tokenController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Auth Token (Optional)',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Vault Password / Sequence',
                  labelStyle: TextStyle(color: Colors.white60),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Download & Restore'),
          ),
        ],
      ),
    );

    if (proceed != true) return;

    final url = urlController.text.trim();
    final token = tokenController.text.trim();
    final pwd = passwordController.text.trim();

    if (url.isEmpty || pwd.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud URL and Vault Password are required.')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _progress = 0.0;
      _statusMessage = 'Connecting to cloud vault...';
    });

    final res = await CloudBackupService.restoreVaultFromCloud(
      serverUrl: url,
      authToken: token,
      secretKey: pwd,
      onProgress: (p, msg) {
        if (mounted) {
          setState(() {
            _progress = p;
            _statusMessage = msg;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isProcessing = false;
      });

      if (res.isSuccess) {
        await widget.vaultManager.initialize();
        await _loadBackupState();

        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent),
                SizedBox(width: 8),
                Text('Cloud Restore Complete', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Text(
              '${res.message}\n\n'
              'Restored ${res.itemsRestored} file(s) and ${res.albumsRestored} album(s) into your vault.',
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK', style: TextStyle(color: Colors.cyanAccent))),
            ],
          ),
        );
      } else {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E1E1E),
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent),
                SizedBox(width: 8),
                Text('Restore Failed', style: TextStyle(color: Colors.white, fontSize: 16)),
              ],
            ),
            content: Text(res.message, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
            ],
          ),
        );
      }
    }
  }

  Future<void> _wipeVaultPermanently() async {
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
                  'DANGER: This action is permanent and cannot be undone.\n\n'
                  'All encrypted photos, videos, albums, and local persistent backups will be completely erased from this phone.\n\n'
                  'To proceed, enter your vault password below:',
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
                  isValid = (pwd == widget.vaultManager.secretKey);
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
      await widget.vaultManager.wipeVault();
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
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

  @override
  Widget build(BuildContext context) {
    final itemCount = widget.vaultManager.items.length;
    final albumCount = widget.vaultManager.albums.length;
    final totalBytes = widget.vaultManager.getTotalStorageBytes();

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: const Text('Backup & Recovery', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _hasPendingChanges ? Colors.amber.withOpacity(0.5) : Colors.green.withOpacity(0.5),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        _hasPendingChanges ? Icons.sync_problem : Icons.shield_rounded,
                        color: _hasPendingChanges ? Colors.amberAccent : Colors.greenAccent,
                        size: 26,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _hasPendingChanges ? 'Unbacked Changes Detected' : 'Vault Backup Up-to-Date',
                          style: TextStyle(
                            color: _hasPendingChanges ? Colors.amberAccent : Colors.greenAccent,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _lastBackupTime != null
                        ? 'Last successful backup: ${DateFormat('MMM dd, yyyy • hh:mm a').format(_lastBackupTime!)}'
                        : 'No standalone backup package created yet.',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildMiniBadge(Icons.file_copy, '$itemCount Items'),
                      const SizedBox(width: 8),
                      _buildMiniBadge(Icons.photo_album, '$albumCount Albums'),
                      const SizedBox(width: 8),
                      _buildMiniBadge(Icons.data_usage, _formatBytes(totalBytes)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Progress bar if active
            if (_isProcessing) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.indigo.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.indigoAccent.withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_statusMessage, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation<Color>(Colors.cyanAccent),
                    ),
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text('${(_progress * 100).toInt()}%', style: const TextStyle(color: Colors.white54, fontSize: 10)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Local Package Actions
            const Text('Local Backup Package', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            _buildActionTile(
              icon: Icons.inventory_2_outlined,
              iconColor: Colors.cyanAccent,
              title: 'Create Encrypted Archive (.hidexenc)',
              subtitle: 'Package all files and albums into an exportable file for safe storage.',
              onTap: _isProcessing ? null : _performManualBackup,
            ),
            const SizedBox(height: 10),

            _buildActionTile(
              icon: Icons.restore_page_outlined,
              iconColor: Colors.purpleAccent,
              title: 'Restore from .hidexenc File',
              subtitle: 'Select any .hidexenc package from device storage to restore.',
              onTap: _isProcessing ? null : _restoreFromPackage,
            ),
            const SizedBox(height: 20),

            // Cloud Synchronization Section
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Encrypted Cloud Storage', style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                if (_cloudConfig?.isEnabled == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.greenAccent),
                    ),
                    child: const Text('Active', style: TextStyle(color: Colors.greenAccent, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
              ],
            ),
            const SizedBox(height: 12),

            _buildActionTile(
              icon: Icons.cloud_sync_outlined,
              iconColor: Colors.lightBlueAccent,
              title: 'Cloud Backup Settings',
              subtitle: _cloudConfig?.serverUrl.isNotEmpty == true
                  ? 'Connected: ${_cloudConfig!.serverUrl}'
                  : 'Configure WebDAV, Nextcloud, REST, or Supabase cloud sync.',
              onTap: _isProcessing ? null : _configureCloudSync,
            ),
            const SizedBox(height: 10),

            _buildActionTile(
              icon: Icons.cloud_upload_outlined,
              iconColor: Colors.greenAccent,
              title: 'Sync to Cloud Storage Now',
              subtitle: 'Upload a verified SHA-256 encrypted master backup to your remote cloud.',
              onTap: _isProcessing ? null : _syncToCloudNow,
            ),
            const SizedBox(height: 10),

            _buildActionTile(
              icon: Icons.cloud_download_outlined,
              iconColor: Colors.amberAccent,
              title: 'Restore Vault from Cloud',
              subtitle: 'Download and recover your entire vault after reinstalling on any device.',
              onTap: _isProcessing ? null : _restoreFromCloud,
            ),
            const SizedBox(height: 20),

            // Persistent reinstallation protection explanation
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blueAccent, size: 20),
                      SizedBox(width: 8),
                      Text('Survival Across Reinstallation', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '1. Persistent Folder Storage:\n'
                    'All encrypted vault items are automatically saved to persistent device storage at /storage/emulated/0/Documents/.calendar_vault/. Android does NOT wipe this location when you uninstall the app.\n\n'
                    '2. Exportable Encrypted Archive (.hidexenc):\n'
                    'The "Back Up Now" feature packs and encrypts everything into a single portable package. You can copy it to a computer, flash drive, or cloud drive (Google Drive, Dropbox) for complete off-device peace of mind.\n\n'
                    '3. Restoring:\n'
                    'When reinstalling HideX, simply tap your secret date sequence to immediately reload your persistent vault, or use "Restore Vault from Backup" to load any .hidexenc archive.',
                    style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Danger Zone
            const Text('Danger Zone', style: TextStyle(color: Colors.redAccent, fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),

            _buildActionTile(
              icon: Icons.delete_forever_rounded,
              iconColor: Colors.redAccent,
              title: 'Permanently Wipe Entire Vault',
              subtitle: 'Completely erase all encrypted media, albums, settings, and local backups from this device.',
              onTap: _isProcessing ? null : _wipeVaultPermanently,
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniBadge(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(color: Colors.white70, fontSize: 11)),
        ],
      ),
    );
  }

  Widget _buildActionTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white10),
        ),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: iconColor.withOpacity(0.15),
              child: Icon(icon, color: iconColor),
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
