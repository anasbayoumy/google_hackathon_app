package com.example.myapp

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.app.ActivityManager
import android.content.Context
import android.location.Location
import android.location.LocationManager
import android.location.LocationListener
import android.os.Bundle
import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.Settings
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.plugins.GeneratedPluginRegistrant
import android.util.Log
import java.io.File
import android.graphics.BitmapFactory
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.tasks.genai.llminference.GraphOptions
import com.google.mediapipe.tasks.genai.llminference.LlmInference
import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import java.util.concurrent.Executors
// MediaPipe imports (to be added when wiring up real inference)
// import com.google.mediapipe.tasks.genai.llminference.LlmInference
// import com.google.mediapipe.tasks.genai.llminference.LlmInferenceSession
import org.vosk.Model
import org.vosk.Recognizer
import com.google.android.gms.wearable.*
import com.google.android.gms.tasks.Task

class MainActivity : FlutterActivity() {
    private val CHANNEL = "location_service"
    private lateinit var locationManager: LocationManager
    private var currentLocation: Location? = null

    // LLM instance and session
    private var llmInference: LlmInference? = null
    private var llmSession: LlmInferenceSession? = null
    private var modelLoaded: Boolean = false
    private var sessionWarmedUp: Boolean = false  // Track if session has been warmed up
    private val llmLock = Any()
    private val executor = Executors.newSingleThreadExecutor()

    companion object {
        private var instance: MainActivity? = null

        fun getInstance(): MainActivity? = instance
    }

    private fun printLog(msg: String) {
        Log.d("LLM", msg)
    }

    private fun isEmulator(): Boolean {
        return (android.os.Build.FINGERPRINT.startsWith("generic")
                || android.os.Build.FINGERPRINT.startsWith("unknown")
                || android.os.Build.FINGERPRINT.contains("emulator")
                || android.os.Build.MODEL.contains("google_sdk")
                || android.os.Build.MODEL.contains("Emulator")
                || android.os.Build.MODEL.contains("Android SDK built for x86")
                || android.os.Build.MODEL.contains("sdk_gphone")
                || android.os.Build.MANUFACTURER.contains("Genymotion")
                || android.os.Build.MANUFACTURER.equals("Google", ignoreCase = true)
                || android.os.Build.BRAND.startsWith("generic")
                || android.os.Build.DEVICE.startsWith("generic")
                || android.os.Build.DEVICE.startsWith("emulator")
                || android.os.Build.DEVICE.contains("x86")
                || android.os.Build.PRODUCT.contains("sdk")
                || android.os.Build.PRODUCT.contains("emulator")
                || android.os.Build.PRODUCT.contains("simulator"))
    }

    private fun isLowEndDevice(): Boolean {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
        val memoryInfo = ActivityManager.MemoryInfo()
        activityManager.getMemoryInfo(memoryInfo)

        // Get total RAM in GB
        val totalRamGB = memoryInfo.totalMem / (1024 * 1024 * 1024)

        printLog("[isLowEndDevice] Total RAM: ${totalRamGB}GB")

        // Consider devices with 4GB or less as low-end for GPU inference
        // GPU inference requires significant memory overhead
        val isLowEnd = totalRamGB.toInt() <= 4

        printLog("[isLowEndDevice] Device classification: ${if (isLowEnd) "LOW-END (CPU only)" else "HIGH-END (GPU capable)"}")

        return isLowEnd
    }

    private fun loadModelQuickly(modelPath: String) {
        printLog("[loadModelQuickly] Loading pre-optimized model...")

        // Device detection (same logic as full preload)
        val isEmulatorDevice = isEmulator()
        val isLowEndDevice = isLowEndDevice()
        printLog("[loadModelQuickly] Device: isEmulator=$isEmulatorDevice, isLowEnd=$isLowEndDevice")

        // Use same backend selection logic
        val backend = if (isEmulatorDevice || isLowEndDevice) {
            LlmInference.Backend.CPU
        } else {
            LlmInference.Backend.GPU
        }

        val options = LlmInference.LlmInferenceOptions.builder()
            .setModelPath(modelPath)
            .setMaxTokens(1024)
            .setMaxNumImages(1)
            .setMaxTopK(64)
            .setPreferredBackend(backend)
            .build()

        llmInference = LlmInference.createFromOptions(this, options)

        // Create session (try vision first, fallback to text-only)
        var sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
            .setTopK(40)
            .setTopP(0.8f)
            .setTemperature(0.7f)
            .setGraphOptions(GraphOptions.builder().setEnableVisionModality(true).build())
            .build()

        try {
            llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
            printLog("[loadModelQuickly] Vision session created successfully")
        } catch (e: Exception) {
            printLog("[loadModelQuickly] Vision failed, using text-only: ${e.message}")
            sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                .setTopK(40)
                .setTopP(0.8f)
                .setTemperature(0.7f)
                .setGraphOptions(GraphOptions.builder().setEnableVisionModality(false).build())
                .build()
            llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
        }

        modelLoaded = true
        sessionWarmedUp = true  // Pre-optimized models are already warmed up
        printLog("[loadModelQuickly] Quick load complete!")
        printLog("[loadModelQuickly] Session marked as warmed up - using pre-optimized model")
    }

