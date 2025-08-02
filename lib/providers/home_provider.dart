import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import '../models/ai_response.dart';
import '../services/ai_service.dart';
import '../services/location_service.dart';
import 'package:flutter/services.dart';

class HomeState {
  final String textInput;
  final String? imagePath;
  final bool isLoading;
  final AiResponse? aiResponse;
  final bool isListening;
  final String? errorMessage;
  final bool permissionsRequested;
  final bool smsDialogShown;
  final bool shouldShowPermissionDialog;
  final LocationData? currentLocation;
  final bool isLocationLoading;
  final String? audioPath;
  final bool isAnalyzing; // New flag to lock UI during analysis
  final bool isRestarting; // New flag for restart operation

  HomeState({
    this.textInput = '',
    this.imagePath,
    this.isLoading = false,
    this.aiResponse,
    this.isListening = false,
    this.errorMessage,
    this.permissionsRequested = false,
    this.smsDialogShown = false,
    this.shouldShowPermissionDialog = false,
    this.currentLocation,
    this.isLocationLoading = false,
    this.audioPath,
    this.isAnalyzing = false,
    this.isRestarting = false,
  });

  HomeState copyWith({
    String? textInput,
    String? imagePath,
    bool? isLoading,
    AiResponse? aiResponse,
    bool? isListening,
    String? errorMessage,
    bool? permissionsRequested,
    bool? smsDialogShown,
    bool? shouldShowPermissionDialog,
    LocationData? currentLocation,
    bool? isLocationLoading,
    String? audioPath,
    bool? isAnalyzing,
    bool? isRestarting,
    bool clearAudioPath = false, // Add flag to explicitly clear audioPath
    bool clearImagePath = false, // Add flag to explicitly clear imagePath
  }) {
    return HomeState(
      textInput: textInput ?? this.textInput,
      imagePath: clearImagePath ? null : (imagePath ?? this.imagePath),
      isLoading: isLoading ?? this.isLoading,
      aiResponse: aiResponse ?? this.aiResponse,
      isListening: isListening ?? this.isListening,
      errorMessage: errorMessage ?? this.errorMessage,
      permissionsRequested: permissionsRequested ?? this.permissionsRequested,
      smsDialogShown: smsDialogShown ?? this.smsDialogShown,
      shouldShowPermissionDialog:
          shouldShowPermissionDialog ?? this.shouldShowPermissionDialog,
      currentLocation: currentLocation ?? this.currentLocation,
      isLocationLoading: isLocationLoading ?? this.isLocationLoading,
      audioPath: clearAudioPath ? null : (audioPath ?? this.audioPath),
      isAnalyzing: isAnalyzing ?? this.isAnalyzing,
      isRestarting: isRestarting ?? this.isRestarting,
    );
  }
}

class HomeNotifier extends StateNotifier<HomeState> {
  final ImagePicker _imagePicker = ImagePicker();
  final SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  final AiService _aiService = AiService();

  HomeNotifier() : super(HomeState()) {
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    // Wait a moment to ensure the app is fully loaded
    await Future.delayed(const Duration(milliseconds: 500));

    if (!kIsWeb) {
      // Always check if all permissions are already granted
      bool allPermissionsGranted = await _checkAllPermissionsGranted();

      if (!allPermissionsGranted) {
        // Only show permission dialog if some permissions are missing
        state = state.copyWith(shouldShowPermissionDialog: true);
        // Wait a bit more for the dialog to be triggered from UI
        await Future.delayed(const Duration(milliseconds: 1000));
      }
    }

    await _requestPermissions();
  }

  Future<bool> _checkAllPermissionsGranted() async {
    if (kIsWeb) return true;

    try {
      // Check current status of all required permissions (without requesting)
      List<PermissionStatus> statuses = await Future.wait([
        Permission.microphone.status,
        Permission.camera.status,
        Permission.storage.status,
        Permission.photos.status,
        Permission.location.status,
        Permission.locationWhenInUse.status,
      ]);

      // Check if all permissions are granted
      bool allGranted = statuses.every((status) => status.isGranted);
      debugPrint('All permissions granted: $allGranted');
      return allGranted;
    } catch (e) {
      debugPrint('Error checking permissions: $e');
      return false;
    }
  }

