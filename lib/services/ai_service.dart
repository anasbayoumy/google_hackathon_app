import 'package:flutter/services.dart';
import '../models/ai_response.dart';

class AiService {
  static const MethodChannel _channel = MethodChannel('com.example.myapp/llm');

  String buildPrompt({
    required String userInput,
    required double latitude,
    required double longitude,
    bool hasImage = false,
    bool isFromWatch = false,
  }) {
    if (isFromWatch) {
      // Watch-only prompt: SMS only
      return '''
You are an emergency assistant. Given the following voice emergency report:

$userInput

Location: $latitude, $longitude

Write a concise SMS message that can be sent to emergency services. The SMS should:
- Have the exact same situation that the user described
- Include the location coordinates
- Be as small as possible
- Only include essential emergency details
- No fancy formatting, just the emergency situation and location

Format your response as:
SMS:
<the sms message here>''';
    } else {
      // App prompt: SMS + GUIDE
      return '''
You are an expert emergency assistant. Given:

$userInput  
Location: $latitude, $longitude  
${hasImage ? "You also have an image. Note visible injuries, people, damage, hazards to improve your response." : ""}

Your tasks:

1. **SMS**  
   - Include coordinates, key details, and urgency.  

2. **GUIDE**  
   - Step-by-step, specific and actionable.  
   - Assume the user is panicked and inexperienced.  
   - Cover immediate safety, first aid, and prep for responders.  
   - Use clear, direct language.

**Output exactly as:**

SMS:  
[EMERGENCY TYPE] at [coordinates] [key details]!

GUIDE:  
1. [Immediate safety/assessment]  
2. [Specific action]  
3. [Detailed procedure if needed]  
…  
[Final: wait for emergency services]
''';
    }
  }

  Map<String, dynamic> parseModelOutput(String output) {
    print('[AiService] Parsing output: $output');

    String sms = '';
    List<String> guideSteps = [];

    // Find SMS section
    final smsMatch =
        RegExp(r'SMS:\s*\n(.*?)\n\s*GUIDE:', dotAll: true).firstMatch(output);
    if (smsMatch != null) {
      sms = smsMatch.group(1)?.trim() ?? '';
    }

    // Find GUIDE section
    final guideMatch =
        RegExp(r'GUIDE:\s*\n(.*)', dotAll: true).firstMatch(output);
    if (guideMatch != null) {
      final guideContent = guideMatch.group(1)?.trim() ?? '';

      // Split by numbered steps (1., 2., 3., etc.)
      final stepMatches = RegExp(r'\d+\.\s+(.+?)(?=\n\d+\.|\n*$)', dotAll: true)
          .allMatches(guideContent);
      guideSteps = stepMatches
          .map((match) => match.group(1)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      // If no numbered steps found, try other patterns
      if (guideSteps.isEmpty) {
        guideSteps = guideContent
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && line.length > 5)
            .map((line) => line.replaceFirst(RegExp(r'^\d+\.\s*'), ''))
            .toList();
      }
    }

    print('[AiService] Parsed SMS: "$sms"');
    print('[AiService] Parsed guideSteps: $guideSteps');

    return {'sms': sms, 'guideSteps': guideSteps};
  }

  Future<void> loadModel() async {
    print('[AiService] Calling native initModel');
    final result = await _channel.invokeMethod('initModel');
    print('[AiService] Native initModel result: $result');
  }

  /// Simple warmup inference without emergency template wrapping
  /// Used during model optimization to ensure model is fully loaded
  Future<String> runWarmupInference(String simplePrompt) async {
    print(
        '[AiService] 🔥 Running warmup inference with simple prompt: $simplePrompt');

    try {
      // Reset session for clean context
      await resetSession();

      // Send simple prompt directly without emergency template
      final args = <String, dynamic>{
        'text': simplePrompt, // Direct prompt, no template wrapping
      };

      print('[AiService] 🔥 Warmup args sent to native: $args');

      final response = await _channel.invokeMethod('runLlmInference', args);
      final output = response as String;

      print('[AiService] 🔥 Warmup response: $output');
      return output;
    } catch (e) {
      print('[AiService] ⚠️ Warmup inference failed: $e');
      return 'Warmup failed: $e';
    }
  }

