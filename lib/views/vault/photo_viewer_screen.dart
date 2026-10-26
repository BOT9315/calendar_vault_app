import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/vault_item.dart';
import '../../services/vault_manager.dart';

class PhotoViewerScreen extends StatefulWidget {
  final VaultItem item;
  final VaultManager vaultManager;

  const PhotoViewerScreen({
    Key? key,
    required this.item,
    required this.vaultManager,
  }) : super(key: key);

  @override
  State<PhotoViewerScreen> createState() => _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<PhotoViewerScreen> {
  Uint8List? _decryptedBytes;
  bool _isLoading = true;
  int _rotationQuarterTurns = 0;
  final TransformationController _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _loadPhoto();
  }

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  Future<void> _loadPhoto() async {
    final bytes = await widget.vaultManager.getDecryptedBytes(widget.item);
    if (mounted) {
      setState(() {
        _decryptedBytes = bytes;
        _isLoading = false;
      });
    }
  }

  void _rotatePhoto() {
    setState(() {
      _rotationQuarterTurns = (_rotationQuarterTurns + 1) % 4;
    });
  }

  void _toggleFavorite() async {
    await widget.vaultManager.toggleFavorite(widget.item);
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 1),
          content: Text(widget.item.isFavorite ? '❤️ Added to Favorites' : 'Removed from Favorites'),
        ),
      );
    }
  }

  void _showMoveToAlbumDialog() async {
    final albums = widget.vaultManager.albums;
    if (albums.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No albums created yet. Create an album first!')),
      );
      return;
    }

    final chosenAlbumId = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Move to Album', style: TextStyle(color: Colors.white)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: const Row(
              children: [
                Icon(Icons.folder_off, color: Colors.white60),
                SizedBox(width: 10),
                Text('No Album (Remove from album)', style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
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
      await widget.vaultManager.assignItemToAlbum(widget.item.id, chosenAlbumId.isEmpty ? null : chosenAlbumId);
      setState(() {});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Album updated!')),
        );
      }
    }
  }

  void _showDetailsSheet() {
    String albumName = 'None';
    if (widget.item.albumId != null) {
      for (final a in widget.vaultManager.albums) {
        if (a.id == widget.item.albumId) {
          albumName = a.name;
          break;
        }
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Media Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                _buildDetailRow('File Name', widget.item.originalName),
                _buildDetailRow('File Size', _formatBytes(widget.item.fileSizeBytes)),
                _buildDetailRow('Date Added', DateFormat('MMM dd, yyyy • hh:mm a').format(widget.item.dateAdded)),
                _buildDetailRow('Album', albumName),
                _buildDetailRow('Encryption', 'Military AES-256 (CBC)'),
                _buildDetailRow('Encrypted File', widget.item.encryptedFileName),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  void _exportPhoto() async {
    const defaultExportDir = '/storage/emulated/0/Download';
    final success = await widget.vaultManager.exportItemToPublicStorage(widget.item, defaultExportDir);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Exported to Downloads folder!' : 'Failed to export.'),
        ),
      );
    }
  }

  void _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete permanently?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete the encrypted photo from your secret vault.',
          style: TextStyle(color: Colors.white70),
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
      await widget.vaultManager.deleteItem(widget.item);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.8),
        foregroundColor: Colors.white,
        title: Text(
          widget.item.originalName,
          style: const TextStyle(fontSize: 15),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Rotate 90°',
            icon: const Icon(Icons.rotate_right),
            onPressed: _rotatePhoto,
          ),
          IconButton(
            tooltip: widget.item.isFavorite ? 'Favorited' : 'Favorite',
            icon: Icon(
              widget.item.isFavorite ? Icons.favorite : Icons.favorite_border,
              color: widget.item.isFavorite ? Colors.redAccent : Colors.white,
            ),
            onPressed: _toggleFavorite,
          ),
          IconButton(
            tooltip: 'Move to Album',
            icon: const Icon(Icons.drive_file_move_outlined),
            onPressed: _showMoveToAlbumDialog,
          ),
          IconButton(
            tooltip: 'Info / Details',
            icon: const Icon(Icons.info_outline),
            onPressed: _showDetailsSheet,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onSelected: (val) {
              if (val == 'export') _exportPhoto();
              if (val == 'delete') _confirmDelete();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Unhide / Export to Phone'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('Delete Permanently', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.cyanAccent))
          : _decryptedBytes == null
              ? const Center(child: Text('Failed to decrypt image.', style: TextStyle(color: Colors.white)))
              : Center(
                  child: InteractiveViewer(
                    transformationController: _transformationController,
                    minScale: 0.5,
                    maxScale: 5.0,
                    child: RotatedBox(
                      quarterTurns: _rotationQuarterTurns,
                      child: Image.memory(
                        _decryptedBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
    );
  }
}