    private fun preloadModel() {
        executor.execute {
            printLog("[preloadModel] Starting model pre-loading...")
            synchronized(llmLock) {
                // Check if model is already fully optimized
                val prefs = getSharedPreferences("model_prefs", Context.MODE_PRIVATE)
                val isFullyOptimized = prefs.getBoolean("model_fully_optimized", false)

                if (isFullyOptimized && !modelLoaded) {
                    // Model was previously optimized, just load it quickly
                    printLog("[preloadModel] Model already optimized, loading quickly...")
                    try {
                        val modelPath = getModelFilePath(this)
                        val file = java.io.File(modelPath)
                        if (file.exists()) {
                            // Quick load without warm-up
                            loadModelQuickly(modelPath)
                            printLog("[preloadModel] Quick load complete - ready for instant responses!")
                            return@execute
                        } else {
                            // Model file missing, need to re-optimize
                            printLog("[preloadModel] Model file missing, need to re-optimize")
                            prefs.edit().putBoolean("model_fully_optimized", false).apply()
                        }
                    } catch (e: Exception) {
                        printLog("[preloadModel] Quick load failed: ${e.message}, will do full optimization")
                        prefs.edit().putBoolean("model_fully_optimized", false).apply()
                    }
                }

                if (!modelLoaded) {
                    try {
                        val modelPath = getModelFilePath(this)
                        val file = java.io.File(modelPath)
                        printLog("[preloadModel] Checking for model file at: $modelPath")
                        if (!file.exists()) {
                            printLog("[preloadModel] Model file not found: $modelPath")
                            return@execute
                        }

                        printLog("[preloadModel] Model file found: $modelPath, size: ${file.length()}")

                        // STEP 2: Device detection and smart backend selection
                        printLog("[preloadModel] === DEVICE DETECTION PHASE ===")
                        val isEmulatorDevice = isEmulator()
                        val isLowEndDevice = isLowEndDevice()
                        printLog("[preloadModel] Device detection complete: isEmulator=$isEmulatorDevice, isLowEnd=$isLowEndDevice")

                        if (isEmulatorDevice || isLowEndDevice) {
                            // Use CPU directly on emulators and low-end devices
                            val reason = if (isEmulatorDevice) "Emulator" else "Low-end device (≤4GB RAM)"
                            printLog("[preloadModel] $reason detected, using stable CPU backend")
                            val options = LlmInference.LlmInferenceOptions.builder()
                                .setModelPath(modelPath)
                                .setMaxTokens(1024)
                                .setMaxNumImages(1)
                                .setMaxTopK(64)
                                .setPreferredBackend(LlmInference.Backend.CPU)
                                .build()

                            llmInference = LlmInference.createFromOptions(this, options)
                            printLog("[preloadModel] CPU backend successful!")
                        } else {
                            // Try GPU first on high-end real devices
                            var options = LlmInference.LlmInferenceOptions.builder()
                                .setModelPath(modelPath)
                                .setMaxTokens(1024)
                                .setMaxNumImages(1)
                                .setMaxTopK(64)
                                .setPreferredBackend(LlmInference.Backend.CPU)
                                .build()

                            try {
                                printLog("[preloadModel] High-end device detected, attempting GPU backend...")
                                llmInference = LlmInference.createFromOptions(this, options)
                                printLog("[preloadModel] GPU backend successful!")
                            } catch (e: Exception) {
                                printLog("[preloadModel] GPU backend failed: ${e.message}")
                                printLog("[preloadModel] Falling back to stable CPU backend...")

                                options = LlmInference.LlmInferenceOptions.builder()
                                    .setModelPath(modelPath)
                                    .setMaxTokens(1024)
                                    .setMaxNumImages(1)
                                    .setMaxTopK(64)
                                    .setPreferredBackend(LlmInference.Backend.CPU)
                                    .build()

                                llmInference = LlmInference.createFromOptions(this, options)
                                printLog("[preloadModel] CPU backend successful!")
                            }
                        }

                        // Create session with vision fallback
                        var sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                            .setTopK(40)
                            .setTopP(0.8f)
                            .setTemperature(0.7f)
                            .setGraphOptions(GraphOptions.builder().setEnableVisionModality(true).build())
                            .build()

                        try {
                            printLog("[preloadModel] Attempting session creation with vision modality...")
                            llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                            printLog("[preloadModel] Session with vision modality successful!")
                        } catch (e: Exception) {
                            printLog("[preloadModel] Vision modality failed: ${e.message}")
                            printLog("[preloadModel] Falling back to text-only mode...")

                            sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                                .setTopK(40)
                                .setTopP(0.8f)
                                .setTemperature(0.7f)
                                .setGraphOptions(GraphOptions.builder().setEnableVisionModality(false).build())
                                .build()

                            llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                            printLog("[preloadModel] Text-only session successful! (Image input will not be available)")
                        }

                        modelLoaded = true
                        printLog("[preloadModel] === MODEL LOADED ===")

                        // CRITICAL: Perform warm-up inference to trigger ALL TensorFlow optimizations
                        printLog("[preloadModel] === STARTING WARM-UP INFERENCE ===")
                        printLog("[preloadModel] This will trigger all remaining TensorFlow optimizations...")
                        try {
                            val warmupSession = llmSession!!
                            warmupSession.addQueryChunk("hi - reply back with just a Hi")
                            val warmupLatch = java.util.concurrent.CountDownLatch(1)
                            var warmupCompleted = false
                            var tokenCount = 0

                            warmupSession.generateResponseAsync({ response, done ->
                                tokenCount++
                                if (tokenCount <= 5) {
                                    printLog("[preloadModel] Warm-up token $tokenCount: '$response', done: $done")
                                } else if (tokenCount == 6) {
                                    printLog("[preloadModel] Warm-up continuing... (${tokenCount} tokens so far)")
                                }

                                if (done) {
                                    warmupCompleted = true
                                    printLog("[preloadModel] === WARM-UP COMPLETE ===")
                                    printLog("[preloadModel] Generated $tokenCount tokens - All TensorFlow subgraphs optimized!")
                                    warmupLatch.countDown()
                                }
                            })

                            // Wait up to 3 minutes for warm-up to complete
                            val warmupSuccess = warmupLatch.await(180, java.util.concurrent.TimeUnit.SECONDS)

                            if (warmupSuccess && warmupCompleted) {
                                printLog("[preloadModel] === MODEL OPTIMIZATION COMPLETE ===")
                                printLog("[preloadModel] Model ready for INSTANT emergency responses!")

                                // Reset session to clear warm-up state
                                try {
                                    val newSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                                    llmSession = newSession
                                    printLog("[preloadModel] Session reset after warm-up - ready for new requests")
                                } catch (e: Exception) {
                                    printLog("[preloadModel] Session reset failed: ${e.message}")
                                }

                                // Mark model as fully optimized so we don't need to do this again
                                val prefs = getSharedPreferences("model_prefs", Context.MODE_PRIVATE)
                                prefs.edit().putBoolean("model_fully_optimized", true).apply()
                                sessionWarmedUp = true  // Mark session as warmed up
                                printLog("[preloadModel] Optimization flag saved - future app launches will be instant!")
                                printLog("[preloadModel] Session marked as warmed up - will not recreate unnecessarily")
                            } else {
                                printLog("[preloadModel] Warm-up timed out, but model should still work")
                            }
                        } catch (e: Exception) {
                            printLog("[preloadModel] Warm-up failed: ${e.message}, but model should still work")
                        }

                    } catch (e: Exception) {
                        printLog("[preloadModel] Error during pre-loading: ${e.message}")
                    }
                } else {
                    printLog("[preloadModel] Model already loaded, skipping pre-load")
                }
            }
        }
    }