  Future<void> resetSession() async {
    print('[AiService] Calling native resetSession');
    final result = await _channel.invokeMethod('resetSession');
    print('[AiService] Native resetSession result: $result');
  }

  Future<bool> requestStoragePermission() async {
    print('[AiService] Calling native requestStoragePermission');
    try {
      final result = await _channel.invokeMethod('requestStoragePermission');
      print('[AiService] Native requestStoragePermission result: $result');
      return result as bool;
    } catch (e) {
      print('[AiService] requestStoragePermission error: $e');
      return false;
    }
  }

  Future<String?> copyModelFromDownloads() async {
    print('[AiService] Calling native copyModelFromDownloads');
    try {
      final result = await _channel.invokeMethod('copyModelFromDownloads');
      print('[AiService] Native copyModelFromDownloads result: $result');
      return result as String?;
    } catch (e) {
      print('[AiService] copyModelFromDownloads error: $e');
      return null;
    }
  }

  Future<AiResponse> runInference(
    String prompt, {
    String? imagePath,
    String? audioPath,
    double? latitude,
    double? longitude,
    bool isFromWatch = false,
  }) async {
    print('[AiService] Preparing to call native runLlmInference');
    print('[AiService] prompt: $prompt');
    print('[AiService] imagePath: $imagePath');
    print('[AiService] audioPath: $audioPath');
    print('[AiService] latitude: $latitude, longitude: $longitude');

    // Always reset session before new inference to ensure clean context
    print('[AiService] Resetting session for fresh context...');
    try {
      await resetSession();
      print('[AiService] Session reset successful');
    } catch (e) {
      print('[AiService] Session reset failed: $e - continuing anyway');
    }

    // Build the real prompt
    final realPrompt = buildPrompt(
      userInput: prompt,
      latitude: latitude ?? 0.0,
      longitude: longitude ?? 0.0,
      hasImage: imagePath != null && imagePath.isNotEmpty,
      isFromWatch: isFromWatch,
    );

    final args = <String, dynamic>{
      'text': realPrompt,
    };

    if (imagePath != null && imagePath.isNotEmpty) {
      args['imagePath'] = imagePath;
    }
    if (audioPath != null && audioPath.isNotEmpty) {
      args['audioPath'] = audioPath;
    }

    print('[AiService] Args sent to native: $args');

    try {
      final response = await _channel.invokeMethod('runLlmInference', args);
      print('[AiService] Native runLlmInference response: $response');
      final output = response as String;

      // Check if we got an empty response (token limit exceeded)
      if (output.trim().isEmpty) {
        print(
            '[AiService] Empty response detected, resetting session and retrying...');
        await resetSession();

        // Retry with the same arguments
        final retryResponse =
            await _channel.invokeMethod('runLlmInference', args);
        print('[AiService] Retry response: $retryResponse');
        final retryOutput = retryResponse as String;

        final parsed = parseModelOutput(retryOutput);
        print('[AiService] Parsed SMS: ${parsed['sms']}');
        print('[AiService] Parsed guideSteps: ${parsed['guideSteps']}');
        return AiResponse(
          smsDraft: parsed['sms'] ?? '',
          guidanceSteps: List<String>.from(parsed['guideSteps'] ?? []),
        );
      }

      final parsed = parseModelOutput(output);
      print('[AiService] Parsed SMS: ${parsed['sms']}');
      print('[AiService] Parsed guideSteps: ${parsed['guideSteps']}');
      return AiResponse(
        smsDraft: parsed['sms'] ?? '',
        guidanceSteps: List<String>.from(parsed['guideSteps'] ?? []),
      );
    } catch (e) {
      print('[AiService] Error during inference: $e');
      // If there's an error, try resetting session and retry once
      try {
        print('[AiService] Attempting session reset due to error...');
        await resetSession();
        final retryResponse =
            await _channel.invokeMethod('runLlmInference', args);
        final retryOutput = retryResponse as String;
        final parsed = parseModelOutput(retryOutput);
        return AiResponse(
          smsDraft: parsed['sms'] ?? '',
          guidanceSteps: List<String>.from(parsed['guideSteps'] ?? []),
        );
      } catch (retryError) {
        print('[AiService] Retry also failed: $retryError');
        rethrow;
      }
    }
  }
}
