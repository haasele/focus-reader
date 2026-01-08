import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/book_metadata.dart';

class StorageService {
  static const String _bookIdsKey = 'saved_book_ids';
  static const String _booksDirName = 'books';

  // Get books directory
  Future<Directory> _getBooksDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final booksDir = Directory('${appDocDir.path}/$_booksDirName');
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
    return booksDir;
  }

  // Get book directory for a specific book
  Future<Directory> _getBookDirectory(String bookId) async {
    final booksDir = await _getBooksDirectory();
    final bookDir = Directory('${booksDir.path}/$bookId');
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }
    return bookDir;
  }

  // Save book file and metadata
  Future<void> saveBook({
    required String bookId,
    required Uint8List fileBytes,
    required String fileName,
    required BookMetadata metadata,
    Uint8List? coverImage,
  }) async {
    final bookDir = await _getBookDirectory(bookId);

    // Save book file
    final bookFile = File('${bookDir.path}/$fileName');
    await bookFile.writeAsBytes(fileBytes);

    // Save metadata
    final metadataFile = File('${bookDir.path}/metadata.json');
    await metadataFile.writeAsString(jsonEncode(metadata.toJson()));

    // Save cover image if provided
    if (coverImage != null) {
      final coverFile = File('${bookDir.path}/cover.png');
      await coverFile.writeAsBytes(coverImage);
    }

    // Add book ID to list
    final prefs = await SharedPreferences.getInstance();
    final bookIds = prefs.getStringList(_bookIdsKey) ?? [];
    if (!bookIds.contains(bookId)) {
      bookIds.add(bookId);
      await prefs.setStringList(_bookIdsKey, bookIds);
    }
  }

  // Load book file
  Future<Uint8List> loadBook(String bookId) async {
    final bookDir = await _getBookDirectory(bookId);
    final metadata = await getBookMetadata(bookId);
    final fileName = metadata.filePath.split('/').last;
    final bookFile = File('${bookDir.path}/$fileName');
    return await bookFile.readAsBytes();
  }

  // Get book metadata
  Future<BookMetadata> getBookMetadata(String bookId) async {
    final bookDir = await _getBookDirectory(bookId);
    final metadataFile = File('${bookDir.path}/metadata.json');
    if (!await metadataFile.exists()) {
      throw Exception('Metadata file not found for book: $bookId');
    }
    final jsonString = await metadataFile.readAsString();
    final json = jsonDecode(jsonString) as Map<String, dynamic>;
    return BookMetadata.fromJson(json);
  }

  // Get all saved books
  Future<List<BookMetadata>> getAllBooks() async {
    final prefs = await SharedPreferences.getInstance();
    final bookIds = prefs.getStringList(_bookIdsKey) ?? [];
    final books = <BookMetadata>[];

    for (final bookId in bookIds) {
      try {
        final metadata = await getBookMetadata(bookId);
        books.add(metadata);
      } catch (e) {
        // Skip books with missing metadata
        continue;
      }
    }

    // Sort by lastOpened (most recent first)
    books.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    return books;
  }

  // Delete book
  Future<void> deleteBook(String bookId) async {
    final bookDir = await _getBookDirectory(bookId);
    if (await bookDir.exists()) {
      await bookDir.delete(recursive: true);
    }

    // Remove from list
    final prefs = await SharedPreferences.getInstance();
    final bookIds = prefs.getStringList(_bookIdsKey) ?? [];
    bookIds.remove(bookId);
    await prefs.setStringList(_bookIdsKey, bookIds);
  }

  // Update reading progress
  Future<void> updateProgress(String bookId, int currentIndex) async {
    final metadata = await getBookMetadata(bookId);
    final updatedMetadata = metadata.copyWith(
      lastReadIndex: currentIndex,
      lastOpened: DateTime.now(),
    );

    final bookDir = await _getBookDirectory(bookId);
    final metadataFile = File('${bookDir.path}/metadata.json');
    await metadataFile.writeAsString(jsonEncode(updatedMetadata.toJson()));
  }

  // Get cover image
  Future<Uint8List?> getCoverImage(String bookId) async {
    final bookDir = await _getBookDirectory(bookId);
    final coverFile = File('${bookDir.path}/cover.png');
    if (await coverFile.exists()) {
      return await coverFile.readAsBytes();
    }
    return null;
  }
}

