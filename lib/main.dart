import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utils/app_constants.dart';
import 'package:record/record.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'screens/model_loading_screen.dart';
// import 'dart:io';

void main() {
  runApp(const ProviderScope(child: EmergencyCompanionApp()));
}

class EmergencyCompanionApp extends StatelessWidget {
  const EmergencyCompanionApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
        title: AppConstants.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF3F51B5),
            brightness: Brightness.light,
          ),
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.transparent,
            elevation: 0,
            centerTitle: true,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          inputDecorationTheme: InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFF3F51B5), width: 2),
            ),
          ),
        ),
        home: const ModelLoadingScreen());
  }
}

// Add a stateful widget for voice recording
class VoiceRecorderWidget extends StatefulWidget {
  final void Function(String? path) onRecordingComplete;
  final bool enabled; // Add enabled parameter to lock during analysis
  const VoiceRecorderWidget({
    super.key,
    required this.onRecordingComplete,
    this.enabled = true,
  });

  @override
  State<VoiceRecorderWidget> createState() => _VoiceRecorderWidgetState();
}

class _VoiceRecorderWidgetState extends State<VoiceRecorderWidget> {
  final AudioPlayer _player = AudioPlayer();
  String? _filePath;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isPlaying = false;
  final Duration _duration = Duration.zero;
  final Duration _position = Duration.zero;
  late String _wavPath;
  late final AudioRecorder _recorder;

  @override
  void initState() {
    super.initState();
    _recorder = AudioRecorder();
  }

  @override
  void dispose() {
    _player.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<String> _getWavPath() async {
    final dir = await getApplicationDocumentsDirectory();
    return '${dir.path}/voice_input.wav';
  }

  Future<void> _startRecording() async {
    _wavPath = await _getWavPath();
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.wav,
        bitRate: 128000,
        sampleRate: 16000,
        numChannels: 1, // Mono audio for Vosk
        autoGain: false, // Disable auto gain for consistent audio
        echoCancel: false, // Disable echo cancellation for raw audio
        noiseSuppress: false, // Disable noise suppression for raw audio
      ),
      path: _wavPath,
    );
    setState(() {
      _isRecording = true;
      _isPaused = false;
      _filePath = null;
    });
  }

  Future<void> _pauseRecording() async {
    await _recorder.pause();
    setState(() {
      _isPaused = true;
    });
  }

  Future<void> _resumeRecording() async {
    await _recorder.resume();
    setState(() {
      _isPaused = false;
    });
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    setState(() {
      _isRecording = false;
      _isPaused = false;
      _filePath = path;
    });
    widget.onRecordingComplete(path);
  }

  Future<void> _restartRecording() async {
    await _recorder.stop();
    await _startRecording();
  }

  Future<void> _playRecording() async {
    if (_filePath == null) return;
    await _player.setFilePath(_filePath!);
    setState(() {
      _isPlaying = true;
    });
    _player.play();
    _player.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _isPlaying = false;
        });
      }
    });
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    setState(() {
      _isPlaying = false;
    });
  }

  void _clearRecording() {
    setState(() {
      _filePath = null;
    });
    widget.onRecordingComplete(null);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!_isRecording && _filePath == null)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.enabled ? _startRecording : null,
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [
                              Color(0xFFEF4444),
                              Color(0xFFDC2626),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(32),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFEF4444).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.mic,
                          color: Colors.white,
                          size: 32,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Record Emergency Voice',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1F2937),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap to start recording your emergency description',
                        style: TextStyle(
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_isRecording) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: const Color(0xFFEF4444).withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFEF4444).withOpacity(0.1),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              children: [
                // Recording indicator with animation
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: _isPaused
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _isPaused
                            ? 'Recording Paused'
                            : 'Recording in Progress...',
                        style: TextStyle(
                          color: _isPaused
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFFEF4444),
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Control buttons
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: Icon(
                            _isPaused ? Icons.play_arrow : Icons.pause,
                            size: 20,
                          ),
                          label: Text(
                            _isPaused ? 'Resume' : 'Pause',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: widget.enabled
                              ? (_isPaused ? _resumeRecording : _pauseRecording)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF3B82F6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.stop, size: 20),
                          label: const Text(
                            'Stop',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: widget.enabled ? _stopRecording : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        if (_filePath != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF10B981).withOpacity(0.3),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withOpacity(0.1),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                // Success header
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Recording Complete',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF10B981),
                              ),
                            ),
                            Text(
                              'Voice recording saved successfully',
                              style: TextStyle(
                                fontSize: 14,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Control buttons
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: Icon(
                            _isPlaying ? Icons.stop : Icons.play_arrow,
                            size: 20,
                          ),
                          label: Text(
                            _isPlaying ? 'Stop' : 'Play',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: widget.enabled
                              ? (_isPlaying ? _stopPlayback : _playRecording)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.04),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.delete, size: 20),
                          label: const Text(
                            'Clear',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                          onPressed: widget.enabled ? _clearRecording : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6B7280),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            elevation: 0,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}
