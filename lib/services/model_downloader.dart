import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

class ModelDownloader {
  // Model download URL. Using a smaller alternative model that doesn't require authentication
  static const String modelUrl =
      'https://gemma-3n-lite-model.s3.us-east-1.amazonaws.com/gemma-3n-E2B-it-int4.task';
  static const String modelFileName = 'gemma-3n-E2B-it-int4.task';

  // Alternative: Original Gemma 3n model (requires Hugging Face authentication)
  static const String originalModelUrl =
      'https://gemma-3n-lite-model.s3.us-east-1.amazonaws.com/gemma-3n-E2B-it-int4.task';
  static const String originalModelFileName = 'gemma-3n-E2B-it-int4.task';

  /// Checks if internet connection is available
  static Future<bool> hasInternetConnection() async {
    try {
      print('[ModelDownloader] Checking internet connection...');
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 5);
      dio.options.receiveTimeout = const Duration(seconds: 5);

      // Try to reach a simple endpoint
      final response = await dio.get('https://www.google.com');
      final hasConnection = response.statusCode == 200;
      print('[ModelDownloader] Internet connection: $hasConnection');
      return hasConnection;
    } catch (e) {
      print('[ModelDownloader] No internet connection: $e');
      return false;
    }
  }

  /// Returns the local file path where the model should be stored.
  static Future<String> getModelFilePath() async {
    final dir = await getApplicationDocumentsDirectory();
    return p.join(dir.path, modelFileName);
  }

  /// Checks if the model file exists in app directory and is complete.
  /// Returns true if model is complete, false if it needs to be copied/downloaded.
  /// This method does NOT require any permissions as it only checks app's private storage.
  static Future<bool> modelExistsInAppDirectory() async {
    print('[ModelDownloader] 🔍 Checking if model exists in app directory...');

    final path = await getModelFilePath();
    final file = File(path);

    print('[ModelDownloader] 📂 Model path: $path');

    if (await file.exists()) {
      print(
          '[ModelDownloader] ✅ Model file exists in app directory, checking size...');
      try {
        final localSize = await file.length();
        print(
            '[ModelDownloader] 📏 Local model size: $localSize bytes (${(localSize / 1024 / 1024).toStringAsFixed(1)} MB)');

        // Check if file is reasonably large (at least 1GB for the model)
        final isReasonableSize = localSize > 1000000000; // 1GB minimum

        if (isReasonableSize) {
          print(
              '[ModelDownloader] ✅ Model in app directory is complete and ready!');
          return true;
        } else {
          print(
              '[ModelDownloader] ⚠️ Model file too small, deleting and will search elsewhere...');
          await file.delete();
          return false;
        }
      } catch (e) {
        print('[ModelDownloader] ❌ Error checking model size: $e');
        // Delete potentially corrupted file
        if (await file.exists()) {
          await file.delete();
          print(
              '[ModelDownloader] 🗑️ Deleted potentially corrupted model file');
        }
        return false;
      }
    }

    print('[ModelDownloader] ❌ Model file does not exist in app directory');
    return false;
  }

  /// Legacy method - kept for compatibility
  /// Checks if the model file exists locally and matches the expected size.
  /// Returns true if model is complete, false if it needs to be copied/downloaded.
  static Future<bool> modelIsComplete() async {
    return await modelExistsInAppDirectory();
  }

  /// NEW: Permission-free search for model file in external folders
  /// This method attempts to find the model WITHOUT requesting storage permissions first
  /// Returns the path of the model file if found, null otherwise
  /// This is used to determine IF we need to request permissions for copying
  static Future<String?> findModelInExternalFoldersNoPermission() async {
    print(
        '[ModelDownloader] 🔍 Searching external folders WITHOUT permissions...');

    // The 10 most common locations where users place downloaded models
    final externalCandidates = [
      // Downloads folders (most common)
      '/storage/emulated/0/Download/gemma-3n-E2B-it-int4.task',
      '/storage/emulated/0/Downloads/gemma-3n-E2B-it-int4.task',
      '/sdcard/Download/gemma-3n-E2B-it-int4.task',
      '/sdcard/Downloads/gemma-3n-E2B-it-int4.task',
      // Documents folders
      '/storage/emulated/0/Documents/gemma-3n-E2B-it-int4.task',
      '/sdcard/Documents/gemma-3n-E2B-it-int4.task',
      // Root storage
      '/storage/emulated/0/gemma-3n-E2B-it-int4.task',
      '/sdcard/gemma-3n-E2B-it-int4.task',
      // App external directories (accessible without special permissions)
      '/storage/emulated/0/Android/data/com.example.myapp/files/gemma-3n-E2B-it-int4.task',
      '/sdcard/Android/data/com.example.myapp/files/gemma-3n-E2B-it-int4.task',
    ];

    print(
        '[ModelDownloader] 🔍 Searching ${externalCandidates.length} external locations...');

    for (int i = 0; i < externalCandidates.length; i++) {
      final candidate = externalCandidates[i];
      print(
          '[ModelDownloader] 📁 [${i + 1}/${externalCandidates.length}] Checking: $candidate');

      try {
        final file = File(candidate);

        // Try to check if file exists (this might fail due to permissions, but we try anyway)
        if (await file.exists()) {
          final fileSize = await file.length();
          final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
          print('[ModelDownloader] ✅ Found file: $candidate');
          print(
              '[ModelDownloader] 📏 File size: $fileSize bytes ($fileSizeMB MB)');

          // Check if file is reasonably large (at least 1GB for the model)
          if (fileSize > 1000000000) {
            // 1GB minimum
            print(
                '[ModelDownloader] ✅ File size is valid (>1GB), model found in external storage!');
            return candidate;
          } else {
            print(
                '[ModelDownloader] ⚠️ File too small ($fileSizeMB MB), continuing search...');
          }
        } else {
          print('[ModelDownloader] ❌ Not found: $candidate');
        }
      } catch (e) {
        // This is expected for some paths that require permissions
        print(
            '[ModelDownloader] 🔒 Cannot access: $candidate (may require permissions)');
        continue;
      }
    }

    print(
        '[ModelDownloader] ❌ Model not found in any accessible external location');
    return null;
  }

  /// Legacy method - kept for compatibility but now uses permission-based search
  /// Comprehensive search for model file in all possible locations
  /// Returns the path of the complete model file if found, null otherwise
  static Future<String?> findModelInAllLocations() async {
    print(
        '[ModelDownloader] 🔍 Starting comprehensive model search WITH permissions...');

    final candidates = [
      // Downloads folders (most common)
      '/storage/emulated/0/Download/gemma-3n-E2B-it-int4.task',
      '/storage/emulated/0/Downloads/gemma-3n-E2B-it-int4.task',
      '/sdcard/Download/gemma-3n-E2B-it-int4.task',
      '/sdcard/Downloads/gemma-3n-E2B-it-int4.task',
      // Documents folders
      '/storage/emulated/0/Documents/gemma-3n-E2B-it-int4.task',
      '/sdcard/Documents/gemma-3n-E2B-it-int4.task',
      // Root storage
      '/storage/emulated/0/gemma-3n-E2B-it-int4.task',
      '/sdcard/gemma-3n-E2B-it-int4.task',
      // App external directories
      '/storage/emulated/0/Android/data/com.example.myapp/files/gemma-3n-E2B-it-int4.task',
      '/sdcard/Android/data/com.example.myapp/files/gemma-3n-E2B-it-int4.task',
    ];

    print('[ModelDownloader] 🔍 Searching ${candidates.length} locations...');

    for (int i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      print(
          '[ModelDownloader] 📁 [${i + 1}/${candidates.length}] Checking: $candidate');

      final file = File(candidate);
      if (await file.exists()) {
        final fileSize = await file.length();
        final fileSizeMB = (fileSize / 1024 / 1024).toStringAsFixed(1);
        print('[ModelDownloader] ✅ Found file: $candidate');
        print(
            '[ModelDownloader] 📏 File size: $fileSize bytes ($fileSizeMB MB)');

        // Check if file is reasonably large (at least 1GB for the model)
        if (fileSize > 1000000000) {
          // 1GB minimum
          print('[ModelDownloader] ✅ File size is valid (>1GB), model found!');
          return candidate;
        } else {
          print(
              '[ModelDownloader] ⚠️ File too small ($fileSizeMB MB), continuing search...');
        }
      } else {
        print('[ModelDownloader] ❌ Not found: $candidate');
      }
    }

    print(
        '[ModelDownloader] ❌ Model not found in any of the ${candidates.length} locations');
    return null;
  }

  /// NEW: Request storage permission specifically for copying model
  /// This method is ONLY called when we've already found a model in external storage
  /// Returns true if permission granted, false otherwise
  static Future<bool> requestPermissionForModelCopy() async {
    print(
        '[ModelDownloader] 🔐 REQUESTING STORAGE PERMISSION TO COPY FOUND MODEL...');
    print(
        '[ModelDownloader] � This permission is ONLY requested because model was found externally');

    try {
      // CORRECT ORDER: Try storage permission first (most common)
      print('[ModelDownloader] 📱 Requesting STORAGE permission...');
      final storageStatus = await Permission.storage.request();
      if (storageStatus.isGranted) {
        print('[ModelDownloader] ✅ STORAGE permission granted for model copy');
        return true;
      }

      print(
          '[ModelDownloader] ❌ Storage permission denied, trying manage external storage...');

      // Try manage external storage for Android 11+ (API 30+)
      print(
          '[ModelDownloader] 📱 Requesting MANAGE EXTERNAL STORAGE permission...');
      final manageStatus = await Permission.manageExternalStorage.request();
      if (manageStatus.isGranted) {
        print(
            '[ModelDownloader] ✅ MANAGE EXTERNAL STORAGE permission granted for model copy');
        return true;
      }

      print('[ModelDownloader] ❌ ALL storage permission requests DENIED');
      print('[ModelDownloader] 📥 Will fall back to download instead');
      return false;
    } catch (e) {
      print('[ModelDownloader] ❌ ERROR requesting storage permission: $e');
      return false;
    }
  }

  /// Copies model from source path to app directory with progress tracking
  static Future<bool> copyModelToAppDirectory(String sourcePath) async {
    try {
      print('[ModelDownloader] 📋 Starting model copy operation...');
      print('[ModelDownloader] 📂 Source: $sourcePath');

      final destPath = await getModelFilePath();
      print('[ModelDownloader] 📂 Destination: $destPath');

      final sourceFile = File(sourcePath);
      final destFile = File(destPath);

      // Create destination directory if needed
      final destDir = destFile.parent;
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
        print('[ModelDownloader] 📁 Created destination directory');
      }

      // Delete existing incomplete file if any
      if (await destFile.exists()) {
        await destFile.delete();
        print('[ModelDownloader] 🗑️ Deleted existing incomplete file');
      }

      final sourceSize = await sourceFile.length();
      print(
          '[ModelDownloader] 📏 Source file size: $sourceSize bytes (${(sourceSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      // Copy the file
      print('[ModelDownloader] 📋 Copying file...');
      await sourceFile.copy(destPath);

      // Verify copy
      final copiedSize = await destFile.length();
      print(
          '[ModelDownloader] 📏 Copied file size: $copiedSize bytes (${(copiedSize / 1024 / 1024).toStringAsFixed(1)} MB)');

      if (copiedSize == sourceSize) {
        print('[ModelDownloader] ✅ Model copy completed successfully!');
        return true;
      } else {
        print('[ModelDownloader] ❌ Copy verification failed: size mismatch');
        await destFile.delete();
        return false;
      }
    } catch (e) {
      print('[ModelDownloader] ❌ Copy failed: $e');
      return false;
    }
  }

  /// Tries to copy the model from /sdcard/Android/data or /sdcard/Download to app storage if present.
  static Future<bool> _tryCopyFromSdcardOrDownload(String destPath) async {
    final candidates = [
      '/storage/emulated/0/Android/data/com.example.myapp/files/gemma-3n-E2B-it-int4.task',
      '/sdcard/Android/data/com.example.myapp/files/gemma-3n-E2B-it-int4.task',
      '/sdcard/Download/gemma-3n-E2B-it-int4.task',
    ];
    for (final candidate in candidates) {
      final file = File(candidate);
      if (await file.exists()) {
        print(
            '[ModelDownloader] Found model at $candidate, attempting to copy to $destPath');
        // Request appropriate permissions based on location and Android version
        if (candidate.contains('/Download/')) {
          // For Downloads folder, we need storage permissions
          bool hasPermission = false;

          // Try different permission strategies for different Android versions
          try {
            // For Android 13+ (API 33+), try photos permission first
            final photosStatus = await Permission.photos.request();
            if (photosStatus.isGranted) {
              hasPermission = true;
              print('[ModelDownloader] Photos permission granted');
            } else {
              // Fallback to storage permission for older Android versions
              final storageStatus = await Permission.storage.request();
              if (storageStatus.isGranted) {
                hasPermission = true;
                print('[ModelDownloader] Storage permission granted');
              } else {
                // Try manage external storage as last resort
                final manageStatus =
                    await Permission.manageExternalStorage.request();
                if (manageStatus.isGranted) {
                  hasPermission = true;
                  print(
                      '[ModelDownloader] Manage external storage permission granted');
                }
              }
            }
          } catch (e) {
            print('[ModelDownloader] Error requesting permissions: $e');
          }

          if (!hasPermission) {
            print(
                '[ModelDownloader] Storage permissions not granted. Cannot copy model file from Downloads.');
            continue;
          }
        }
        try {
          await file.copy(destPath);
          print('[ModelDownloader] Copy succeeded from $candidate');
          return true;
        } catch (e) {
          print('[ModelDownloader] Copy failed from $candidate: $e');
        }
      } else {
        print('[ModelDownloader] Model not found at $candidate');
      }
    }
    return false;
  }

  /// Gets the expected file size from the server using a HEAD request.
  static Future<int?> getRemoteFileSize() async {
    try {
      print('[ModelDownloader] Getting remote file size...');
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      dio.options.receiveTimeout = const Duration(seconds: 10);

      final response = await dio.head(modelUrl);
      final contentLength = response.headers.value('content-length');

      if (contentLength != null) {
        final size = int.tryParse(contentLength);
        print('[ModelDownloader] Remote file size: $size bytes');
        return size;
      } else {
        print('[ModelDownloader] No content-length header found');
        return null;
      }
    } catch (e) {
      print('[ModelDownloader] Error getting remote file size: $e');
      return null;
    }
  }

  /// Downloads the model file, reporting progress (0.0 to 1.0) via [onProgress].
  /// If a partial file exists, resumes download if possible.
  /// NO PERMISSIONS REQUIRED - Downloads directly to app's private storage
  static Future<void> downloadModel(
      {required void Function(double) onProgress}) async {
    print('[ModelDownloader] 📥 Starting model download to app directory...');

    try {
      final path = await getModelFilePath();
      final file = File(path);
      print('[ModelDownloader] 📂 Download path: $path');

      // Create directory if it doesn't exist
      final directory = file.parent;
      if (!await directory.exists()) {
        await directory.create(recursive: true);
        print('[ModelDownloader] 📁 Created directory: ${directory.path}');
      }

      final dio = Dio();
      dio.options.connectTimeout = const Duration(minutes: 5);
      dio.options.receiveTimeout = const Duration(minutes: 30);

      int? expectedSize = await getRemoteFileSize();
      int downloaded = 0;

      if (await file.exists()) {
        downloaded = await file.length();
        print('[ModelDownloader] 📄 Existing file size: $downloaded bytes');

        // If file is complete, skip download
        if (expectedSize != null && downloaded == expectedSize) {
          print('[ModelDownloader] ✅ File already complete, skipping download');
          onProgress(1.0);
          return;
        }
      }

      print('[ModelDownloader] 📥 Starting download from byte: $downloaded');

      await dio.download(
        modelUrl,
        path,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            final progress = received / total;
            print(
                '[ModelDownloader] 📊 Progress: ${(progress * 100).toStringAsFixed(1)}%');
            onProgress(progress);
          } else {
            // If total is unknown, calculate based on expected size
            if (expectedSize != null) {
              final progress = (downloaded + received) / expectedSize;
              onProgress(progress.clamp(0.0, 1.0));
            }
          }
        },
        deleteOnError: true,
        options: Options(
          headers: downloaded > 0 ? {'range': 'bytes=$downloaded-'} : null,
        ),
      );

      print('[ModelDownloader] ✅ Download completed');

      // Verify file size after download
      final finalSize = await file.length();
      print('[ModelDownloader] 📏 Final file size: $finalSize bytes');

      if (expectedSize != null && finalSize != expectedSize) {
        print(
            '[ModelDownloader] ❌ File size mismatch. Expected: $expectedSize, Got: $finalSize');
        if (await file.exists()) {
          await file.delete();
        }
        throw Exception(
            'Downloaded file is incomplete or corrupt. Expected: $expectedSize bytes, Got: $finalSize bytes');
      }

      print('[ModelDownloader] ✅ Download verification successful');
    } catch (e) {
      print('[ModelDownloader] ❌ Download error: $e');

      // Clean up partial file on error
      final path = await getModelFilePath();
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        print('[ModelDownloader] 🗑️ Cleaned up partial file');
      }

      rethrow;
    }
  }
}
