import 'package:flutter/material.dart';

enum VaultMediaType { photo, video, document, audio, other }

class VaultItem {
  final String id;
  String originalName;
  final String encryptedFileName; // Relative name in the hidden persistent directory
  final VaultMediaType type;
  final int fileSizeBytes;
  final DateTime dateAdded;
  DateTime? dateModified;
  final int? durationSeconds; // For audio/videos
  final bool isDownloaded; // From private browser
  String? albumId; // Associated album, if any
  bool isFavorite; // Quick favorites bookmark
  String? notes; // Optional private notes

  VaultItem({
    required this.id,
    required this.originalName,
    required this.encryptedFileName,
    required this.type,
    required this.fileSizeBytes,
    required this.dateAdded,
    this.dateModified,
    this.durationSeconds,
    this.isDownloaded = false,
    this.albumId,
    this.isFavorite = false,
    this.notes,
  });

  String get fileExtension {
    if (originalName.contains('.')) {
      return originalName.split('.').last.toLowerCase();
    }
    return '';
  }

  IconData get icon {
    switch (type) {
      case VaultMediaType.photo:
        return Icons.image_outlined;
      case VaultMediaType.video:
        return Icons.video_library_outlined;
      case VaultMediaType.audio:
        return Icons.audio_file_outlined;
      case VaultMediaType.document:
        final ext = fileExtension;
        if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
        if (ext == 'doc' || ext == 'docx') return Icons.description_outlined;
        if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') return Icons.table_chart_outlined;
        if (ext == 'ppt' || ext == 'pptx') return Icons.slideshow_outlined;
        return Icons.article_outlined;
      case VaultMediaType.other:
        final ext = fileExtension;
        if (ext == 'zip' || ext == 'rar' || ext == '7z' || ext == 'tar') {
          return Icons.folder_zip_outlined;
        }
        return Icons.insert_drive_file_outlined;
    }
  }

  Color get color {
    switch (type) {
      case VaultMediaType.photo:
        return Colors.blue;
      case VaultMediaType.video:
        return Colors.purple;
      case VaultMediaType.audio:
        return Colors.orange;
      case VaultMediaType.document:
        final ext = fileExtension;
        if (ext == 'pdf') return Colors.red;
        if (ext == 'doc' || ext == 'docx') return Colors.indigo;
        if (ext == 'xls' || ext == 'xlsx' || ext == 'csv') return Colors.green;
        if (ext == 'ppt' || ext == 'pptx') return Colors.deepOrange;
        return Colors.teal;
      case VaultMediaType.other:
        return Colors.blueGrey;
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'originalName': originalName,
      'encryptedFileName': encryptedFileName,
      'type': type.name,
      'fileSizeBytes': fileSizeBytes,
      'dateAdded': dateAdded.toIso8601String(),
      'dateModified': dateModified?.toIso8601String(),
      'durationSeconds': durationSeconds,
      'isDownloaded': isDownloaded,
      'albumId': albumId,
      'isFavorite': isFavorite,
      'notes': notes,
    };
  }

  factory VaultItem.fromJson(Map<String, dynamic> json) {
    VaultMediaType parsedType;
    final typeStr = json['type'] as String? ?? 'photo';
    switch (typeStr) {
      case 'video':
        parsedType = VaultMediaType.video;
        break;
      case 'document':
        parsedType = VaultMediaType.document;
        break;
      case 'audio':
        parsedType = VaultMediaType.audio;
        break;
      case 'other':
        parsedType = VaultMediaType.other;
        break;
      case 'photo':
      default:
        parsedType = VaultMediaType.photo;
    }

    return VaultItem(
      id: json['id'] as String,
      originalName: json['originalName'] as String,
      encryptedFileName: json['encryptedFileName'] as String,
      type: parsedType,
      fileSizeBytes: json['fileSizeBytes'] as int? ?? 0,
      dateAdded: DateTime.tryParse(json['dateAdded'] as String? ?? '') ?? DateTime.now(),
      dateModified: json['dateModified'] != null ? DateTime.tryParse(json['dateModified'] as String) : null,
      durationSeconds: json['durationSeconds'] as int?,
      isDownloaded: json['isDownloaded'] as bool? ?? false,
      albumId: json['albumId'] as String?,
      isFavorite: json['isFavorite'] as bool? ?? false,
      notes: json['notes'] as String?,
    );
  }

  VaultItem copyWith({
    String? id,
    String? originalName,
    String? encryptedFileName,
    VaultMediaType? type,
    int? fileSizeBytes,
    DateTime? dateAdded,
    DateTime? dateModified,
    int? durationSeconds,
    bool? isDownloaded,
    String? albumId,
    bool? isFavorite,
    String? notes,
  }) {
    return VaultItem(
      id: id ?? this.id,
      originalName: originalName ?? this.originalName,
      encryptedFileName: encryptedFileName ?? this.encryptedFileName,
      type: type ?? this.type,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      dateAdded: dateAdded ?? this.dateAdded,
      dateModified: dateModified ?? this.dateModified,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      isDownloaded: isDownloaded ?? this.isDownloaded,
      albumId: albumId ?? this.albumId,
      isFavorite: isFavorite ?? this.isFavorite,
      notes: notes ?? this.notes,
    );
  }
}
