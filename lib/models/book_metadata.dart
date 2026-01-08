import 'dart:typed_data';
import 'dart:convert';

class BookMetadata {
  final String id;
  final String title;
  final String? author;
  final String filePath; // Lokaler Pfad zur gespeicherten Datei
  final Uint8List? coverImage; // Cover-Bild
  final int totalWords;
  final int lastReadIndex; // Fortschritt
  final DateTime lastOpened;
  final String fileType; // 'epub', 'pdf', 'txt'

  BookMetadata({
    required this.id,
    required this.title,
    this.author,
    required this.filePath,
    this.coverImage,
    required this.totalWords,
    this.lastReadIndex = 0,
    required this.lastOpened,
    required this.fileType,
  });

  // Serialisierung für JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'filePath': filePath,
      'coverImage': coverImage != null
          ? base64Encode(coverImage!)
          : null,
      'totalWords': totalWords,
      'lastReadIndex': lastReadIndex,
      'lastOpened': lastOpened.toIso8601String(),
      'fileType': fileType,
    };
  }

  // Deserialisierung aus JSON
  factory BookMetadata.fromJson(Map<String, dynamic> json) {
    return BookMetadata(
      id: json['id'] as String,
      title: json['title'] as String,
      author: json['author'] as String?,
      filePath: json['filePath'] as String,
      coverImage: json['coverImage'] != null
          ? base64Decode(json['coverImage'] as String)
          : null,
      totalWords: json['totalWords'] as int,
      lastReadIndex: json['lastReadIndex'] as int? ?? 0,
      lastOpened: DateTime.parse(json['lastOpened'] as String),
      fileType: json['fileType'] as String,
    );
  }

  // Kopie mit aktualisierten Feldern
  BookMetadata copyWith({
    String? id,
    String? title,
    String? author,
    String? filePath,
    Uint8List? coverImage,
    int? totalWords,
    int? lastReadIndex,
    DateTime? lastOpened,
    String? fileType,
  }) {
    return BookMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      coverImage: coverImage ?? this.coverImage,
      totalWords: totalWords ?? this.totalWords,
      lastReadIndex: lastReadIndex ?? this.lastReadIndex,
      lastOpened: lastOpened ?? this.lastOpened,
      fileType: fileType ?? this.fileType,
    );
  }
}

