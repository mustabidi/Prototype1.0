import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  Future<File> _compressImage(File file) async {
    final targetPath = file.absolute.path.replaceAll(RegExp(r'\.\w+$'), '_${DateTime.now().millisecondsSinceEpoch}.jpg');
    final result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70, // Compresses file significantly
      format: CompressFormat.jpeg,
    );
    return result != null ? File(result.path) : file;
  }

  /// Uploads multiple images for a given post.
  /// Storage path: posts/{userId}/{postId}/image_{index}.jpg
  Future<List<String>> uploadPostImages({
    required String userId,
    required String postId,
    required List<File> imageFiles,
  }) async {
    List<String> downloadUrls = [];

    for (int i = 0; i < imageFiles.length; i++) {
      // Compress file first
      final file = await _compressImage(imageFiles[i]);
      
      final path = 'posts/$userId/$postId/image_$i.jpg';
      final ref = _storage.ref().child(path);

      // Upload with metadata indicating it's a jpeg
      final uploadTask = ref.putFile(
        file,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      final snapshot = await uploadTask;
      final url = await snapshot.ref.getDownloadURL();
      downloadUrls.add(url);
    }

    return downloadUrls;
  }

  /// Uploads a single logo for a business.
  /// Storage path: businesses/{userId}/{businessId}/logo.jpg
  Future<String> uploadBusinessLogo({
    required String userId,
    required String businessId,
    required File imageFile,
  }) async {
    final compressedFile = await _compressImage(imageFile);
    
    final path = 'businesses/$userId/$businessId/logo.jpg';
    final ref = _storage.ref().child(path);

    final uploadTask = ref.putFile(
      compressedFile,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final snapshot = await uploadTask;
    return await snapshot.ref.getDownloadURL();
  }
}
