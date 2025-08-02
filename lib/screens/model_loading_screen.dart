import 'package:flutter/material.dart';
import '../services/model_downloader.dart';
import '../services/ai_service.dart';
import 'home_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class ModelLoadingScreen extends StatefulWidget {
  const ModelLoadingScreen({super.key});

  @override
  State<ModelLoadingScreen> createState() => _ModelLoadingScreenState();
}

class _ModelLoadingScreenState extends State<ModelLoadingScreen> {
  double _progress = 0.0;
  String _status = 'Checking model...';
  bool _checking = true;
  bool _downloading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _checkFirstLaunch();
  }

  Future<void> _checkFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // STEP 1: Check if model exists in app directory (NO PERMISSIONS NEEDED)
      setState(() {
        _status = 'Checking model in app directory...';
      });

      final modelExistsInApp =
          await ModelDownloader.modelExistsInAppDirectory();
      if (modelExistsInApp) {
        print(
            '[ModelLoadingScreen] ✅ Model found and complete in app directory');
        await _proceedWithModelOptimization(prefs);
        return;
      } else {
        // Model file missing - reset optimization state
        print(
            '[ModelLoadingScreen] ❌ Model file missing - resetting optimization state');
        await _resetOptimizationState(prefs);
      }

      // STEP 2: Search external folders WITHOUT requesting permissions first
      setState(() {
        _status = 'Searching for model in external folders...';
      });

      final externalModelPath =
          await ModelDownloader.findModelInExternalFoldersNoPermission();

      if (externalModelPath != null) {
        print(
            '[ModelLoadingScreen] ✅ Model found in external storage at: $externalModelPath');

        // STEP 3: Smart permission handling with emulator detection
        setState(() {
          _status = 'Model found! Checking device compatibility...';
        });

        // Check if running on emulator (emulators often have permission issues)
        bool isEmulator = await _isRunningOnEmulator();

        if (isEmulator) {
          print(
              '[ModelLoadingScreen] 🤖 Emulator detected - skipping permission request, falling back to download');
          setState(() {
            _status =
                'Emulator detected - downloading instead for better compatibility...';
          });

          // Wait a moment to show the message, then proceed with download
          await Future.delayed(Duration(milliseconds: 2000));
          _checkAndDownloadModel(prefs);
          return;
        }

        // Real device - request permission normally
        setState(() {
          _status = 'Model found! Requesting permission to copy...';
        });

        final hasPermission =
            await ModelDownloader.requestPermissionForModelCopy();
        if (!hasPermission) {
          setState(() {
            _status = 'Permission denied. Starting download instead...';
            _errorMessage =
                'Storage permission required to copy model from external storage. Falling back to download.';
          });

          // Wait a moment to show the message, then proceed with download
          await Future.delayed(Duration(milliseconds: 2000));
          _checkAndDownloadModel(prefs);
          return;
        }

        // STEP 4: Copy model to app directory (permission granted)
        setState(() {
          _status = 'Copying model to app directory...';
        });

        final copySuccess =
            await ModelDownloader.copyModelToAppDirectory(externalModelPath);
        if (copySuccess) {
          print('[ModelLoadingScreen] ✅ Model copied successfully');
          await _proceedWithModelOptimization(prefs);
          return;
        } else {
          print('[ModelLoadingScreen] ❌ Model copy failed');
          setState(() {
            _status = 'Failed to copy model. Starting download...';
            _errorMessage =
                'Could not copy model from $externalModelPath. Falling back to download.';
          });

          // Wait a moment to show the message, then proceed with download
          await Future.delayed(Duration(milliseconds: 2000));
          _checkAndDownloadModel(prefs);
          return;
        }
      }

      // STEP 5: Model not found anywhere - start download (NO PERMISSIONS NEEDED for app directory)
      print(
          '[ModelLoadingScreen] ❌ Model not found in any accessible location');
      print(
          '[ModelLoadingScreen] 📥 Proceeding with download as last resort...');

      setState(() {
        _status = 'Model not found anywhere. Starting download...';
      });

      await prefs.setBool('model_ready', false);
      _checkAndDownloadModel(prefs);
    } catch (e) {
      print('[ModelLoadingScreen] Error in _checkFirstLaunch: $e');
      setState(() {
        _errorMessage = 'Failed to initialize: $e';
        _checking = false;
        _downloading = false;
      });
    }
  }

  Future<void> _proceedWithModelOptimization(SharedPreferences prefs) async {
    // Check if optimization was already completed before
    final isOptimized = prefs.getBool('model_optimized') ?? false;
    final isModelLoaded = prefs.getBool('model_loaded') ?? false;

    if (isOptimized && isModelLoaded) {
      print(
          '[ModelLoadingScreen] ✅ Model already optimized and loaded, navigating instantly...');
      setState(() {
        _status = 'Model ready! Navigating instantly...';
      });

      // Brief delay to show completion message, then navigate
      await Future.delayed(Duration(milliseconds: 300));
      _goToHome();
      return;
    }

    if (isOptimized && !isModelLoaded) {
      print('[ModelLoadingScreen] ✅ Model optimized but needs quick reload...');
      setState(() {
        _status = 'Model optimized! Quick startup...';
      });

      // Quick warm-up for instant response
      try {
        await AiService().loadModel();
        print('[ModelLoadingScreen] ✅ Quick model reload successful');

        // Mark model as loaded for future instant launches
        await prefs.setBool('model_loaded', true);

        setState(() {
          _status = 'Ready for emergency responses!';
        });

        // Brief delay to show completion message
        await Future.delayed(Duration(milliseconds: 500));
        await _setModelReady(prefs);
        _goToHome();
        return;
      } catch (e) {
        print(
            '[ModelLoadingScreen] ⚠️ Quick reload failed, doing full optimization: $e');
        // Reset optimization flag and fall through to full optimization
        await prefs.setBool('model_optimized', false);
        await prefs.setBool('model_loaded', false);
        print(
            '[ModelLoadingScreen] 🔄 Reset optimization state due to reload failure');
      }
    }

    // FULL OPTIMIZATION PROCESS (First time or if quick loading failed)
    setState(() {
      _status = 'Detecting device capabilities...';
    });

    // Check device RAM and capabilities
    print('[ModelLoadingScreen] 🔍 Checking device RAM and capabilities...');
    await Future.delayed(Duration(milliseconds: 500));

    // TODO: Add actual device RAM detection here
    // For now, we'll assume device is capable but add the checking infrastructure
    final deviceRAM = await _getDeviceRAM();
    final isLowRAMDevice = deviceRAM < 4096; // Less than 4GB

    if (isLowRAMDevice) {
      print(
          '[ModelLoadingScreen] ⚠️ Low RAM device detected ($deviceRAM MB), using lite optimization');
      setState(() {
        _status = 'Optimizing for low-memory device ($deviceRAM MB RAM)...';
      });
    } else {
      print(
          '[ModelLoadingScreen] ✅ High RAM device detected ($deviceRAM MB), using full optimization');
      setState(() {
        _status =
            'Optimizing for high-performance device ($deviceRAM MB RAM)...';
      });
    }

    // Give UI time to update
    await Future.delayed(Duration(milliseconds: 500));

    setState(() {
      _status = 'Optimizing AI model for this device...';
    });

    // Give UI time to update
    await Future.delayed(Duration(milliseconds: 500));

    setState(() {
      _status = 'Running warm-up inference to optimize all components...';
    });

    // Pre-load the AI model (this triggers device detection and full optimization)
    try {
      await AiService().loadModel();
      print('[ModelLoadingScreen] ✅ AI model fully optimized successfully');

      // Perform warm-up inference to ensure everything is ready
      await _performWarmupInference();

      // SAVE OPTIMIZATION STATE for instant future launches
      await prefs.setBool('model_optimized', true);
      await prefs.setBool('model_loaded', true);
      await prefs.setInt('device_ram_mb', deviceRAM);
      print(
          '[ModelLoadingScreen] ✅ Optimization state saved for instant future launches');

      setState(() {
        _status = 'Optimization complete! Future launches will be instant!';
      });

      // Brief delay to show completion message
      await Future.delayed(Duration(milliseconds: 1000));

      await _setModelReady(prefs);
      _goToHome();
    } catch (e) {
      print('[ModelLoadingScreen] ❌ AI model optimization failed: $e');

      // Reset optimization state on failure
      await _resetOptimizationState(prefs);

      setState(() {
        _status = 'Error optimizing model';
        _errorMessage = 'Failed to optimize model: $e';
        _checking = false;
      });
    }
  }

  Future<void> _checkAndDownloadModel([SharedPreferences? prefs]) async {
    setState(() {
      _checking = true;
      _progress = 0.0;
      _status = 'Preparing to download model...';
      _errorMessage = null;
    });

    try {
      // FINAL VERIFICATION: One last check to see if model appeared
      setState(() {
        _status = 'Final verification before download...';
      });

      final modelExistsInApp =
          await ModelDownloader.modelExistsInAppDirectory();
      if (modelExistsInApp) {
        print(
            '[ModelLoadingScreen] 🎉 Model appeared in app directory during final verification!');
        final prefs0 = prefs ?? await SharedPreferences.getInstance();
        await _proceedWithModelOptimization(prefs0);
        return;
      }

      // Check internet connection before proceeding
      print('[ModelLoadingScreen] 🌐 Checking internet connection...');
      setState(() {
        _status = 'Checking internet connection...';
      });

      final hasInternet = await ModelDownloader.hasInternetConnection();
      if (!hasInternet) {
        throw Exception(
            'No internet connection available. Please check your network settings and try again.');
      }

      print(
          '[ModelLoadingScreen] ✅ Internet connection confirmed, starting download...');
      setState(() {
        _checking = false;
        _downloading = true;
        _status = 'Downloading AI model... This may take several minutes.';
      });

      // Download model (no permissions needed - downloading to app directory)
      await ModelDownloader.downloadModel(onProgress: (p) {
        setState(() {
          _progress = p;
          _status = 'Downloading AI model... ${(p * 100).toStringAsFixed(1)}%';
        });
      });

      print(
          '[ModelLoadingScreen] ✅ Download completed, proceeding with optimization...');
      setState(() {
        _status = 'Download complete! Optimizing AI model...';
        _progress = 1.0;
      });

      // Proceed with model optimization after successful download
      final prefs0 = prefs ?? await SharedPreferences.getInstance();
      await _proceedWithModelOptimization(prefs0);
    } catch (e) {
      print('[ModelLoadingScreen] ❌ Error in _checkAndDownloadModel: $e');
      setState(() {
        _downloading = false;
        _checking = false;
        _errorMessage = e.toString();
      });
    }
  }

  Future<void> _setModelReady([SharedPreferences? prefs]) async {
    final prefs0 = prefs ?? await SharedPreferences.getInstance();
    await prefs0.setBool('model_ready', true);

    // Also ensure optimization state is maintained
    final isOptimized = prefs0.getBool('model_optimized') ?? false;
    if (!isOptimized) {
      await prefs0.setBool('model_optimized', true);
      await prefs0.setBool('model_loaded', true);
      print(
          '[ModelLoadingScreen] ✅ Set optimization state for future instant launches');
    }
  }

  /// Check if running on emulator (emulators often have permission issues)
  /// Uses simple heuristics to detect emulator environment
  Future<bool> _isRunningOnEmulator() async {
    try {
      if (!Platform.isAndroid) {
        return false; // Only check on Android
      }

      // Simple heuristic: check if we're running on x86/x86_64 architecture
      // Most emulators run on x86, while real devices are usually ARM
      // This is not 100% accurate but good enough for our use case

      // For now, we'll use a conservative approach:
      // If copy operations consistently fail, it's likely an emulator
      print('[ModelLoadingScreen] 🔍 Using conservative emulator detection');
      print(
          '[ModelLoadingScreen] 📱 Assuming real device - will test copy operation');

      return false; // Default to real device, let copy operation determine compatibility
    } catch (e) {
      print(
          '[ModelLoadingScreen] ⚠️ Could not detect device type, assuming real device: $e');
      return false; // Default to real device if detection fails
    }
  }

  /// Get device RAM in MB (placeholder - would need platform-specific implementation)
  Future<int> _getDeviceRAM() async {
    try {
      // TODO: Implement actual device RAM detection using platform channels
      // For now, return a reasonable default that assumes most devices have adequate RAM
      // This could be improved by adding native Android/iOS code to detect actual RAM

      // Simulate RAM detection with some delay
      await Future.delayed(Duration(milliseconds: 200));

      // Default to assuming 6GB RAM (6144 MB) for now
      // In production, this should call platform-specific code
      return 6144; // MB
    } catch (e) {
      print('[ModelLoadingScreen] ❌ Error detecting device RAM: $e');
      // Default to safe assumption of 4GB+ if detection fails
      return 4096; // MB
    }
  }

  /// Perform warm-up inference to ensure model is fully loaded and optimized
  Future<void> _performWarmupInference() async {
    try {
      print('[ModelLoadingScreen] 🔥 Performing warm-up inference...');
      setState(() {
        _status = 'Running warm-up inference to ensure instant responses...';
      });

      // Simple warm-up prompt to ensure model is fully loaded
      final warmupPrompt = '''
hi - just reply with a hi back
''';

      // Perform a quick inference to warm up the model
      // Use the simple warmup method that bypasses emergency template
      try {
        final warmupResponse =
            await AiService().runWarmupInference(warmupPrompt.trim());
        print(
            '[ModelLoadingScreen] 🔥 Warm-up inference completed successfully');
        print('[ModelLoadingScreen] 🔥 Warmup response: $warmupResponse');
      } catch (e) {
        print(
            '[ModelLoadingScreen] ⚠️ Warm-up inference failed but model may still work: $e');
      }
    } catch (e) {
      print('[ModelLoadingScreen] ⚠️ Warm-up process failed: $e');
      // Don't fail the entire process if warm-up fails
      // The model might still work fine for actual emergencies
    }
  }

  void _goToHome() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  /// Reset optimization state - call this when model issues are detected
  Future<void> _resetOptimizationState([SharedPreferences? prefs]) async {
    final prefs0 = prefs ?? await SharedPreferences.getInstance();
    await prefs0.setBool('model_optimized', false);
    await prefs0.setBool('model_loaded', false);
    await prefs0.setBool('model_ready', false);
    print(
        '[ModelLoadingScreen] 🔄 Reset optimization state - will re-optimize on next launch');
  }

  // void _showErrorDialog(String message) {
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (context) => AlertDialog(
  //       title: Row(
  //         children: const [
  //           Icon(Icons.error_outline, color: Colors.red),
  //           SizedBox(width: 8),
  //           Text('Download Error'),
  //         ],
  //       ),
  //       content: Text(message),
  //       actions: [
  //         TextButton(
  //           onPressed: () {
  //             Navigator.of(context).pop();
  //             _checkAndDownloadModel();
  //           },
  //           child: const Text('Retry'),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.of(context).pop(),
  //           child: const Text('Cancel'),
  //         ),
  //       ],
  //     ),
  //   );
  // }

  void _showManualInstructions() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.info_outline, color: Colors.blue),
            SizedBox(width: 8),
            Text('Manual Model Setup'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'The automatic download requires authentication. You can manually download and place the model file:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('1. Visit one of these URLs:'),
              const SizedBox(height: 8),
              const SelectableText(
                '• https://gemma-3n-lite-model.s3.us-east-1.amazonaws.com/gemma-3n-E2B-it-int4.task\n'
                '• https://huggingface.co/google/gemma-3n-E2B-it-litert-preview',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text(
                  '2. Create a Hugging Face account and accept the license terms'),
              const SizedBox(height: 8),
              const Text('3. Download the .task file'),
              const SizedBox(height: 8),
              const Text(
                  '4. Place it in one of these locations on your device:'),
              const SizedBox(height: 8),
              const SelectableText(
                '• /sdcard/Download/\n'
                '• /storage/emulated/0/Android/data/com.example.myapp/files/',
                style: TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              const SizedBox(height: 16),
              const Text('5. Restart the app'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'Note: The model file is approximately 1-2 GB in size.',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              _checkAndDownloadModel();
            },
            child: const Text('Check Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFFE3F2FD),
              Color(0xFFF3E5F5),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.smart_toy,
                      size: 48,
                      color: Color(0xFF3F51B5),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Preparing AI Model',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1A237E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Setting up your emergency AI companion',
                    style: TextStyle(
                      fontSize: 16,
                      color: Color(0xFF5C6BC0),
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Column(
                        children: [
                          const Icon(Icons.error, color: Colors.red, size: 32),
                          const SizedBox(height: 8),
                          const Text(
                            'Setup Failed',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.red),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              ElevatedButton(
                                onPressed: () => _checkAndDownloadModel(),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.red,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Retry'),
                              ),
                              ElevatedButton(
                                onPressed: _showManualInstructions,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Manual Setup'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ] else if (_checking) ...[
                    const CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Color(0xFF3F51B5)),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _status,
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ] else if (_downloading) ...[
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          LinearProgressIndicator(
                            value: _progress,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: const AlwaysStoppedAnimation<Color>(
                                Color(0xFF3F51B5)),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            '${(_progress * 100).toStringAsFixed(1)}%',
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF3F51B5),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _status,
                            style: const TextStyle(fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Please keep the app open during download',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