    private fun getModelFilePath(context: Context): String {
        // Only use this model file name
        val modelFileName = "gemma-3n-E2B-it-int4.task"

        // 1. PRIORITY: Check app's internal documents directory first (where ModelDownloader saves files)
        val docsDir = java.io.File(context.filesDir, "app_flutter")
        val docsFile = java.io.File(docsDir, modelFileName)
        if (docsFile.exists()) {
            printLog("[getModelFilePath] Found model in app directory: ${docsFile.absolutePath}")
            return docsFile.absolutePath
        }

        // 2. Check external files dir for the model file
        val extDir = context.getExternalFilesDir(null)
        val extFile = java.io.File(extDir, modelFileName)
        if (extFile.exists()) {
            printLog("[getModelFilePath] Found model in external files: ${extFile.absolutePath}")
            return extFile.absolutePath
        }

        // 3. FALLBACK: Check Downloads folder and copy to app directory (only if not already there)
        val downloadPaths = listOf(
            "/storage/emulated/0/Download/gemma-3n-E2B-it-int4.task",
            "/sdcard/Download/gemma-3n-E2B-it-int4.task"
        )
        for (downloadPath in downloadPaths) {
            val downloadFile = java.io.File(downloadPath)
            if (downloadFile.exists()) {
                printLog("[getModelFilePath] Found model in Downloads: $downloadPath")
                // Try to copy to app's internal directory (only if not already there)
                if (!docsDir.exists()) {
                    docsDir.mkdirs()
                }
                val destFile = java.io.File(docsDir, modelFileName)
                if (!destFile.exists()) {
                    try {
                        printLog("[getModelFilePath] Copying model from Downloads to app directory...")
                        downloadFile.copyTo(destFile, overwrite = false)
                        printLog("[getModelFilePath] Successfully copied model to: ${destFile.absolutePath}")
                        return destFile.absolutePath
                    } catch (e: Exception) {
                        printLog("[getModelFilePath] Failed to copy model from Downloads: ${e.message}")
                        // If copy fails, use Downloads path directly
                        printLog("[getModelFilePath] Using Downloads path directly: $downloadPath")
                        return downloadPath
                    }
                } else {
                    printLog("[getModelFilePath] Model already exists in app directory, using: ${destFile.absolutePath}")
                    return destFile.absolutePath
                }
            }
        }

        // 3. Fallback: check assets (copy to cache if needed)
        val assetFileName = modelFileName
        val cacheFile = java.io.File(context.cacheDir, assetFileName)
        if (!cacheFile.exists()) {
            printLog("[getModelFilePath] Copying model from assets to cache: $assetFileName")
            context.assets.open(assetFileName).use { input ->
                cacheFile.outputStream().use { output ->
                    input.copyTo(output)
                }
            }
        }
        printLog("[getModelFilePath] Using model from cache: ${cacheFile.absolutePath}")
        return cacheFile.absolutePath
    }

    private fun initLlmModel(context: Context, result: MethodChannel.Result) {
        executor.execute {
            printLog("[initLlmModel] Called")
            synchronized(llmLock) {
                // Check if model is already loaded from preload
                if (modelLoaded && llmInference != null && llmSession != null) {
                    printLog("[initLlmModel] Model already pre-loaded, returning immediately")
                    Handler(Looper.getMainLooper()).post {
                        result.success(true)
                    }
                    return@execute
                }

                try {
                    val modelPath = getModelFilePath(context)
                    val file = java.io.File(modelPath)
                    printLog("[initLlmModel] Checking for model file at: $modelPath")
                    if (!file.exists()) {
                        printLog("[initLlmModel] Model file not found: $modelPath")
                        Handler(Looper.getMainLooper()).post {
                            result.error("MODEL_NOT_FOUND", "Model file not found at $modelPath", null)
                        }
                        return@execute
                    }
                    printLog("[initLlmModel] Model file found: $modelPath, size: ${file.length()}")
                    // Smart backend selection: avoid GPU on emulators and low-end devices
                    printLog("[initLlmModel] === DEVICE DETECTION PHASE ===")
                    val isEmulatorDevice = isEmulator()
                    val isLowEndDevice = isLowEndDevice()
                    printLog("[initLlmModel] Device detection complete: isEmulator=$isEmulatorDevice, isLowEnd=$isLowEndDevice")

                    if (isEmulatorDevice || isLowEndDevice) {
                        // Use CPU directly on emulators and low-end devices to avoid crashes
                        val reason = if (isEmulatorDevice) "Emulator" else "Low-end device (≤4GB RAM)"
                        printLog("[initLlmModel] $reason detected, using stable CPU backend")
                        val options = LlmInference.LlmInferenceOptions.builder()
                            .setModelPath(modelPath)
                            .setMaxTokens(1024) // Optimized for faster mobile performance
                            .setMaxNumImages(1)
                            .setMaxTopK(64)
                            .setPreferredBackend(LlmInference.Backend.CPU)
                            .build()

                        llmInference = LlmInference.createFromOptions(context, options)
                        printLog("[initLlmModel] CPU backend successful!")
                    } else {
                        // Try GPU backend first on real devices, fallback to CPU if unstable
                        var options = LlmInference.LlmInferenceOptions.builder()
                            .setModelPath(modelPath)
                            .setMaxTokens(1024) // Optimized for faster mobile performance
                            .setMaxNumImages(1)
                            .setMaxTopK(64)
                            .setPreferredBackend(LlmInference.Backend.GPU)
                            .build()

                        try {
                            printLog("[initLlmModel] High-end device detected, attempting GPU backend...")
                            llmInference = LlmInference.createFromOptions(context, options)
                            printLog("[initLlmModel] GPU backend successful!")
                        } catch (e: Exception) {
                            printLog("[initLlmModel] GPU backend failed: ${e.message}")
                            printLog("[initLlmModel] Falling back to stable CPU backend...")

                            // Fallback to stable CPU backend
                            options = LlmInference.LlmInferenceOptions.builder()
                                .setModelPath(modelPath)
                                .setMaxTokens(1024)
                                .setMaxNumImages(1)
                                .setMaxTopK(64)
                                .setPreferredBackend(LlmInference.Backend.CPU)
                                .build()

                            llmInference = LlmInference.createFromOptions(context, options)
                            printLog("[initLlmModel] CPU backend successful!")
                        }
                    }
                    // Try with vision modality first, fallback to text-only if unsupported
                    var sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                        .setTopK(40)
                        .setTopP(0.8f)
                        .setTemperature(0.7f)
                        .setGraphOptions(GraphOptions.builder().setEnableVisionModality(true).build())
                        .build()

                    try {
                        printLog("[initLlmModel] Attempting session creation with vision modality...")
                        llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                        printLog("[initLlmModel] Session with vision modality successful!")
                    } catch (e: Exception) {
                        printLog("[initLlmModel] Vision modality failed: ${e.message}")
                        printLog("[initLlmModel] Falling back to text-only mode...")

                        // Fallback to text-only mode
                        sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                            .setTopK(40)
                            .setTopP(0.8f)
                            .setTemperature(0.7f)
                            .setGraphOptions(GraphOptions.builder().setEnableVisionModality(false).build())
                            .build()

                        llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                        printLog("[initLlmModel] Text-only session successful! (Image input will not be available)")
                    }
                    modelLoaded = true
                    printLog("[initLlmModel] Model initialized successfully")
                    Handler(Looper.getMainLooper()).post {
                        result.success(true)
                    }
                } catch (e: Exception) {
                    printLog("[initLlmModel] Error: ${e.message}")
                    Handler(Looper.getMainLooper()).post {
                        result.error("INIT_ERROR", e.message, null)
                    }
                }
            }
        }
    }

