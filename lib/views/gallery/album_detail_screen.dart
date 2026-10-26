import 'package:flutter/material.dart';
import '../../models/album.dart';
import '../../models/vault_item.dart';
import '../../services/vault_manager.dart';
import '../vault/photo_viewer_screen.dart';
import '../vault/video_player_screen.dart';
import '../widgets/media_grid_item.dart';

class AlbumDetailScreen extends StatefulWidget {
  final Album album;
  final VaultManager vaultManager;

  const AlbumDetailScreen({
    Key? key,
    required this.album,
    required this.vaultManager,
  }) : super(key: key);

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
  final Set<String> _selectedIds = {};
  bool _isSelectionMode = false;

  void _toggleSelect(VaultItem item) {
    setState(() {
      if (_selectedIds.contains(item.id)) {
        _selectedIds.remove(item.id);
        if (_selectedIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedIds.add(item.id);
        _isSelectionMode = true;
      }
    });
  }

  void _selectAll(List<VaultItem> items) {
    setState(() {
      if (_selectedIds.length == items.length) {
        _selectedIds.clear();
        _isSelectionMode = false;
      } else {
        _selectedIds.addAll(items.map((e) => e.id));
        _isSelectionMode = true;
      }
    });
  }

  Future<void> _renameAlbum() async {
    final controller = TextEditingController(text: widget.album.name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Rename Album', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Enter new album name',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.indigoAccent)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty) {
      await widget.vaultManager.renameAlbum(widget.album.id, newName);
      setState(() {
        widget.album.name = newName;
      });
    }
  }

  Future<void> _deleteAlbum() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Delete Album?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Deleting this album will NOT delete the photos/videos inside it. They will still remain safe in your vault.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Album'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.vaultManager.deleteAlbum(widget.album.id);
      if (mounted) Navigator.pop(context);
    }
  }

  Future<void> _removeSelectedFromAlbum(List<VaultItem> albumItems) async {
    final selectedItems = albumItems.where((e) => _selectedIds.contains(e.id)).toList();
    for (final item in selectedItems) {
      await widget.vaultManager.assignItemToAlbum(item.id, null);
    }
    setState(() {
      _selectedIds.clear();
      _isSelectionMode = false;
    });
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Removed ${selectedItems.length} item(s) from album.')),
      );
    }
  }

  Future<void> _addExistingVaultItemsToAlbum() async {
    // Show modal to pick from unassigned or all vault items
    final otherItems = widget.vaultManager.items.where((e) => e.albumId != widget.album.id).toList();
    if (otherItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No other items available in vault to add.')),
      );
      return;
    }

    final chosen = await showModalBottomSheet<List<VaultItem>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF1E1E1E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final selected = <String>{};
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              child: SizedBox(
                height: MediaQuery.of(context).size.height * 0.7,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Add Files to Album', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                            onPressed: selected.isEmpty
                                ? null
                                : () {
                                    final itemsToAdd = otherItems.where((e) => selected.contains(e.id)).toList();
                                    Navigator.pop(ctx, itemsToAdd);
                                  },
                            child: Text('Add (${selected.length})'),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white12),
                    Expanded(
                      child: ListView.builder(
                        itemCount: otherItems.length,
                        itemBuilder: (context, index) {
                          final item = otherItems[index];
                          final isChecked = selected.contains(item.id);
                          return CheckboxListTile(
                            value: isChecked,
                            activeColor: Colors.indigoAccent,
                            secondary: Icon(item.icon, color: item.color),
                            title: Text(item.originalName, style: const TextStyle(color: Colors.white, fontSize: 13), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${item.type.name.toUpperCase()} • ${_formatBytes(item.fileSizeBytes)}', style: const TextStyle(color: Colors.white54, fontSize: 11)),
                            onChanged: (val) {
                              setSheetState(() {
                                if (val == true) {
                                  selected.add(item.id);
                                } else {
                                  selected.remove(item.id);
                                }
                              });
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (chosen != null && chosen.isNotEmpty) {
      await widget.vaultManager.moveMultipleItemsToAlbum(chosen, widget.album.id);
      setState(() {});
    }
  }

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
            vaultManager: widget.vaultManager,
          ),
        ),
      ).then((_) => setState(() {}));
    } else if (item.type == VaultMediaType.video) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VideoPlayerScreen(
            item: item,
            vaultManager: widget.vaultManager,
          ),
        ),
      ).then((_) => setState(() {}));
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final albumItems = widget.vaultManager.getItemsForAlbum(widget.album.id);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E1E1E),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.album.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text('${albumItems.length} item(s)', style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
        actions: [
          if (_isSelectionMode) ...[
            IconButton(
              tooltip: 'Select All',
              icon: Icon(_selectedIds.length == albumItems.length ? Icons.deselect : Icons.select_all),
              onPressed: () => _selectAll(albumItems),
            ),
            IconButton(
              tooltip: 'Remove from Album',
              icon: const Icon(Icons.folder_off_outlined, color: Colors.amberAccent),
              onPressed: () => _removeSelectedFromAlbum(albumItems),
            ),
          ] else ...[
            IconButton(
              tooltip: 'Add Files from Vault',
              icon: const Icon(Icons.add_photo_alternate_outlined),
              onPressed: _addExistingVaultItemsToAlbum,
            ),
            IconButton(
              tooltip: 'Rename Album',
              icon: const Icon(Icons.edit_outlined),
              onPressed: _renameAlbum,
            ),
            IconButton(
              tooltip: 'Delete Album',
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _deleteAlbum,
            ),
          ],
        ],
      ),
      body: albumItems.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.photo_album_outlined, size: 64, color: Colors.white.withOpacity(0.2)),
                  const SizedBox(height: 12),
                  const Text('Album is Empty', style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 6),
                  const Text('Add files from your vault to organize this album.', style: TextStyle(color: Colors.white38, fontSize: 12)),
                  const SizedBox(height: 18),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo),
                    icon: const Icon(Icons.add),
                    label: const Text('Add Files'),
                    onPressed: _addExistingVaultItemsToAlbum,
                  ),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(8.0),
              child: GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.95,
                ),
                itemCount: albumItems.length,
                itemBuilder: (context, index) {
                  final item = albumItems[index];
                  final isSelected = _selectedIds.contains(item.id);

                  return Stack(
                    children: [
                      MediaGridItem(
                        item: item,
                        vaultManager: widget.vaultManager,
                        onTap: () => _openDetails(item),
                      ),
                      if (_isSelectionMode)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: GestureDetector(
                            onTap: () => _toggleSelect(item),
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: isSelected ? Colors.indigoAccent : Colors.black54,
                              child: Icon(
                                isSelected ? Icons.check : Icons.circle_outlined,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
    );
  }
}