  Future<void> _initializeServices() async {
    // Initialize speech recognition if microphone permission is granted
    final micStatus = await Permission.microphone.status;
    if (micStatus.isGranted) {
      debugPrint('Microphone permission granted, initializing speech...');
      await _initializeSpeech();
    }

    // Get current location if location permission is granted
    final locationStatus = await Permission.location.status;
    final locationWhenInUseStatus = await Permission.locationWhenInUse.status;
    if (locationStatus.isGranted || locationWhenInUseStatus.isGranted) {
      debugPrint('Location permission granted, getting current location...');
      await _getCurrentLocation();
    }
  }

  Future<void> _requestPermissions() async {
    if (kIsWeb) {
      state = state.copyWith(permissionsRequested: true);
      return;
    }

    // Check if permissions are already granted
    bool allPermissionsGranted = await _checkAllPermissionsGranted();

    if (allPermissionsGranted) {
      // If all permissions are granted, just initialize services
      state = state.copyWith(permissionsRequested: true);
      await _initializeServices();
      return;
    }

    try {
      debugPrint('Requesting permissions...');

      // Request all permissions at once
      Map<Permission, PermissionStatus> statuses = await [
        Permission.microphone,
        Permission.camera,
        Permission.storage,
        Permission.photos,
        Permission.location,
        Permission.locationWhenInUse,
      ].request();

      state = state.copyWith(permissionsRequested: true);

      // Check microphone permission specifically for speech
      final micStatus = statuses[Permission.microphone];
      if (micStatus != null && micStatus.isGranted) {
        debugPrint('Microphone permission granted, initializing speech...');
        await _initializeSpeech();
      } else {
        debugPrint('Microphone permission denied: $micStatus');
        state = state.copyWith(
          errorMessage: 'Microphone permission is required for voice input.',
        );
      }

      // Check other permissions
      final cameraStatus = statuses[Permission.camera];
      if (cameraStatus != null && !cameraStatus.isGranted) {
        debugPrint('Camera permission denied: $cameraStatus');
      }

      // Check location permission
      final locationStatus = statuses[Permission.location];
      final locationWhenInUseStatus = statuses[Permission.locationWhenInUse];
      if ((locationStatus != null && locationStatus.isGranted) ||
          (locationWhenInUseStatus != null &&
              locationWhenInUseStatus.isGranted)) {
        debugPrint('Location permission granted, getting current location...');
        await _getCurrentLocation();
      } else {
        debugPrint(
            'Location permission denied - location: $locationStatus, whenInUse: $locationWhenInUseStatus');
      }
    } catch (e) {
      debugPrint('Failed to request permissions: $e');
      state = state.copyWith(
        errorMessage:
            'Failed to request permissions. Please check app settings.',
        permissionsRequested: true,
      );
    }
  }

  Future<void> _initializeSpeech() async {
    if (kIsWeb) {
      debugPrint('Speech recognition not supported on web');
      return;
    }

    try {
      debugPrint('Initializing speech recognition...');

      // Check if microphone permission is still granted
      final micStatus = await Permission.microphone.status;
      if (!micStatus.isGranted) {
        debugPrint('Microphone permission not granted');
        state = state.copyWith(
          errorMessage: 'Microphone permission required for voice input.',
        );
        return;
      }

      _speechEnabled = await _speechToText.initialize(
        onError: (errorNotification) {
          debugPrint('Speech error: ${errorNotification.errorMsg}');
          state = state.copyWith(
            errorMessage: 'Voice recognition error. Please try again.',
            isListening: false,
          );
        },
        onStatus: (status) {
          debugPrint('Speech status: $status');
          if (status == 'done' || status == 'notListening') {
            state = state.copyWith(isListening: false);
          }
        },
        debugLogging: true,
      );

      debugPrint('Speech initialized successfully: $_speechEnabled');

      if (!_speechEnabled) {
        state = state.copyWith(
          errorMessage:
              'Voice recognition initialization failed. Please restart the app.',
        );
      }
    } catch (e) {
      debugPrint('Speech initialization failed: $e');
      _speechEnabled = false;
      state = state.copyWith(
        errorMessage: 'Voice recognition not available on this device.',
      );
    }
  }

