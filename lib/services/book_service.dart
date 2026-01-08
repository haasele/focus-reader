import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'dart:convert';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class BookService {
  // Extract cover image from EPUB
  static Future<Uint8List?> extractCoverFromEpub(Uint8List bytes) async {
    try {
      return await _extractCoverFromEpubManually(bytes);
    } catch (e) {
      return null;
    }
  }

  // Manual EPUB cover extraction
  static Future<Uint8List?> _extractCoverFromEpubManually(
      Uint8List bytes) async {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      
      // Find content.opf to get cover reference
      ArchiveFile? opfFile;
      String? coverPath;
      
      for (var file in archive.files) {
        if (file.name.toLowerCase().endsWith('content.opf')) {
          opfFile = file;
          break;
        }
      }
      
      if (opfFile != null && opfFile.content != null) {
        final opfContent = utf8.decode(opfFile.content as List<int>);
        // Find cover image reference in OPF
        // Try meta tag with name="cover"
        final coverMatch1 = RegExp(
          r'<meta[^>]*name="cover"[^>]*content="([^"]+)"',
          caseSensitive: false,
        ).firstMatch(opfContent);
        
        final coverMatch2 = RegExp(
          r"<meta[^>]*name='cover'[^>]*content='([^']+)'",
          caseSensitive: false,
        ).firstMatch(opfContent);
        
        if (coverMatch1 != null) {
          coverPath = coverMatch1.group(1);
        } else if (coverMatch2 != null) {
          coverPath = coverMatch2.group(1);
        } else {
          // Try to find item with id="cover-image" or similar
          final itemMatch1 = RegExp(
            r'<item[^>]*id="cover-image"[^>]*href="([^"]+)"',
            caseSensitive: false,
          ).firstMatch(opfContent);
          
          final itemMatch2 = RegExp(
            r"<item[^>]*id='cover-image'[^>]*href='([^']+)'",
            caseSensitive: false,
          ).firstMatch(opfContent);
          
          if (itemMatch1 != null) {
            coverPath = itemMatch1.group(1);
          } else if (itemMatch2 != null) {
            coverPath = itemMatch2.group(1);
          }
        }
      }
      
      // If we found a cover path, extract it
      if (coverPath != null) {
        // Normalize path (handle relative paths)
        final normalizedPath = coverPath.replaceAll('\\', '/');
        for (var file in archive.files) {
          final fileName = file.name.replaceAll('\\', '/');
          if (fileName.toLowerCase().contains(normalizedPath.toLowerCase()) ||
              fileName.toLowerCase().endsWith(normalizedPath.toLowerCase())) {
            if (file.content != null) {
              final ext = fileName.toLowerCase();
              if (ext.endsWith('.jpg') ||
                  ext.endsWith('.jpeg') ||
                  ext.endsWith('.png') ||
                  ext.endsWith('.gif')) {
                return Uint8List.fromList(file.content as List<int>);
              }
            }
          }
        }
      }
      
      // Fallback: Look for common cover image names
      final commonNames = ['cover.jpg', 'cover.png', 'cover.jpeg', 'cover.gif'];
      for (var name in commonNames) {
        for (var file in archive.files) {
          if (file.name.toLowerCase().endsWith(name)) {
            if (file.content != null) {
              return Uint8List.fromList(file.content as List<int>);
            }
          }
        }
      }
      
      return null;
    } catch (e) {
      return null;
    }
  }

  // Extract cover from PDF (first page as image)
  static Future<Uint8List?> extractCoverFromPdf(Uint8List bytes) async {
    try {
      final document = PdfDocument(inputBytes: bytes);
      if (document.pages.count > 0) {
        // Render first page as image
        // Note: This requires additional setup with dart:ui
        // For now, return null and use placeholder
        document.dispose();
        return null;
      }
      document.dispose();
    } catch (e) {
      return null;
    }
    return null;
  }

  // Generate placeholder cover with initials
  static Uint8List? generatePlaceholderCover(String title) {
    // Placeholder generation would require canvas rendering
    // For now, return null - the UI will handle placeholder display
    return null;
  }
}

