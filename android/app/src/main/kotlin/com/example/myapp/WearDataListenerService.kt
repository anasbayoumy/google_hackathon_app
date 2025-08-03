package com.example.myapp

import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.wearable.*
import kotlinx.coroutines.*
import kotlinx.coroutines.tasks.await
import java.io.File
import java.io.FileOutputStream

class WearDataListenerService : WearableListenerService() {
    
    companion object {
        private const val TAG = "WearDataListener"
        private const val EMERGENCY_VOICE_PATH = "/emergency_voice"
        private const val SMS_RESPONSE_PATH = "/sms_response"
        private const val REQUEST_SMS_PATH = "/request_sms"
        private const val CONNECTION_CHECK_PATH = "/connection_check"
    }
    
    private val serviceScope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    override fun onDataChanged(dataEvents: DataEventBuffer) {
        super.onDataChanged(dataEvents)

        Log.d(TAG, "📱 PHONE STEP 1: WearDataListenerService received data from watch!")
        Log.d(TAG, "📱 Service is running and active!")
        Log.d(TAG, "📱 Number of data events: ${dataEvents.count}")

        for (event in dataEvents) {
            Log.d(TAG, "📱 Processing data event type: ${event.type}")
            if (event.type == DataEvent.TYPE_CHANGED) {
                val dataItem = event.dataItem
                Log.d(TAG, "📱 PHONE STEP 2: Data item received!")
                Log.d(TAG, "📱 Data item URI: ${dataItem.uri}")
                Log.d(TAG, "📱 Data item path: ${dataItem.uri.path}")

                when (dataItem.uri.path) {
                    EMERGENCY_VOICE_PATH -> {
                        Log.d(TAG, "✅ PHONE STEP 3: Emergency voice data detected!")
                        Log.d(TAG, "✅ Starting emergency voice processing...")
                        handleEmergencyVoice(dataItem)
                    }
                    REQUEST_SMS_PATH -> {
                        Log.d(TAG, "✅ PHONE STEP 3: Emergency SMS request detected!")
                        handleEmergencySmsRequest(dataItem)
                    }
                    else -> {
                        Log.w(TAG, "⚠️ Unknown data path received: ${dataItem.uri.path}")
                    }
                }
            } else {
                Log.d(TAG, "📱 Ignoring data event type: ${event.type}")
            }
        }
        Log.d(TAG, "📱 Finished processing all data events")
    }
    
    override fun onMessageReceived(messageEvent: MessageEvent) {
        super.onMessageReceived(messageEvent)
        
        when (messageEvent.path) {
            CONNECTION_CHECK_PATH -> {
                Log.d(TAG, "Connection check received from watch")
                // Respond to connection check
                serviceScope.launch {
                    sendConnectionResponse(messageEvent.sourceNodeId)
                }
            }
        }
    }
    
    private fun handleEmergencyVoice(dataItem: DataItem) {
        serviceScope.launch {
            try {
                Log.d(TAG, "📱 PHONE STEP 4: Processing emergency voice from watch")
                Log.d(TAG, "📱 Data item URI: ${dataItem.uri}")

                val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
                Log.d(TAG, "📱 PHONE STEP 5: DataMap extracted successfully")
                Log.d(TAG, "📱 DataMap keys: ${dataMap.keySet()}")

                val asset = dataMap.getAsset("audio_file")
                Log.d(TAG, "📱 PHONE STEP 6: Audio asset extraction")
                Log.d(TAG, "📱 Asset found: ${asset != null}")

                if (asset != null) {
                    Log.d(TAG, "📱 PHONE STEP 7: Getting audio file from asset...")
                    // Get audio file from watch
                    val audioFile = getAudioFileFromAsset(asset)

                    if (audioFile != null) {
                        Log.d(TAG, "✅ PHONE STEP 8: Audio file received successfully!")
                        Log.d(TAG, "✅ Audio file size: ${audioFile.length()} bytes")
                        Log.d(TAG, "✅ Starting AI processing...")
                        // Process with AI (watch mode)
                        val nodeId = dataItem.uri.host ?: ""
                        processEmergencyAudio(audioFile, nodeId)
                    } else {
                        Log.e(TAG, "❌ PHONE STEP 8 FAILED: Failed to receive audio file")
                        sendErrorToWatch("Failed to receive audio file")
                    }
                } else {
                    Log.e(TAG, "❌ PHONE STEP 6 FAILED: No audio file in request")
                    sendErrorToWatch("No audio file in request")
                }
            } catch (e: Exception) {
                Log.e(TAG, "❌ PHONE STEP FAILED: Error handling emergency voice", e)
                Log.e(TAG, "❌ Exception type: ${e.javaClass.simpleName}")
                Log.e(TAG, "❌ Exception message: ${e.message}")
                sendErrorToWatch("Processing error: ${e.message}")
            }
        }
    }
    