  void updateTextInput(String text) {
    state = state.copyWith(textInput: text);
  }

  void updateAudioPath(String? path) {
    if (path == null) {
      state = state.copyWith(clearAudioPath: true);
    } else {
      state = state.copyWith(audioPath: path);
    }
  }

  Future<void> setImagePath({ImageSource? source}) async {
    try {
      ImageSource imageSource = source ?? ImageSource.gallery;

      // On web, camera might not be available, so default to gallery
      if (kIsWeb && imageSource == ImageSource.camera) {
        imageSource = ImageSource.gallery;
      }

      debugPrint('setImagePath called with source: $imageSource');
      final XFile? image = await _imagePicker.pickImage(
        source: imageSource,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image != null) {
        debugPrint('Image selected: ${image.path}');
        state = state.copyWith(imagePath: image.path);
        debugPrint('Image path set in state: ${state.imagePath}');
      } else {
        debugPrint('No image selected');
      }
    } catch (e) {
      debugPrint('Error selecting image: $e');
      state = state.copyWith(
        errorMessage: 'Failed to select image: $e',
      );
    }
  }

  Future<void> _getCurrentLocation() async {
    if (kIsWeb) {
      debugPrint('Location services not supported on web');
      return;
    }

    try {
      state = state.copyWith(isLocationLoading: true);
      debugPrint('Getting current location...');

      // Check if location services are enabled
      bool serviceEnabled = await LocationService.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('Location services are disabled');
        state = state.copyWith(
          isLocationLoading: false,
          errorMessage:
              'Location services are disabled. Please enable them in device settings.',
        );
        return;
      }

      // Check and request location permission
      bool hasPermission = await LocationService.hasLocationPermission();
      if (!hasPermission) {
        hasPermission = await LocationService.requestLocationPermission();
        if (!hasPermission) {
          debugPrint('Location permissions are denied');
          state = state.copyWith(
            isLocationLoading: false,
            errorMessage: 'Location permissions are denied.',
          );
          return;
        }
      }

      // Get current position using our location service
      LocationData? position = await LocationService.getCurrentLocation();

      if (position != null) {
        debugPrint(
            'Location obtained: ${position.latitude}, ${position.longitude}');
        state = state.copyWith(
          currentLocation: position,
          isLocationLoading: false,
        );
      } else {
        state = state.copyWith(
          isLocationLoading: false,
          errorMessage: 'Failed to get current location.',
        );
      }
    } catch (e) {
      debugPrint('Failed to get location: $e');
      state = state.copyWith(
        isLocationLoading: false,
        errorMessage: 'Failed to get current location: $e',
      );
    }
  }

  Future<void> clearImage() async {
    debugPrint('clearImage called, current imagePath: ${state.imagePath}');

    // Delete the actual file if it exists
    if (state.imagePath != null && !kIsWeb) {
      try {
        final file = File(state.imagePath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('Image file deleted: ${state.imagePath}');
        }
      } catch (e) {
        debugPrint('Error deleting image file: $e');
      }
    }

    state = state.copyWith(clearImagePath: true);
    debugPrint('clearImage completed, new imagePath: ${state.imagePath}');
  }

  Future<void> toggleListening() async {
    if (kIsWeb) {
      state = state.copyWith(
        errorMessage:
            'Voice input not available on web. Please type your emergency description.',
      );
      return;
    }

    // Clear any previous error messages
    state = state.copyWith(errorMessage: null);

    if (!_speechEnabled) {
      debugPrint('Speech not enabled, trying to reinitialize...');
      await _initializeSpeech();
      if (!_speechEnabled) {
        state = state.copyWith(
          errorMessage:
              'Voice recognition not available. Please check microphone permissions in settings.',
        );
        return;
      }
    }

    try {
      if (state.isListening) {
        debugPrint('Stopping speech recognition');
        await _speechToText.stop();
        state = state.copyWith(isListening: false);
      } else {
        debugPrint('Starting speech recognition');

        // Check if speech to text is available
        bool available = await _speechToText.hasPermission;
        if (!available) {
          state = state.copyWith(
            errorMessage:
                'Microphone permission not available. Please check app settings.',
          );
          return;
        }

        state = state.copyWith(isListening: true);

        bool success = await _speechToText.listen(
          onResult: (result) {
            debugPrint(
                'Speech result: ${result.recognizedWords}, final: ${result.finalResult}');

            if (result.finalResult && result.recognizedWords.isNotEmpty) {
              // Append to existing text if any, otherwise replace
              String newText = state.textInput.isEmpty
                  ? result.recognizedWords
                  : '${state.textInput} ${result.recognizedWords}';

              state = state.copyWith(
                textInput: newText,
                isListening: false,
              );
              debugPrint('Updated text input: $newText');
            }
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 3),
          localeId: 'en_US',
        );

        if (!success) {
          state = state.copyWith(
            isListening: false,
            errorMessage:
                'Could not start voice recognition. Please try again.',
          );
        }
      }
    } catch (e) {
      debugPrint('Speech error: $e');
      state = state.copyWith(
        errorMessage:
            'Voice recognition failed. Please try again or type your emergency.',
        isListening: false,
      );
    }
  }

  Future<String> transcribeWavWithVosk(String wavPath) async {
    debugPrint('🎤 [VOSK] Starting transcription for file: $wavPath');
    const platform = MethodChannel('com.example.myapp/llm');
    try {
      // Increase timeout to 60 seconds for Vosk processing (was 30, now 60)
      debugPrint(
          '🎤 [VOSK] Waiting for Kotlin transcription (timeout: 60s)...');
      final text = await platform.invokeMethod<String>(
        'transcribeWavWithVosk',
        {'wavPath': wavPath},
      ).timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          debugPrint('🎤 [VOSK] ❌ Transcription timed out after 60 seconds');
          return '';
        },
      );
      final transcribedText = text ?? '';
      debugPrint('🎤 [VOSK] ✅ Transcription completed!');
      debugPrint('🎤 [VOSK] 📝 Transcribed text: "$transcribedText"');
      debugPrint(
          '🎤 [VOSK] 📏 Text length: ${transcribedText.length} characters');
      return transcribedText;
    } catch (e) {
      debugPrint('🎤 [VOSK] ❌ Transcription error: $e');
      return '';
    }
  }

  Future<void> analyzeScenario() async {
    if (state.textInput.trim().isEmpty &&
        (state.audioPath == null || state.audioPath!.isEmpty)) {
      state = state.copyWith(
          errorMessage:
              'Please provide text or record audio for the emergency situation');
      return;
    }

    // Lock UI during analysis
    state =
        state.copyWith(isLoading: true, isAnalyzing: true, errorMessage: null);

    try {
      // Use real location if available, otherwise fallback to default
      double latitude = 40.7128; // Default to NYC
      double longitude = -74.0060;

      if (state.currentLocation != null) {
        latitude = state.currentLocation!.latitude;
        longitude = state.currentLocation!.longitude;
        debugPrint('Using real location: $latitude, $longitude');
      } else {
        debugPrint('Using fallback location: $latitude, $longitude');
        // Try to get location one more time if not available
        if (!kIsWeb) {
          await _getCurrentLocation();
          if (state.currentLocation != null) {
            latitude = state.currentLocation!.latitude;
            longitude = state.currentLocation!.longitude;
            debugPrint('Got location on retry: $latitude, $longitude');
          }
        }
      }

      String promptText = state.textInput.trim();
      debugPrint('📝 [ANALYZE] Initial text input: "$promptText"');
      debugPrint('📝 [ANALYZE] Audio path: "${state.audioPath}"');

      // If audio is present, transcribe it and use as prompt
      if (state.audioPath != null && state.audioPath!.isNotEmpty) {
        debugPrint(
            '🎤 [ANALYZE] Audio file detected, starting Vosk transcription...');
        debugPrint('🎤 [ANALYZE] Audio file path: ${state.audioPath}');
        debugPrint(
            '🎤 [ANALYZE] Original text before transcription: "$promptText"');

        final stopwatch = Stopwatch()..start();
        final recognizedText = await transcribeWavWithVosk(state.audioPath!);
        stopwatch.stop();

        debugPrint(
            '🎤 [ANALYZE] Vosk transcription completed in ${stopwatch.elapsedMilliseconds}ms');
        debugPrint('🎤 [ANALYZE] Vosk transcription result: "$recognizedText"');
        debugPrint(
            '🎤 [ANALYZE] Result length: ${recognizedText.length} characters');

        if (recognizedText.isNotEmpty) {
          promptText = recognizedText;
          debugPrint(
              '✅ [ANALYZE] SUCCESS: Using transcribed text as prompt: "$promptText"');
        } else {
          debugPrint(
              '❌ [ANALYZE] FAILURE: Vosk transcription returned empty text');
          debugPrint('❌ [ANALYZE] Will use original text: "$promptText"');
        }
      } else {
        debugPrint('📝 [ANALYZE] No audio file, using text input only');
      }

      debugPrint('Calling AiService.runInference with text: \'$promptText\', image: \'${state.imagePath ?? ''}\', audio: \'${state.audioPath ?? ''}\'');
      await _aiService.loadModel();
      AiResponse aiResponse = await _aiService.runInference(
        promptText,
        imagePath: state.imagePath,
        latitude: latitude,
        longitude: longitude,
      );

      // Inject coordinates into SMS draft
      final smsDraftWithLocation = aiResponse.smsDraft
          .replaceAll('[LATITUDE]', latitude.toStringAsFixed(6))
          .replaceAll('[LONGITUDE]', longitude.toStringAsFixed(6));

      debugPrint(
          'Setting AI response with ${aiResponse.guidanceSteps.length} guidance steps');
      state = state.copyWith(
        aiResponse: AiResponse(
          smsDraft: smsDraftWithLocation,
          guidanceSteps: aiResponse.guidanceSteps,
        ),
        isLoading: false,
        isAnalyzing: false, // Unlock UI after successful analysis
        smsDialogShown: false, // Reset to allow dialog to show
      );
      debugPrint(
          'AI response set, guidance steps: ${state.aiResponse?.guidanceSteps}');
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        isAnalyzing: false, // Unlock UI after error
        errorMessage: 'Failed to analyze scenario: $e',
      );
    }
  }

  void clearState() {
    state = HomeState(
      permissionsRequested: state.permissionsRequested,
      currentLocation: state.currentLocation,
    );
  }

  Future<void> restartRequest() async {
    debugPrint('🔄 [HomeNotifier] Restart request - resetting AI session...');

    // Set loading state
    state = state.copyWith(isRestarting: true);

    try {
      // Reset the AI session to clear previous context
      await _aiService.resetSession();
      debugPrint('✅ [HomeNotifier] AI session reset successfully');
    } catch (e) {
      debugPrint('❌ [HomeNotifier] Failed to reset AI session: $e');
      // Continue with UI reset even if session reset fails
    }

    // Reset the UI state (this will also clear isRestarting)
    state = HomeState(
      permissionsRequested: state.permissionsRequested,
      currentLocation: state.currentLocation,
    );
    debugPrint('✅ [HomeNotifier] UI state reset completed');
  }

  void markSmsDialogShown() {
    state = state.copyWith(smsDialogShown: true);
  }

  void hidePermissionDialog() {
    state = state.copyWith(shouldShowPermissionDialog: false);
  }
}

final homeProvider = StateNotifierProvider<HomeNotifier, HomeState>((ref) {
  return HomeNotifier();
});