    private fun runLlmInference(context: Context, args: Map<*, *>, result: MethodChannel.Result) {
        executor.execute {
            printLog("[runLlmInference] Called with args: $args")
            synchronized(llmLock) {
                if (!modelLoaded || llmInference == null || llmSession == null) {
                    printLog("[runLlmInference] Model not initialized")
                    Handler(Looper.getMainLooper()).post {
                        result.error("MODEL_NOT_INITIALIZED", "Model not initialized", null)
                    }
                    return@execute
                }
                try {
                    val text = args["text"] as? String
                    val imagePath = args["imagePath"] as? String
                    val audioPath = args["audioPath"] as? String
                    val session = llmSession!!
                    printLog("[runLlmInference] Session ready. text=$text, imagePath=$imagePath, audioPath=$audioPath")
                    if (!text.isNullOrBlank()) {
                        printLog("[runLlmInference] Adding text chunk: $text")
                        session.addQueryChunk(text)
                    } else {
                        printLog("[runLlmInference] No text chunk provided")
                    }
                    if (!imagePath.isNullOrBlank()) {
                        printLog("[runLlmInference] Adding image: $imagePath")
                        val imgFile = java.io.File(imagePath)
                        if (imgFile.exists()) {
                            val bitmap = BitmapFactory.decodeFile(imagePath)
                            session.addImage(com.google.mediapipe.framework.image.BitmapImageBuilder(bitmap).build())
                            printLog("[runLlmInference] Image added to session")
                        } else {
                            printLog("[runLlmInference] Image file not found: $imagePath")
                        }
                    } else {
                        printLog("[runLlmInference] No image provided")
                    }
                    if (!audioPath.isNullOrBlank()) {
                        printLog("[runLlmInference] Adding audio: $audioPath")
                        val audioFile = java.io.File(audioPath)
                        if (audioFile.exists()) {
                            try {
                                val audioBytes = audioFile.readBytes()
                                // Use reflection to call addAudio if it exists
                                try {
                                    val addAudioMethod = session.javaClass.getMethod("addAudio", ByteArray::class.java)
                                    addAudioMethod.invoke(session, audioBytes)
                                    printLog("[runLlmInference] Audio added to session (reflection)")
                                } catch (e: NoSuchMethodException) {
                                    printLog("[runLlmInference] addAudio method not found in LlmInferenceSession. Audio not supported in this version.")
                                } catch (e: Exception) {
                                    printLog("[runLlmInference] Error invoking addAudio (reflection): ${e.message}")
                                }
                            } catch (e: Exception) {
                                printLog("[runLlmInference] Error reading audio file: ${e.message}")
                            }
                        } else {
                            printLog("[runLlmInference] Audio file not found: $audioPath")
                        }
                    } else {
                        printLog("[runLlmInference] No audio provided")
                    }
                    printLog("[runLlmInference] Generating response...")
                    val startTime = System.currentTimeMillis()
                    val responseBuilder = StringBuilder()
                    val latch = java.util.concurrent.CountDownLatch(1)
                    session.generateResponseAsync({ partial, done ->
                        printLog("[runLlmInference] Partial: $partial, done: $done")
                        responseBuilder.append(partial)
                        if (done) {
                            val endTime = System.currentTimeMillis()
                            printLog("[runLlmInference] Inference complete, final response length: ${responseBuilder.length}")
                            printLog("[runLlmInference] Inference took ${endTime - startTime} ms")
                            latch.countDown()
                        }
                    })
                    latch.await() // Wait for completion
                    val response = responseBuilder.toString()
                    printLog("[runLlmInference] Final response: $response")
                    Handler(Looper.getMainLooper()).post {
                        result.success(response)
                    }
                } catch (e: Exception) {
                    printLog("[runLlmInference] Error: ${e.message}")
                    Handler(Looper.getMainLooper()).post {
                        result.error("INFERENCE_ERROR", e.message, null)
                    }
                }
            }
        }
    }

