import 'dart:io';
import 'package:flutter/material.dart';

enum ImportOption {
  importOnly,
  importAndRemoveOriginals,
}

class ImportConfirmationDialog extends StatefulWidget {
  final List<File> files;

  const ImportConfirmationDialog({
    Key? key,
    required this.files,
  }) : super(key: key);

  @override
  State<ImportConfirmationDialog> createState() => _ImportConfirmationDialogState();
}

class _ImportConfirmationDialogState extends State<ImportConfirmationDialog> {
  ImportOption _selectedOption = ImportOption.importOnly;
  bool _userExplicitConsent = false;

  int _calculateTotalBytes() {
    int total = 0;
    for (final file in widget.files) {
      try {
        total += file.lengthSync();
      } catch (_) {}
    }
    return total;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final totalBytes = _calculateTotalBytes();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      backgroundColor: const Color(0xFF1E1E1E),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.indigo.withOpacity(0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.security, color: Colors.indigoAccent, size: 24),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Secure Vault Import',
              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Summary card
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Selected Items', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text('${widget.files.length} file(s)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total Size', style: TextStyle(color: Colors.white54, fontSize: 11)),
                      Text(_formatBytes(totalBytes), style: const TextStyle(color: Colors.indigoAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text(
              'Choose Import Strategy:',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const SizedBox(height: 10),

            // Option A: Import Only
            Container(
              decoration: BoxDecoration(
                color: _selectedOption == ImportOption.importOnly ? Colors.indigo.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedOption == ImportOption.importOnly ? Colors.indigoAccent : Colors.white12,
                ),
              ),
              child: RadioListTile<ImportOption>(
                value: ImportOption.importOnly,
                groupValue: _selectedOption,
                activeColor: Colors.indigoAccent,
                title: const Text('Option A: Import Only', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: const Text(
                  'Copy items into HideX vault and keep original files untouched on the phone.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
            ),
            const SizedBox(height: 10),

            // Option B: Import and Remove Originals
            Container(
              decoration: BoxDecoration(
                color: _selectedOption == ImportOption.importAndRemoveOriginals ? Colors.red.withOpacity(0.12) : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedOption == ImportOption.importAndRemoveOriginals ? Colors.redAccent : Colors.white12,
                ),
              ),
              child: RadioListTile<ImportOption>(
                value: ImportOption.importAndRemoveOriginals,
                groupValue: _selectedOption,
                activeColor: Colors.redAccent,
                title: const Text('Option B: Import & Remove Originals', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                subtitle: const Text(
                  'Encrypt into vault, verify each file, and safely remove originals from public gallery.',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
            ),

            // If Option B is selected, show verification notice & explicit consent checkbox
            if (_selectedOption == ImportOption.importAndRemoveOriginals) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.verified_user, color: Colors.amberAccent, size: 16),
                        SizedBox(width: 6),
                        Text(
                          'Pre-Deletion Safety Verification:',
                          style: TextStyle(color: Colors.amberAccent, fontWeight: FontWeight.bold, fontSize: 11),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      '• Every file will be decrypted in memory to verify zero corruption.\n'
                      '• Deleting originals may affect availability in cloud gallery backups.\n'
                      '• Originals are PRESERVED if copying or verification fails.',
                      style: TextStyle(color: Colors.white70, fontSize: 10.5, height: 1.3),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _userExplicitConsent,
                activeColor: Colors.redAccent,
                title: const Text(
                  'I authorize HideX to delete original phone copies after successful vault verification.',
                  style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                ),
                onChanged: (val) {
                  setState(() => _userExplicitConsent = val ?? false);
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('Cancel', style: TextStyle(color: Colors.white60)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: _selectedOption == ImportOption.importAndRemoveOriginals ? Colors.redAccent : Colors.indigo,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onPressed: (_selectedOption == ImportOption.importAndRemoveOriginals && !_userExplicitConsent)
              ? null
              : () {
                  Navigator.pop(
                    context,
                    _selectedOption == ImportOption.importAndRemoveOriginals,
                  );
                },
          child: Text(
            _selectedOption == ImportOption.importAndRemoveOriginals ? 'Verify & Import (Remove Originals)' : 'Import (Keep Originals)',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ],
    );
  }
}
