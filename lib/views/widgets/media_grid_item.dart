import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/vault_item.dart';
import '../../services/vault_manager.dart';

class MediaGridItem extends StatefulWidget {
  final VaultItem item;
  final VaultManager vaultManager;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool isSelected;
  final bool isSelectionMode;

  const MediaGridItem({
    Key? key,
    required this.item,
    required this.vaultManager,
    required this.onTap,
    this.onLongPress,
    this.isSelected = false,
    this.isSelectionMode = false,
  }) : super(key: key);

  @override
  State<MediaGridItem> createState() => _MediaGridItemState();
}

class _MediaGridItemState extends State<MediaGridItem> {
  Uint8List? _previewBytes;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    if (widget.item.type == VaultMediaType.photo) {
      _loadThumbnail();
    }
  }

  @override
  void didUpdateWidget(covariant MediaGridItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.id != widget.item.id && widget.item.type == VaultMediaType.photo) {
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    if (_loading) return;
    _loading = true;
    try {
      final bytes = await widget.vaultManager.getDecryptedBytes(widget.item);
      if (mounted) {
        setState(() {
          _previewBytes = bytes;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;

    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      borderRadius: BorderRadius.circular(14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E1E),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.isSelected ? Colors.indigoAccent : Colors.white12,
              width: widget.isSelected ? 2.5 : 1.0,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Content presentation
              if (item.type == VaultMediaType.photo && _previewBytes != null)
                Image.memory(
                  _previewBytes!,
                  fit: BoxFit.cover,
                )
              else if (item.type == VaultMediaType.video)
                Container(
                  color: Colors.purple.shade900.withOpacity(0.35),
                  child: Center(
                    child: Icon(Icons.play_circle_fill, color: Colors.purpleAccent.shade100, size: 40),
                  ),
                )
              else
                Container(
                  color: item.color.withOpacity(0.12),
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(item.icon, color: item.color, size: 36),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: item.color.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          item.fileExtension.toUpperCase(),
                          style: TextStyle(
                            color: item.color,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

              // Favorite Heart Badge (top right)
              if (item.isFavorite)
                Positioned(
                  top: 6,
                  right: widget.isSelectionMode ? 32 : 6,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.favorite, color: Colors.redAccent, size: 12),
                  ),
                ),

              // Selection Checkbox (top right)
              if (widget.isSelectionMode)
                Positioned(
                  top: 6,
                  right: 6,
                  child: CircleAvatar(
                    radius: 11,
                    backgroundColor: widget.isSelected ? Colors.indigoAccent : Colors.black54,
                    child: Icon(
                      widget.isSelected ? Icons.check : Icons.circle_outlined,
                      size: 14,
                      color: Colors.white,
                    ),
                  ),
                ),

              // Private Download Badge (top left)
              if (item.isDownloaded)
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.cyan.shade900.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.5)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.download, color: Colors.cyanAccent, size: 9),
                        SizedBox(width: 2),
                        Text(
                          'PRIVATE',
                          style: TextStyle(color: Colors.cyanAccent, fontSize: 7.5, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),

              // Bottom gradient with filename & size
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Colors.black87, Colors.transparent],
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.originalName,
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(item.icon, color: Colors.white60, size: 11),
                          Text(
                            _formatBytes(item.fileSizeBytes),
                            style: const TextStyle(color: Colors.white60, fontSize: 8.5),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
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