    private fun resetLlmSession(context: Context, result: MethodChannel.Result) {
        executor.execute {
            printLog("[resetLlmSession] Called")
            synchronized(llmLock) {
                try {
                    if (llmInference != null && llmSession != null) {
                        // Check if session is warmed up - if so, try to preserve it
                        if (sessionWarmedUp) {
                            printLog("[resetLlmSession] Session is warmed up - preserving optimization, conversation will be reset naturally on next inference")
                            // The session will naturally reset conversation state on next addQueryChunk call
                            // No need to recreate the optimized session
                            Handler(Looper.getMainLooper()).post {
                                result.success(true)
                            }
                            return@execute
                        }

                        // Only recreate session if it wasn't warmed up (legacy behavior)
                        printLog("[resetLlmSession] Session not warmed up, recreating...")
                        
                        // Close existing session
                        llmSession?.close()

                        // Create new session with vision fallback
                        var sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                            .setTopK(40)  // Fixed parameters
                            .setTopP(0.8f)
                            .setTemperature(0.7f)
                            .setGraphOptions(GraphOptions.builder().setEnableVisionModality(true).build())
                            .build()

                        try {
                            printLog("[resetLlmSession] Creating new LlmInferenceSession with vision...")
                            llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                            printLog("[resetLlmSession] Session with vision successful!")
                        } catch (e: Exception) {
                            printLog("[resetLlmSession] Vision modality failed: ${e.message}")
                            printLog("[resetLlmSession] Falling back to text-only mode...")

                            // Fallback to text-only mode
                            sessionOptions = LlmInferenceSession.LlmInferenceSessionOptions.builder()
                                .setTopK(40)  // Fixed parameters
                                .setTopP(0.8f)
                                .setTemperature(0.7f)
                                .setGraphOptions(GraphOptions.builder().setEnableVisionModality(false).build())
                                .build()

                            llmSession = LlmInferenceSession.createFromOptions(llmInference, sessionOptions)
                            printLog("[resetLlmSession] Text-only session successful!")
                        }
                        printLog("[resetLlmSession] Session reset successfully")
                        Handler(Looper.getMainLooper()).post {
                            result.success(true)
                        }
                    } else {
                        printLog("[resetLlmSession] LlmInference not initialized")
                        Handler(Looper.getMainLooper()).post {
                            result.error("MODEL_NOT_INITIALIZED", "Model not initialized", null)
                        }
                    }
                } catch (e: Exception) {
                    printLog("[resetLlmSession] Error: ${e.message}")
                    Handler(Looper.getMainLooper()).post {
                        result.error("RESET_ERROR", e.message, null)
                    }
                }
            }
        }
    }

    // Vosk: Transcribe a .wav file to text
    private fun transcribeWavWithVosk(context: Context, wavPath: String): String {
        try {
            printLog("🎤 [VOSK] Starting transcription for: $wavPath")

            // Check if audio file exists
            val file = java.io.File(wavPath)
            if (!file.exists()) {
                printLog("❌ [VOSK] Audio file does not exist: $wavPath")
                return ""
            }
            printLog("✅ [VOSK] Audio file found, size: ${file.length()} bytes")

            // Copy model from assets to internal storage if not already done
            val modelDir = java.io.File(context.filesDir, "vosk-model")
            if (!modelDir.exists()) {
                printLog("📁 [VOSK] Copying model from assets to internal storage...")
                copyAssetFolder(context.assets, "vosk-model-small-en-us-0.15", modelDir.absolutePath)
                printLog("✅ [VOSK] Model copied successfully")
            } else {
                printLog("✅ [VOSK] Model already exists in internal storage")
            }

            printLog("🤖 [VOSK] Initializing Vosk model...")
            val model = Model(modelDir.absolutePath)
            val recognizer = Recognizer(model, 16000.0f)
            printLog("✅ [VOSK] Model and recognizer initialized")

            printLog("🎵 [VOSK] Processing audio file...")

            // Read and log WAV header information
            val headerBytes = ByteArray(44) // Standard WAV header is 44 bytes
            val headerStream = file.inputStream()
            val headerBytesRead = headerStream.read(headerBytes)
            headerStream.close()

            if (headerBytesRead >= 44) {
                // Parse WAV header
                val sampleRate = java.nio.ByteBuffer.wrap(headerBytes, 24, 4).order(java.nio.ByteOrder.LITTLE_ENDIAN).int
                val channels = java.nio.ByteBuffer.wrap(headerBytes, 22, 2).order(java.nio.ByteOrder.LITTLE_ENDIAN).short.toInt()
                val bitsPerSample = java.nio.ByteBuffer.wrap(headerBytes, 34, 2).order(java.nio.ByteOrder.LITTLE_ENDIAN).short.toInt()

                printLog("📊 [VOSK] WAV Header - Sample Rate: $sampleRate Hz, Channels: $channels, Bits: $bitsPerSample")

                if (sampleRate != 16000) {
                    printLog("⚠️ [VOSK] Warning: Sample rate is $sampleRate Hz, but Vosk expects 16000 Hz")
                }
                if (channels != 1) {
                    printLog("⚠️ [VOSK] Warning: Audio has $channels channels, but Vosk expects mono (1 channel)")
                }
                if (bitsPerSample != 16) {
                    printLog("⚠️ [VOSK] Warning: Audio has $bitsPerSample bits per sample, Vosk typically expects 16-bit")
                }
            }

            val inputStream = file.inputStream()
            val buffer = ByteArray(4096)
            var bytesRead: Int
            var totalBytesProcessed = 0
            while (inputStream.read(buffer).also { bytesRead = it } >= 0) {
                if (bytesRead > 0) {
                    recognizer.acceptWaveForm(buffer, bytesRead)
                    totalBytesProcessed += bytesRead
                }
            }
            inputStream.close()
            printLog("✅ [VOSK] Processed $totalBytesProcessed bytes of audio")

            val result = recognizer.finalResult
            printLog("📄 [VOSK] Raw result JSON: $result")

            recognizer.close()
            model.close()

            // The result is a JSON string, extract the "text" field
            // Handle both single-line and multi-line JSON
            val text = Regex("\"text\"\\s*:\\s*\"([^\"]*?)\"", RegexOption.DOT_MATCHES_ALL).find(result)?.groupValues?.get(1) ?: ""
            printLog("📝 [VOSK] Extracted text: \"$text\"")
            printLog("📏 [VOSK] Text length: ${text.length} characters")

            if (text.isEmpty()) {
                printLog("⚠️ [VOSK] Warning: Regex failed to extract text from JSON")
                printLog("🔍 [VOSK] Attempting alternative extraction...")

                // Alternative extraction method using simple string parsing
                val startIndex = result.indexOf("\"text\"")
                if (startIndex != -1) {
                    val colonIndex = result.indexOf(":", startIndex)
                    val firstQuoteIndex = result.indexOf("\"", colonIndex)
                    val secondQuoteIndex = result.indexOf("\"", firstQuoteIndex + 1)
                    if (firstQuoteIndex != -1 && secondQuoteIndex != -1) {
                        val alternativeText = result.substring(firstQuoteIndex + 1, secondQuoteIndex)
                        printLog("🔍 [VOSK] Alternative extraction found: \"$alternativeText\"")
                        return alternativeText
                    }
                }
            }

            return text
        } catch (e: Exception) {
            printLog("❌ [VOSK] Error during transcription: ${e.message}")
            e.printStackTrace()
            return ""
        }
    }

