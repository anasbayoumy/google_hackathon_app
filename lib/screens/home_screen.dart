import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io';
import '../providers/home_provider.dart';
import '../widgets/sms_dialog_widget.dart';
// import '../widgets/permission_dialog_widget.dart';
import '../main.dart'; // Import for VoiceRecorderWidget

// Helper function to parse markdown-style bold text (*text* or **text**)
Widget buildRichTextFromMarkdown(String text, TextStyle baseStyle) {
  final List<TextSpan> spans = [];

  // Pattern to match both *text* and **text** for bold formatting
  final RegExp boldPattern = RegExp(r'\*{1,2}([^*]+)\*{1,2}');

  int lastMatchEnd = 0;

  for (final Match match in boldPattern.allMatches(text)) {
    // Add text before the bold part
    if (match.start > lastMatchEnd) {
      spans.add(TextSpan(
        text: text.substring(lastMatchEnd, match.start),
        style: baseStyle,
      ));
    }

    // Add the bold text (without asterisks)
    spans.add(TextSpan(
      text: match.group(1), // The text inside the asterisks
      style: baseStyle.copyWith(
        fontWeight: FontWeight.bold,
        color: baseStyle.color ??
            const Color(0xFF1A237E), // Slightly darker for emphasis
      ),
    ));

    lastMatchEnd = match.end;
  }

  // Add remaining text after the last bold part
  if (lastMatchEnd < text.length) {
    spans.add(TextSpan(
      text: text.substring(lastMatchEnd),
      style: baseStyle,
    ));
  }

  // If no bold text found, return regular text
  if (spans.isEmpty) {
    return Text(text, style: baseStyle);
  }

  return RichText(
    text: TextSpan(children: spans),
  );
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String inputMode = 'text'; // 'text' or 'voice'
  String? lastVoicePath;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(homeProvider);
    final notifier = ref.read(homeProvider.notifier);

    // Show permission dialog on first launch
    // WidgetsBinding.instance.addPostFrameCallback((_) {
    //   if (state.shouldShowPermissionDialog) {
    //     notifier.hidePermissionDialog();
    //     PermissionDialogWidget.showPermissionDialog(context);
    //   }
    // });

    // Show SMS dialog when AI response is ready and not yet shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (state.aiResponse != null && !state.smsDialogShown) {
        notifier.markSmsDialogShown();
        SmsDialogWidget.showSmsDialog(
          context,
          state.aiResponse!.smsDraft,
          () {
            // onDecline callback - do nothing for now
          },
        );
      }
    });

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
          child: Column(
            children: [
              // App Bar
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [
                            Color(0xFFE53935),
                            Color(0xFFD32F2F),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFE53935).withOpacity(0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.emergency,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'AI Emergency Companion',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A237E),
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Ready to assist',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Restart button - only show when AI response is available
                    if (state.aiResponse != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: IconButton(
                          onPressed: state.isRestarting
                              ? null
                              : () async {
                                  // Show loading indicator while resetting session
                                  await notifier.restartRequest();
                                },
                          icon: state.isRestarting
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        Color(0xFF3F51B5)),
                                  ),
                                )
                              : const Icon(
                                  Icons.refresh,
                                  color: Color(0xFF3F51B5),
                                  size: 24,
                                ),
                          tooltip: state.isRestarting
                              ? 'Resetting...'
                              : 'Start New Emergency Request',
                        ),
                      ),
                  ],
                ),
              ),

              // Main Content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (state.aiResponse == null) ...[
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
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Describe the Emergency',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1A237E),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // Modern segmented toggle buttons
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        curve: Curves.easeInOut,
                                        child: ElevatedButton.icon(
                                          icon: Icon(
                                            Icons.text_fields,
                                            color: inputMode == 'text'
                                                ? Colors.white
                                                : const Color(0xFF64748B),
                                            size: 18,
                                          ),
                                          label: Text(
                                            'Text',
                                            style: TextStyle(
                                              color: inputMode == 'text'
                                                  ? Colors.white
                                                  : const Color(0xFF64748B),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: inputMode == 'text'
                                                ? const Color(0xFF3B82F6)
                                                : Colors.transparent,
                                            foregroundColor: inputMode == 'text'
                                                ? Colors.white
                                                : const Color(0xFF64748B),
                                            elevation:
                                                inputMode == 'text' ? 2 : 0,
                                            shadowColor: const Color(0xFF3B82F6)
                                                .withOpacity(0.3),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                          ),
                                          onPressed: state.isAnalyzing
                                              ? null
                                              : () {
                                                  if (inputMode == 'voice' &&
                                                      lastVoicePath != null) {
                                                    _showVoiceToTextDialog();
                                                  } else {
                                                    setState(() {
                                                      inputMode = 'text';
                                                    });
                                                  }
                                                },
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 200),
                                        curve: Curves.easeInOut,
                                        child: ElevatedButton.icon(
                                          icon: Icon(
                                            Icons.mic,
                                            color: inputMode == 'voice'
                                                ? Colors.white
                                                : const Color(0xFF64748B),
                                            size: 18,
                                          ),
                                          label: Text(
                                            'Voice',
                                            style: TextStyle(
                                              color: inputMode == 'voice'
                                                  ? Colors.white
                                                  : const Color(0xFF64748B),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor:
                                                inputMode == 'voice'
                                                    ? const Color(0xFF3B82F6)
                                                    : Colors.transparent,
                                            foregroundColor:
                                                inputMode == 'voice'
                                                    ? Colors.white
                                                    : const Color(0xFF64748B),
                                            elevation:
                                                inputMode == 'voice' ? 2 : 0,
                                            shadowColor: const Color(0xFF3B82F6)
                                                .withOpacity(0.3),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 12),
                                          ),
                                          onPressed: state.isAnalyzing
                                              ? null
                                              : () {
                                                  setState(() {
                                                    inputMode = 'voice';
                                                  });
                                                },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),
                              // Show text field or voice recorder based on inputMode ONLY
                              if (inputMode == 'text')
                                Container(
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
                                  child: TextFormField(
                                    initialValue: state.textInput,
                                    onChanged: state.isAnalyzing
                                        ? null
                                        : notifier.updateTextInput,
                                    enabled: !state
                                        .isAnalyzing, // Disable during analysis
                                    maxLines: 4,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      height: 1.5,
                                      color: Color(0xFF1F2937),
                                    ),
                                    decoration: InputDecoration(
                                      labelText: 'Emergency Description',
                                      labelStyle: const TextStyle(
                                        color: Color(0xFF6B7280),
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                      hintText:
                                          'Describe the emergency situation in detail...',
                                      hintStyle: const TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 15,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                          width: 1.5,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFE5E7EB),
                                          width: 1.5,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: Color(0xFF3B82F6),
                                          width: 2,
                                        ),
                                      ),
                                      errorBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(16),
                                        borderSide: const BorderSide(
                                          color: Color(0xFFEF4444),
                                          width: 2,
                                        ),
                                      ),
                                      filled: true,
                                      fillColor: Colors.white,
                                      contentPadding: const EdgeInsets.all(20),
                                      floatingLabelBehavior:
                                          FloatingLabelBehavior.auto,
                                    ),
                                  ),
                                ),
                              if (inputMode == 'voice')
                                VoiceRecorderWidget(
                                  enabled: !state
                                      .isAnalyzing, // Disable during analysis
                                  onRecordingComplete: (String? path) {
                                    setState(() {
                                      lastVoicePath = path;
                                    });
                                    if (path != null) {
                                      notifier.updateTextInput(
                                          'Voice recording saved: ${path.split('/').last}');
                                      notifier.updateAudioPath(
                                          path); // <-- Ensure audioPath is set
                                    } else {
                                      notifier.updateTextInput('');
                                      notifier.updateAudioPath(
                                          null); // <-- Clear audioPath if recording is cleared
                                    }
                                  },
                                ),
                            ],
                          ),
                        ),

                        // Image Preview (outside the card so it's always visible)
                        if (state.imagePath != null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF5F5F5),
                              borderRadius: BorderRadius.circular(12),
                              border:
                                  Border.all(color: const Color(0xFFE0E0E0)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade300,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: state.imagePath != null
                                      ? ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: kIsWeb
                                              ? Image.network(
                                                  state.imagePath!,
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Icon(
                                                      Icons.error,
                                                      color: Colors.red,
                                                    );
                                                  },
                                                )
                                              : Image.file(
                                                  File(state.imagePath!),
                                                  fit: BoxFit.cover,
                                                  errorBuilder: (context, error,
                                                      stackTrace) {
                                                    return const Icon(
                                                      Icons.error,
                                                      color: Colors.red,
                                                    );
                                                  },
                                                ),
                                        )
                                      : const Icon(
                                          Icons.image,
                                          color: Colors.grey,
                                        ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    state.imagePath != null
                                        ? 'Image selected: ${state.imagePath!.split('/').last}'
                                        : 'Image selected',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                IconButton(
                                  onPressed: () async {
                                    debugPrint(
                                        'X button pressed, clearing image');
                                    await notifier.clearImage();
                                    debugPrint(
                                        'Image cleared, current state: ${ref.read(homeProvider).imagePath}');
                                  },
                                  icon: const Icon(Icons.close,
                                      color: Colors.red),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 24),

                        // Enhanced Add Image Button
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
                              onTap: state.isLoading
                                  ? null
                                  : () =>
                                      _showImageSourceDialog(context, notifier),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF3B82F6)
                                        .withOpacity(0.3),
                                    width: 2,
                                    style: BorderStyle.solid,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF3B82F6)
                                            .withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.add_photo_alternate,
                                        color: Color(0xFF3B82F6),
                                        size: 32,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    const Text(
                                      'Add Emergency Photo',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text(
                                      'Tap to capture or select an image',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // Enhanced Analyze Emergency Button
                        Container(
                          width: double.infinity,
                          height: 60,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: (state.textInput.trim().isEmpty &&
                                    state.audioPath == null)
                                ? const LinearGradient(
                                    colors: [
                                      Color(0xFF9CA3AF), // Grey when disabled
                                      Color(0xFF6B7280),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  )
                                : const LinearGradient(
                                    colors: [
                                      Color(0xFFE53935), // Red when enabled
                                      Color(0xFFD32F2F),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                            boxShadow: (state.textInput.trim().isEmpty &&
                                    state.audioPath == null)
                                ? [
                                    BoxShadow(
                                      color: const Color(0xFF9CA3AF)
                                          .withOpacity(0.2),
                                      blurRadius: 8,
                                      offset: const Offset(0, 4),
                                    ),
                                  ]
                                : [
                                    BoxShadow(
                                      color: const Color(0xFFE53935)
                                          .withOpacity(0.4),
                                      blurRadius: 12,
                                      offset: const Offset(0, 6),
                                    ),
                                    BoxShadow(
                                      color: const Color(0xFFE53935)
                                          .withOpacity(0.2),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: state.isLoading ||
                                      (state.textInput.trim().isEmpty &&
                                          state.audioPath == null)
                                  ? null
                                  : () => notifier.analyzeScenario(),
                              borderRadius: BorderRadius.circular(16),
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 24),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: state.isLoading
                                      ? Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor:
                                                    const AlwaysStoppedAnimation<
                                                        Color>(
                                                  Colors.white,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            const Text(
                                              'Analyzing Emergency...',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.white,
                                              ),
                                            ),
                                          ],
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Icon(
                                              Icons.emergency,
                                              color: (state.textInput
                                                          .trim()
                                                          .isEmpty &&
                                                      state.audioPath == null)
                                                  ? Colors.white.withOpacity(
                                                      0.6) // Dimmed when disabled
                                                  : Colors.white,
                                              size: 24,
                                            ),
                                            const SizedBox(width: 12),
                                            Text(
                                              'Analyze Emergency',
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: (state.textInput
                                                            .trim()
                                                            .isEmpty &&
                                                        state.audioPath == null)
                                                    ? Colors.white.withOpacity(
                                                        0.6) // Dimmed when disabled
                                                    : Colors.white,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Error Message - only show when no AI response
                        if (state.errorMessage != null &&
                            state.aiResponse == null) ...[
                          const SizedBox(height: 16),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.red.shade200),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.error, color: Colors.red),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    state.errorMessage!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ], // End of conditional for input section and analyze button

                      // AI Response Display - show when AI response is available
                      if (state.aiResponse != null) ...[
                        const SizedBox(height: 24),
                        Container(
                          padding: const EdgeInsets.all(24),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.08),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header with enhanced styling
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color:
                                      const Color(0xFF4CAF50).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Icon(
                                        Icons.medical_services,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                    ),
                                    SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Emergency Response Guidance',
                                            style: TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1A237E),
                                            ),
                                          ),
                                          Text(
                                            'Follow these steps carefully',
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF4CAF50),
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              // Enhanced step-by-step guide
                              ...state.aiResponse!.guidanceSteps
                                  .asMap()
                                  .entries
                                  .map(
                                    (entry) => Container(
                                      margin: const EdgeInsets.only(bottom: 16),
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF8F9FA),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: const Color(0xFF4CAF50)
                                              .withOpacity(0.2),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          // Enhanced step number
                                          Container(
                                            width: 32,
                                            height: 32,
                                            decoration: BoxDecoration(
                                              gradient: const LinearGradient(
                                                colors: [
                                                  Color(0xFF4CAF50),
                                                  Color(0xFF66BB6A),
                                                ],
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: const Color(0xFF4CAF50)
                                                      .withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Center(
                                              child: Text(
                                                '${entry.key + 1}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 16),

                                          // Enhanced step content
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Step ${entry.key + 1}',
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xFF4CAF50),
                                                    letterSpacing: 0.5,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                buildRichTextFromMarkdown(
                                                  entry.value,
                                                  const TextStyle(
                                                    fontSize: 16,
                                                    height: 1.5,
                                                    color: Color(0xFF2D3748),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
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
            ],
          ),
        ),
      ),
    );
  }

  void _showVoiceToTextDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          elevation: 16,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.9,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Warning Icon
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.warning_rounded,
                    color: Color(0xFFF59E0B),
                    size: 40,
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                const Text(
                  'Switch to Text Mode?',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1A237E),
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),

                // Content
                const Text(
                  'Your voice recording will be permanently deleted if you switch to text mode.',
                  style: TextStyle(
                    fontSize: 16,
                    color: Color(0xFF6B7280),
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),

                // Warning info box
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'This action cannot be undone',
                          style: TextStyle(
                            fontSize: 14,
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: () {
                          setState(() {
                            lastVoicePath = null;
                            inputMode = 'text';
                          });
                          ref.read(homeProvider.notifier).updateTextInput('');
                          ref.read(homeProvider.notifier).updateAudioPath(null);
                          Navigator.of(context).pop();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 2,
                        ),
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: const Text(
                          'Clear & Switch',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showImageSourceDialog(BuildContext context, HomeNotifier notifier) {
    showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from Gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  notifier.setImagePath();
                },
              ),
              if (!kIsWeb) // Only show camera option on mobile
                ListTile(
                  leading: const Icon(Icons.photo_camera),
                  title: const Text('Take Photo'),
                  onTap: () {
                    Navigator.of(context).pop();
                    notifier.setImagePath(source: ImageSource.camera);
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}