    private fun handleEmergencySmsRequest(dataItem: DataItem) {
        serviceScope.launch {
            try {
                Log.d(TAG, "Processing emergency SMS request from watch")
                
                val dataMap = DataMapItem.fromDataItem(dataItem).dataMap
                val voiceText = String(dataMap.getByteArray("voice_text") ?: byteArrayOf())
                
                if (voiceText.isNotEmpty()) {
                    // Process with AI (watch mode - text only)
                    val nodeId = dataItem.uri.host ?: ""
                    processEmergencyText(voiceText, nodeId)
                } else {
                    sendErrorToWatch("No voice text in request")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error handling SMS request", e)
                sendErrorToWatch("SMS processing error: ${e.message}")
            }
        }
    }
    
    private suspend fun getAudioFileFromAsset(asset: Asset): File? {
        return withContext(Dispatchers.IO) {
            try {
                val inputStream = Wearable.getDataClient(this@WearDataListenerService)
                    .getFdForAsset(asset).await().inputStream
                
                val audioFile = File(cacheDir, "watch_emergency_${System.currentTimeMillis()}.3gp")
                val outputStream = FileOutputStream(audioFile)
                
                inputStream.use { input ->
                    outputStream.use { output ->
                        input.copyTo(output)
                    }
                }
                
                Log.d(TAG, "Audio file saved: ${audioFile.absolutePath}")
                audioFile
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get audio file from asset", e)
                null
            }
        }
    }
    
    private suspend fun processEmergencyAudio(audioFile: File, nodeId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "📱 PHONE STEP 10: Starting emergency audio processing...")
                Log.d(TAG, "📱 PHONE STEP 10: Audio file: ${audioFile.absolutePath}")
                Log.d(TAG, "📱 PHONE STEP 10: Audio file size: ${audioFile.length()} bytes")

                // Use VOSK to transcribe audio
                Log.d(TAG, "📱 PHONE STEP 11: Starting VOSK transcription...")
                val transcription = transcribeAudioWithVosk(audioFile)
                Log.d(TAG, "📱 PHONE STEP 12: VOSK transcription completed!")
                Log.d(TAG, "📱 PHONE STEP 12: Transcription result: \"$transcription\"")

                if (transcription.isNotEmpty()) {
                    Log.d(TAG, "📱 PHONE STEP 13: Transcription successful, processing with AI...")
                    processEmergencyText(transcription, nodeId)
                } else {
                    Log.e(TAG, "❌ PHONE STEP 12 FAILED: Empty transcription result")
                    sendErrorToWatch("Failed to transcribe audio")
                }

                // Clean up audio file
                Log.d(TAG, "🗑️ PHONE: Deleting processed audio file...")
                audioFile.delete()
                Log.d(TAG, "🗑️ PHONE: Audio file deleted")
            } catch (e: Exception) {
                Log.e(TAG, "❌ PHONE STEP FAILED: Error processing emergency audio", e)
                Log.e(TAG, "❌ Exception type: ${e.javaClass.simpleName}")
                Log.e(TAG, "❌ Exception message: ${e.message}")
                sendErrorToWatch("Audio processing error: ${e.message}")
            }
        }
    }
    
    private suspend fun processEmergencyText(emergencyText: String, nodeId: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "📱 PHONE STEP 13: Starting AI processing for emergency text...")
                Log.d(TAG, "📱 PHONE STEP 13: Emergency text: \"$emergencyText\"")
                Log.d(TAG, "📱 PHONE STEP 13: Node ID: $nodeId")

                // Call the existing AI processing method with watch flag
                Log.d(TAG, "📱 PHONE STEP 14: Calling AI model...")
                val result = processWatchEmergency(emergencyText)
                Log.d(TAG, "📱 PHONE STEP 15: AI processing completed!")
                Log.d(TAG, "📱 PHONE STEP 15: AI result: \"$result\"")

                if (result.isNotEmpty()) {
                    Log.d(TAG, "📱 PHONE STEP 16: AI processing successful, sending SMS to watch...")
                    sendSmsToWatch(nodeId, result)
                } else {
                    Log.e(TAG, "❌ PHONE STEP 15 FAILED: Empty AI result")
                    sendErrorToWatch("AI processing failed")
                }
            } catch (e: Exception) {
                Log.e(TAG, "Error processing emergency text", e)
                sendErrorToWatch("AI processing error: ${e.message}")
            }
        }
    }
    

    
    private suspend fun sendErrorToWatch(error: String) {
        withContext(Dispatchers.IO) {
            try {
                val putDataRequest = PutDataRequest.create(SMS_RESPONSE_PATH).apply {
                    val dataMap = DataMap().apply {
                        putString("error", error)
                        putBoolean("success", false)
                        putLong("timestamp", System.currentTimeMillis())
                    }
                    setData(dataMap.toByteArray())
                    setUrgent()
                }
                
                Wearable.getDataClient(this@WearDataListenerService)
                    .putDataItem(putDataRequest).await()
                
                Log.d(TAG, "Error sent to watch: $error")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send error to watch", e)
            }
        }
    }
    
    private suspend fun sendConnectionResponse(nodeId: String) {
        withContext(Dispatchers.IO) {
            try {
                Wearable.getMessageClient(this@WearDataListenerService)
                    .sendMessage(nodeId, CONNECTION_CHECK_PATH, "pong".toByteArray()).await()

                Log.d(TAG, "Connection response sent to watch")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to send connection response", e)
            }
        }
    }

    private suspend fun sendSmsToWatch(nodeId: String, smsText: String) {
        withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "📱 PHONE STEP 17: Sending SMS result to watch...")
                Log.d(TAG, "📱 SMS to send: \"$smsText\"")

                Wearable.getMessageClient(this@WearDataListenerService)
                    .sendMessage(nodeId, SMS_RESPONSE_PATH, smsText.toByteArray()).await()

                Log.d(TAG, "✅ PHONE STEP 17: SMS sent to watch successfully")
            } catch (e: Exception) {
                Log.e(TAG, "❌ PHONE STEP 17 FAILED: Failed to send SMS to watch", e)
            }
        }
    }
    
    // Real VOSK implementation for watch audio transcription
    private fun transcribeAudioWithVosk(audioFile: File): String {
        return try {
            Log.d(TAG, "📱 PHONE STEP 9: Starting VOSK transcription...")
            Log.d(TAG, "📱 Audio file: ${audioFile.absolutePath}")
            Log.d(TAG, "📱 Audio file exists: ${audioFile.exists()}")
            Log.d(TAG, "📱 Audio file size: ${audioFile.length()} bytes")

            // Check if audio file exists
            if (!audioFile.exists()) {
                Log.e(TAG, "❌ PHONE STEP 9 FAILED: Audio file does not exist")
                return ""
            }

            // Use MainActivity's VOSK transcription method
            val mainActivity = MainActivity.getInstance()
            if (mainActivity != null) {
                Log.d(TAG, "📱 PHONE STEP 9: Using MainActivity VOSK transcription...")
                val transcription = mainActivity.transcribeAudioWithVosk(audioFile.absolutePath)
                Log.d(TAG, "✅ PHONE STEP 9: VOSK transcription result: \"$transcription\"")
                return transcription
            } else {
                Log.e(TAG, "❌ PHONE STEP 9 FAILED: MainActivity instance not available")
                return "Emergency help needed"
            }

        } catch (e: Exception) {
            Log.e(TAG, "❌ PHONE STEP FAILED: Error during VOSK transcription", e)
            Log.e(TAG, "❌ Exception type: ${e.javaClass.simpleName}")
            Log.e(TAG, "❌ Exception message: ${e.message}")
            ""
        }
    }

    private suspend fun processWatchEmergency(text: String): String {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "📱 PHONE STEP 14: Starting AI processing for watch...")
                Log.d(TAG, "📱 Emergency text: \"$text\"")

                if (text.isEmpty()) {
                    Log.e(TAG, "❌ PHONE STEP 14 FAILED: Empty text provided")
                    return@withContext "🚨 EMERGENCY: Voice message received. Send help immediately."
                }

                // Get current location (simplified for watch)
                val location = "Location unavailable from watch"

                // Create emergency prompt for AI model
                val emergencyPrompt = """You are an emergency assistant. Given the following situation:

$text

Location: $location

1. Write a concise SMS message that the user can send to emergency services contact i want the sms to have the exact same situation that the user gave you, describing the situation and location make it as small as posible don't add any fancy contacts or thing just give the situation spotted points and the location only .

Format your response as:
SMS:
<the sms message here>"""

                Log.d(TAG, "📱 PHONE STEP 14: Calling AI model...")

                // Call the actual AI model using MainActivity's method
                val aiResponse = callAiModel(emergencyPrompt)

                // Extract SMS from AI response
                val smsMatch = Regex("SMS:\\s*(.+?)(?=\\n|$)", RegexOption.DOT_MATCHES_ALL).find(aiResponse)
                val emergencySms = smsMatch?.groupValues?.get(1)?.trim() ?: "🚨 EMERGENCY: $text. Send help immediately."

                Log.d(TAG, "✅ PHONE STEP 14: Generated SMS: \"$emergencySms\"")

                // Mock send SMS to 911
                mockSendSmsTo911(emergencySms)

                emergencySms

            } catch (e: Exception) {
                Log.e(TAG, "❌ AI processing failed", e)
                "🚨 EMERGENCY: $text. Send help immediately."
            }
        }
    }

    private suspend fun callAiModel(prompt: String): String {
        return withContext(Dispatchers.IO) {
            try {
                Log.d(TAG, "📱 Calling AI model with prompt...")

                // Create intent to call MainActivity's AI service
                val intent = Intent("com.example.myapp.AI_INFERENCE")
                intent.putExtra("prompt", prompt)
                intent.putExtra("imagePath", "")
                intent.putExtra("audioPath", "")
                intent.putExtra("latitude", 0.0)
                intent.putExtra("longitude", 0.0)

                // Use a more direct approach - call the native method directly
                val mainActivity = MainActivity.getInstance()
                if (mainActivity != null) {
                    return@withContext mainActivity.runLlmInferenceSync(prompt, null, null)
                } else {
                    Log.e(TAG, "❌ MainActivity instance not available")
                    return@withContext "SMS:\n🚨 EMERGENCY: Emergency situation detected. Send help immediately."
                }

            } catch (e: Exception) {
                Log.e(TAG, "❌ Error calling AI model: ${e.message}")
                return@withContext "SMS:\n🚨 EMERGENCY: Emergency situation detected. Send help immediately."
            }
        }
    }

    private fun mockSendSmsTo911(smsContent: String) {
        try {
            Log.d(TAG, "🚨 MOCK SMS TO 911: ================================")
            Log.d(TAG, "🚨 MOCK SMS TO 911: Starting emergency SMS send...")
            Log.d(TAG, "🚨 MOCK SMS TO 911: Recipient: 911")
            Log.d(TAG, "🚨 MOCK SMS TO 911: Content: \"$smsContent\"")
            Log.d(TAG, "🚨 MOCK SMS TO 911: Simulating network delay...")

            // Simulate SMS sending delay
            Thread.sleep(1000)

            Log.d(TAG, "✅ MOCK SMS TO 911: SMS SENT SUCCESSFULLY!")
            Log.d(TAG, "✅ MOCK SMS TO 911: Message delivered to emergency services")
            Log.d(TAG, "✅ MOCK SMS TO 911: Emergency response initiated")
            Log.d(TAG, "🚨 MOCK SMS TO 911: ================================")

        } catch (e: Exception) {
            Log.e(TAG, "❌ MOCK SMS TO 911: Failed to send SMS", e)
            Log.e(TAG, "❌ MOCK SMS TO 911: Emergency SMS delivery failed!")
        }
    }

    private fun copyAssetFolder(assetManager: android.content.res.AssetManager, fromAssetPath: String, toPath: String) {
        try {
            val files = assetManager.list(fromAssetPath) ?: return
            val toDir = File(toPath)
            if (!toDir.exists()) {
                toDir.mkdirs()
            }

            for (file in files) {
                val fromPath = "$fromAssetPath/$file"
                val toFile = File(toDir, file)

                if (assetManager.list(fromPath)?.isNotEmpty() == true) {
                    // It's a directory
                    copyAssetFolder(assetManager, fromPath, toFile.absolutePath)
                } else {
                    // It's a file
                    assetManager.open(fromPath).use { input ->
                        toFile.outputStream().use { output ->
                            input.copyTo(output)
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "❌ Error copying asset folder: ${e.message}")
        }
    }
    
    override fun onDestroy() {
        super.onDestroy()
        serviceScope.cancel()
    }
}
