import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/book_metadata.dart';
import '../services/storage_service.dart';
import 'dart:typed_data';

class BookListDrawer extends StatefulWidget {
  final Function(String bookId) onBookSelected;
  final Function() onAddNewBook;

  /// Session books for web (in-memory storage)
  final List<BookMetadata> sessionBooks;

  /// Session book bytes for web (in-memory storage)
  final Map<String, Uint8List> sessionBookBytes;

  const BookListDrawer({
    super.key,
    required this.onBookSelected,
    required this.onAddNewBook,
    this.sessionBooks = const [],
    this.sessionBookBytes = const {},
  });

  @override
  State<BookListDrawer> createState() => _BookListDrawerState();
}

class _BookListDrawerState extends State<BookListDrawer> {
  final StorageService _storageService = StorageService();
  List<BookMetadata> _books = [];
  bool _isLoading = false;
  DateTime? _lastLoadTime;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) {
      _loadBooks();
    }
  }

  // Method to refresh books list (can be called externally)
  void refreshBooks() {
    if (!_isLoading && !kIsWeb) {
      _loadBooks();
    }
  }

  Future<void> _loadBooks() async {
    if (_isLoading || kIsWeb) {
      return; // Prevent concurrent loads, skip on web
    }
    setState(() => _isLoading = true);
    try {
      final books = await _storageService.getAllBooks();
      if (mounted) {
        setState(() {
          _books = books;
          _isLoading = false;
          _lastLoadTime = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Get all books (from storage on native, from session on web)
  List<BookMetadata> get _allBooks {
    if (kIsWeb) {
      return widget.sessionBooks;
    }
    return _books;
  }

  Future<Uint8List?> _getCoverImage(String bookId) async {
    try {
      return await _storageService.getCoverImage(bookId);
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Reload books when drawer is opened (debounced - only if last load was more than 1 second ago)
    // Skip on web since we use session books
    if (!kIsWeb) {
      final now = DateTime.now();
      if (!_isLoading &&
          (_lastLoadTime == null ||
              now.difference(_lastLoadTime!).inSeconds > 1)) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isLoading) {
            _loadBooks();
          }
        });
      }
    }

    final books = _allBooks;

    return Drawer(
      child: Column(
        children: [
          // Header
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Meine Bücher',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  kIsWeb
                      ? 'Sitzungsbücher (nicht persistent)'
                      : 'Wähle ein Buch aus',
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
          // Book List
          Expanded(
            child: _isLoading && !kIsWeb
                ? const Center(child: CircularProgressIndicator())
                : books.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.book_outlined,
                            size: 64,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            kIsWeb
                                ? 'Noch keine Bücher geladen.\n\nKlicke unten um dein erstes Buch zu öffnen.'
                                : 'Keine Bücher gespeichert',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey[600]),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: books.length,
                    itemBuilder: (context, index) {
                      final book = books[index];
                      return _BookListItem(
                        book: book,
                        onTap: () {
                          widget.onBookSelected(book.id);
                          Navigator.of(context).pop();
                        },
                        getCoverImage: _getCoverImage,
                      );
                    },
                  ),
          ),
          // Add New Book Button
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(color: Colors.grey[800]!, width: 1),
              ),
            ),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  widget.onAddNewBook();
                },
                icon: const Icon(Icons.add),
                label: const Text('Neues Buch hinzufügen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BookListItem extends StatelessWidget {
  final BookMetadata book;
  final VoidCallback onTap;
  final Future<Uint8List?> Function(String) getCoverImage;

  const _BookListItem({
    required this.book,
    required this.onTap,
    required this.getCoverImage,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: FutureBuilder<Uint8List?>(
        future: getCoverImage(book.id),
        builder: (context, snapshot) {
          if (snapshot.hasData && snapshot.data != null) {
            return Image.memory(
              snapshot.data!,
              width: 50,
              height: 70,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) {
                return _buildPlaceholderCover();
              },
            );
          }
          return _buildPlaceholderCover();
        },
      ),
      title: Text(
        book.title,
        style: const TextStyle(fontWeight: FontWeight.bold),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: book.author != null
          ? Text(
              book.author!,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildPlaceholderCover() {
    // Platzhalter mit Initialen
    final initials = book.title.isNotEmpty
        ? book.title.substring(0, 1).toUpperCase()
        : '?';
    return Container(
      width: 50,
      height: 70,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
