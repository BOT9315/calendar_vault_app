import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../../models/vault_item.dart';
import '../../services/vault_manager.dart';

class VideoPlayerScreen extends StatefulWidget {
  final VaultItem item;
  final VaultManager vaultManager;

  const VideoPlayerScreen({
    Key? key,
    required this.item,
    required this.vaultManager,
  }) : super(key: key);

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  File? _tempVideoFile;
  bool _isLoading = true;
  bool _showControls = true;
  bool _isMuted = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      _tempVideoFile = await widget.vaultManager.getDecryptedTempFile(widget.item);
      _controller = VideoPlayerController.file(_tempVideoFile!)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
            _controller!.play();
            _controller!.addListener(() {
              if (mounted) setState(() {});
            });
          }
        });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    // Securely wipe decrypted temp video file
    if (_tempVideoFile != null && _tempVideoFile!.existsSync()) {
      try {
        _tempVideoFile!.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  void _toggleMute() {
    if (_controller == null) return;
    setState(() {
      _isMuted = !_isMuted;
      _controller!.setVolume(_isMuted ? 0.0 : 1.0);
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
        title: const Text('Move Video to Album', style: TextStyle(color: Colors.white)),
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
                  const Icon(Icons.video_library, color: Colors.purpleAccent),
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

    final durationStr = _controller != null && _controller!.value.isInitialized
        ? _formatDuration(_controller!.value.duration)
        : 'Unknown';

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
                const Text('Video Details', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                _buildDetailRow('File Name', widget.item.originalName),
                _buildDetailRow('Duration', durationStr),
                _buildDetailRow('File Size', _formatBytes(widget.item.fileSizeBytes)),
                _buildDetailRow('Date Added', DateFormat('MMM dd, yyyy • hh:mm a').format(widget.item.dateAdded)),
                _buildDetailRow('Album', albumName),
                _buildDetailRow('Encryption', 'Military AES-256 (CBC)'),
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

  void _exportVideo() async {
    const defaultExportDir = '/storage/emulated/0/Download';
    final success = await widget.vaultManager.exportItemToPublicStorage(widget.item, defaultExportDir);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Video exported to Downloads!' : 'Failed to export video.'),
        ),
      );
    }
  }

  void _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete video permanently?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will permanently delete the encrypted video from your secret vault.',
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

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    if (duration.inHours > 0) {
      return '${twoDigits(duration.inHours)}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final isInitialized = _controller != null && _controller!.value.isInitialized;
    final position = isInitialized ? _controller!.value.position : Duration.zero;
    final duration = isInitialized ? _controller!.value.duration : Duration.zero;

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
            tooltip: _isMuted ? 'Unmute' : 'Mute',
            icon: Icon(_isMuted ? Icons.volume_off : Icons.volume_up),
            onPressed: _toggleMute,
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
              if (val == 'export') _exportVideo();
              if (val == 'delete') _confirmDelete();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(Icons.file_download_outlined, size: 18),
                    SizedBox(width: 8),
                    Text('Unhide / Export Video'),
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
          : isInitialized
              ? GestureDetector(
                  onTap: () => setState(() => _showControls = !_showControls),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Center(
                        child: AspectRatio(
                          aspectRatio: _controller!.value.aspectRatio,
                          child: VideoPlayer(_controller!),
                        ),
                      ),

                      // Overlay Play/Pause Button
                      if (_showControls)
                        Center(
                          child: CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              iconSize: 40,
                              icon: Icon(
                                _controller!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                              onPressed: () {
                                setState(() {
                                  _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                                });
                              },
                            ),
                          ),
                        ),

                      // Bottom Progress bar & Duration
                      if (_showControls)
                        Positioned(
                          bottom: 0,
                          left: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: const BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [Colors.black87, Colors.transparent],
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                VideoProgressIndicator(
                                  _controller!,
                                  allowScrubbing: true,
                                  colors: const VideoProgressColors(
                                    playedColor: Colors.purpleAccent,
                                    bufferedColor: Colors.white24,
                                    backgroundColor: Colors.white12,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      _formatDuration(position),
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                    Text(
                                      _formatDuration(duration),
                                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              : const Center(
                  child: Text('Unable to play video format.', style: TextStyle(color: Colors.white)),
                ),
    );
  }
}