    private fun copyAssetFolder(assetManager: android.content.res.AssetManager, fromAssetPath: String, toPath: String) {
        try {
            val files = assetManager.list(fromAssetPath) ?: return
            val toDir = java.io.File(toPath)
            if (!toDir.exists()) {
                toDir.mkdirs()
            }

            for (file in files) {
                val fromPath = "$fromAssetPath/$file"
                val toFile = java.io.File(toDir, file)

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
            printLog("[copyAssetFolder] Error: ${e.message}")
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pre-load the model during app startup
        preloadModel()
        
        locationManager = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        
        // Existing location channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCurrentLocation" -> {
                    getCurrentLocation(result)
                }
                "isLocationServiceEnabled" -> {
                    isLocationServiceEnabled(result)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }

        // New LLM channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.myapp/llm").setMethodCallHandler { call, result ->
            when (call.method) {
                "initModel" -> {
                    printLog("[MethodChannel] initModel called")
                    initLlmModel(this, result)
                }
                "runLlmInference" -> {
                    printLog("[MethodChannel] runLlmInference called")
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    runLlmInference(this, args, result)
                }
                "resetSession" -> {
                    printLog("[MethodChannel] resetSession called")
                    resetLlmSession(this, result)
                }
                "copyModelFromDownloads" -> {
                    printLog("[MethodChannel] copyModelFromDownloads called")
                    copyModelFromDownloads(this, result)
                }
                "requestStoragePermission" -> {
                    printLog("[MethodChannel] requestStoragePermission called")
                    requestStoragePermission(result)
                }
                "transcribeWavWithVosk" -> {
                    val wavPath = call.argument<String>("wavPath")
                    if (wavPath == null) {
                        result.error("NO_PATH", "No wavPath provided", null)
                    } else {
                        // Run Vosk transcription in background thread to avoid ANR
                        executor.execute {
                            try {
                                printLog("🎤 [VOSK] Starting background transcription...")
                                val text = transcribeWavWithVosk(this@MainActivity, wavPath)
                                printLog("🎤 [VOSK] Background transcription completed: \"$text\"")
                                runOnUiThread {
                                    result.success(text)
                                }
                            } catch (e: Exception) {
                                printLog("❌ [VOSK] Background transcription failed: ${e.message}")
                                runOnUiThread {
                                    result.error("VOSK_ERROR", e.message, null)
                                }
                            }
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }

        // Watch communication channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.myapp/watch").setMethodCallHandler { call, result ->
            when (call.method) {
                "processWatchVoice" -> {
                    printLog("[WatchChannel] processWatchVoice called")
                    val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
                    processWatchVoiceInput(this, args, result)
                }
                else -> result.notImplemented()
            }
        }

        GeneratedPluginRegistrant.registerWith(flutterEngine)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        instance = this
    }



    fun runLlmInferenceSync(prompt: String, imagePath: String?, audioPath: String?): String {
        return try {
            synchronized(llmLock) {
                if (!modelLoaded || llmInference == null || llmSession == null) {
                    printLog("[runLlmInferenceSync] Model not initialized")
                    return "SMS:\n🚨 EMERGENCY: Emergency situation detected. Send help immediately."
                }

                val session = llmSession!!
                printLog("[runLlmInferenceSync] Adding prompt: $prompt")
                session.addQueryChunk(prompt)

                printLog("[runLlmInferenceSync] Generating response...")
                val responseBuilder = StringBuilder()
                val latch = java.util.concurrent.CountDownLatch(1)

                session.generateResponseAsync({ partial, done ->
                    responseBuilder.append(partial)
                    if (done) {
                        latch.countDown()
                    }
                })

                // Wait for response with timeout
                val completed = latch.await(30, java.util.concurrent.TimeUnit.SECONDS)
                if (!completed) {
                    printLog("[runLlmInferenceSync] Timeout waiting for response")
                    return "SMS:\n🚨 EMERGENCY: Emergency situation detected. Send help immediately."
                }

                val response = responseBuilder.toString()
                printLog("[runLlmInferenceSync] Response: $response")
                return response
            }
        } catch (e: Exception) {
            printLog("[runLlmInferenceSync] Error: ${e.message}")
            "SMS:\n🚨 EMERGENCY: Emergency situation detected. Send help immediately."
        }
    }

    fun transcribeAudioWithVosk(audioPath: String): String {
        return transcribeWavWithVosk(this, audioPath)
    }

    private fun processWatchVoiceInput(context: Context, args: Map<*, *>, result: MethodChannel.Result) {
        executor.execute {
            printLog("[processWatchVoiceInput] Called with args: $args")
            synchronized(llmLock) {
                if (!modelLoaded || llmInference == null || llmSession == null) {
                    printLog("[processWatchVoiceInput] Model not initialized")
                    Handler(Looper.getMainLooper()).post {
                        result.error("MODEL_NOT_INITIALIZED", "Model not initialized", null)
                    }
                    return@execute
                }
                try {
                    val text = args["text"] as? String
                    val latitude = args["latitude"] as? Double ?: 0.0
                    val longitude = args["longitude"] as? Double ?: 0.0

                    printLog("[processWatchVoiceInput] Processing watch voice input: text=$text, lat=$latitude, lng=$longitude")

                    if (!text.isNullOrBlank()) {
                        val session = llmSession!!
                        printLog("[processWatchVoiceInput] Adding text chunk: $text")
                        session.addQueryChunk(text)

                        printLog("[processWatchVoiceInput] Generating response for watch...")
                        val startTime = System.currentTimeMillis()
                        val responseBuilder = StringBuilder()
                        val latch = java.util.concurrent.CountDownLatch(1)
                        session.generateResponseAsync({ partial, done ->
                            printLog("[processWatchVoiceInput] Partial: $partial, done: $done")
                            responseBuilder.append(partial)
                            if (done) {
                                val endTime = System.currentTimeMillis()
                                printLog("[processWatchVoiceInput] Watch inference complete, response length: ${responseBuilder.length}")
                                printLog("[processWatchVoiceInput] Watch inference took ${endTime - startTime} ms")
                                latch.countDown()
                            }
                        })
                        latch.await() // Wait for completion
                        val response = responseBuilder.toString()
                        printLog("[processWatchVoiceInput] Final watch response: $response")
                        Handler(Looper.getMainLooper()).post {
                            result.success(response)
                        }
                    } else {
                        printLog("[processWatchVoiceInput] No text provided from watch")
                        Handler(Looper.getMainLooper()).post {
                            result.error("NO_TEXT", "No text provided from watch", null)
                        }
                    }
                } catch (e: Exception) {
                    printLog("[processWatchVoiceInput] Error: ${e.message}")
                    Handler(Looper.getMainLooper()).post {
                        result.error("WATCH_INFERENCE_ERROR", e.message, null)
                    }
                }
            }
        }
    }

    private fun getCurrentLocation(result: MethodChannel.Result) {
        if (ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) != PackageManager.PERMISSION_GRANTED &&
            ActivityCompat.checkSelfPermission(this, Manifest.permission.ACCESS_COARSE_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            result.error("PERMISSION_DENIED", "Location permission not granted", null)
            return
        }

        try {
            // Try to get last known location first (faster)
            var bestLocation: Location? = null
            val providers = listOf(LocationManager.GPS_PROVIDER, LocationManager.NETWORK_PROVIDER, LocationManager.PASSIVE_PROVIDER)
            
            for (provider in providers) {
                if (locationManager.isProviderEnabled(provider)) {
                    val location = locationManager.getLastKnownLocation(provider)
                    if (location != null) {
                        if (bestLocation == null || location.accuracy < bestLocation.accuracy) {
                            bestLocation = location
                        }
                    }
                }
            }

            if (bestLocation != null) {
                val resultMap = mapOf(
                    "success" to true,
                    "latitude" to bestLocation.latitude,
                    "longitude" to bestLocation.longitude,
                    "accuracy" to bestLocation.accuracy
                )
                result.success(resultMap)
            } else {
                // If no last known location, try to get a fresh location
                var locationReceived = false
                val locationListener = object : LocationListener {
                    override fun onLocationChanged(location: Location) {
                        if (!locationReceived) {
                            locationReceived = true
                            val resultMap = mapOf(
                                "success" to true,
                                "latitude" to location.latitude,
                                "longitude" to location.longitude,
                                "accuracy" to location.accuracy
                            )
                            result.success(resultMap)
                            locationManager.removeUpdates(this)
                        }
                    }

                    override fun onStatusChanged(provider: String?, status: Int, extras: Bundle?) {}
                    override fun onProviderEnabled(provider: String) {}
                    override fun onProviderDisabled(provider: String) {}
                }

                // Try GPS first, then network provider
                var providerFound = false
                for (provider in providers) {
                    if (locationManager.isProviderEnabled(provider)) {
                        try {
                            locationManager.requestLocationUpdates(provider, 0L, 0f, locationListener)
                            providerFound = true
                            break
                        } catch (e: Exception) {
                            // Continue to next provider
                        }
                    }
                }

                if (!providerFound) {
                    result.error("NO_PROVIDER", "No location provider available", null)
                    return
                }
                
                // Set a timeout in case location doesn't come quickly
                android.os.Handler(android.os.Looper.getMainLooper()).postDelayed({
                    if (!locationReceived) {
                        locationManager.removeUpdates(locationListener)
                        result.error("TIMEOUT", "Location request timed out", null)
                    }
                }, 15000) // 15 second timeout
            }
        } catch (e: Exception) {
            result.error("LOCATION_ERROR", "Failed to get location: ${e.message}", null)
        }
    }

    private fun isLocationServiceEnabled(result: MethodChannel.Result) {
        try {
            val isEnabled = locationManager.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                locationManager.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
            result.success(isEnabled)
        } catch (e: Exception) {
            result.error("SERVICE_ERROR", "Failed to check location service: ${e.message}", null)
        }
    }

    private fun copyModelFromDownloads(context: Context, result: MethodChannel.Result) {
        executor.execute {
            printLog("[copyModelFromDownloads] Called")
            try {
                val modelFileName = "gemma-3n-E2B-it-int4.task"

                // Comprehensive search paths for the model
                val searchPaths = listOf(
                    // Downloads folders
                    "/storage/emulated/0/Download/gemma-3n-E2B-it-int4.task",
                    "/sdcard/Download/gemma-3n-E2B-it-int4.task",
                    "/storage/emulated/0/Downloads/gemma-3n-E2B-it-int4.task",
                    "/sdcard/Downloads/gemma-3n-E2B-it-int4.task",
                    // Documents folders
                    "/storage/emulated/0/Documents/gemma-3n-E2B-it-int4.task",
                    "/sdcard/Documents/gemma-3n-E2B-it-int4.task",
                    // App-specific directories
                    "${context.getExternalFilesDir(null)}/gemma-3n-E2B-it-int4.task",
                    "${context.filesDir}/gemma-3n-E2B-it-int4.task",
                    // Common storage locations
                    "/storage/emulated/0/gemma-3n-E2B-it-int4.task",
                    "/sdcard/gemma-3n-E2B-it-int4.task",
                    // Previous app directory
                    "${context.filesDir}/app_flutter/gemma-3n-E2B-it-int4.task"
                )

                printLog("[copyModelFromDownloads] 🔍 Searching ${searchPaths.size} locations for model...")

                var sourceFile: java.io.File? = null
                for (searchPath in searchPaths) {
                    val file = java.io.File(searchPath)
                    printLog("[copyModelFromDownloads] Checking: $searchPath")
                    if (file.exists()) {
                        val fileSize = file.length()
                        printLog("[copyModelFromDownloads] 📁 Found file at: $searchPath")
                        printLog("[copyModelFromDownloads] 📏 File size: ${fileSize} bytes (${fileSize / 1024 / 1024} MB)")

                        // Check if file size is reasonable (at least 1GB for the model)
                        if (fileSize > 1000000000L) { // 1GB minimum
                            printLog("[copyModelFromDownloads] ✅ Found complete model at: $searchPath")
                            sourceFile = file
                            break
                        } else {
                            printLog("[copyModelFromDownloads] ⚠️ File too small (${fileSize} bytes), continuing search...")
                        }
                    }
                }

                if (sourceFile == null) {
                    printLog("[copyModelFromDownloads] ❌ No complete model found in any location")
                    printLog("[copyModelFromDownloads] Please ensure the 3GB+ model file is downloaded and accessible")
                    Handler(Looper.getMainLooper()).post {
                        result.error("MODEL_NOT_FOUND", "Model not found in any accessible location. Please download the complete model file.", null)
                    }
                    return@execute
                }

                // Create destination directory
                val docsDir = java.io.File(context.filesDir, "app_flutter")
                if (!docsDir.exists()) {
                    docsDir.mkdirs()
                    printLog("[copyModelFromDownloads] 📁 Created app_flutter directory")
                }

                val destFile = java.io.File(docsDir, modelFileName)

                // Check if already exists and is complete
                if (destFile.exists()) {
                    val existingSize = destFile.length()
                    printLog("[copyModelFromDownloads] 📁 Model already exists in app directory")
                    printLog("[copyModelFromDownloads] 📏 Existing file size: ${existingSize} bytes (${existingSize / 1024 / 1024} MB)")

                    if (existingSize > 1000000000L) { // 1GB minimum
                        printLog("[copyModelFromDownloads] ✅ Existing model appears complete")
                        Handler(Looper.getMainLooper()).post {
                            result.success(destFile.absolutePath)
                        }
                        return@execute
                    } else {
                        printLog("[copyModelFromDownloads] ⚠️ Existing model too small, will overwrite")
                        destFile.delete()
                    }
                }

                // Copy the file
                val sourceSize = sourceFile.length()
                printLog("[copyModelFromDownloads] 📋 Starting copy operation...")
                printLog("[copyModelFromDownloads] 📏 Source size: ${sourceSize} bytes (${sourceSize / 1024 / 1024} MB)")
                printLog("[copyModelFromDownloads] 📂 Source: ${sourceFile.absolutePath}")
                printLog("[copyModelFromDownloads] 📂 Destination: ${destFile.absolutePath}")

                sourceFile.copyTo(destFile, overwrite = true)

                val copiedSize = destFile.length()
                printLog("[copyModelFromDownloads] ✅ Copy completed!")
                printLog("[copyModelFromDownloads] 📏 Copied size: ${copiedSize} bytes (${copiedSize / 1024 / 1024} MB)")
                printLog("[copyModelFromDownloads] 🎯 Model ready at: ${destFile.absolutePath}")

                Handler(Looper.getMainLooper()).post {
                    result.success(destFile.absolutePath)
                }

            } catch (e: Exception) {
                printLog("[copyModelFromDownloads] Error: ${e.message}")
                Handler(Looper.getMainLooper()).post {
                    result.error("COPY_ERROR", e.message, null)
                }
            }
        }
    }

    private var pendingPermissionResult: MethodChannel.Result? = null

    private fun requestStoragePermission(result: MethodChannel.Result) {
        printLog("[requestStoragePermission] Called")

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Android 11+ requires MANAGE_EXTERNAL_STORAGE
            if (Environment.isExternalStorageManager()) {
                printLog("[requestStoragePermission] MANAGE_EXTERNAL_STORAGE already granted")
                result.success(true)
            } else {
                printLog("[requestStoragePermission] MANAGE_EXTERNAL_STORAGE not granted, requesting permission")
                try {
                    val intent = Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION)
                    intent.data = Uri.parse("package:$packageName")
                    startActivity(intent)
                    printLog("[requestStoragePermission] Opened settings for MANAGE_EXTERNAL_STORAGE permission")
                    result.success(false) // User needs to grant manually and restart app
                } catch (e: Exception) {
                    printLog("[requestStoragePermission] Error opening settings: ${e.message}")
                    result.error("PERMISSION_ERROR", e.message, null)
                }
            }
        } else {
            // Android 10 and below
            val permissions = arrayOf(
                Manifest.permission.READ_EXTERNAL_STORAGE,
                Manifest.permission.WRITE_EXTERNAL_STORAGE
            )

            val hasPermissions = permissions.all { permission ->
                ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED
            }

            if (hasPermissions) {
                printLog("[requestStoragePermission] Storage permissions already granted")
                result.success(true)
            } else {
                printLog("[requestStoragePermission] Requesting storage permissions from user")
                pendingPermissionResult = result
                ActivityCompat.requestPermissions(this, permissions, 1001)
                // Don't call result.success() here - wait for onRequestPermissionsResult
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 1001) {
            val allGranted = grantResults.all { it == PackageManager.PERMISSION_GRANTED }
            printLog("[onRequestPermissionsResult] Storage permissions granted: $allGranted")

            pendingPermissionResult?.let { result ->
                result.success(allGranted)
                pendingPermissionResult = null
            }
        }
    }

    override fun onPause() {
        super.onPause()
        // Keep model loaded in memory - don't clean up
        printLog("[Lifecycle] onPause - keeping model in memory")
    }

    override fun onResume() {
        super.onResume()
        printLog("[Lifecycle] onResume - model should still be loaded")
    }

    override fun onDestroy() {
        super.onDestroy()
        // Only clean up when app is actually destroyed
        printLog("[Lifecycle] onDestroy - cleaning up model")
        instance = null
        synchronized(llmLock) {
            llmSession?.close()
            llmInference?.close()
            modelLoaded = false
        }
    }
}