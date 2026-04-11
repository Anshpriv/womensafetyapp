package com.womensaftey.app

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.widget.ImageButton
import android.widget.TextView
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity
import androidx.camera.core.CameraSelector
import androidx.camera.core.CompositionSettings
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.PendingRecording
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import java.io.File
import java.lang.ref.WeakReference

class DualCameraRecordingActivity : AppCompatActivity() {

    private lateinit var previewView: PreviewView
    private lateinit var statusText: TextView
    private lateinit var stopButton: ImageButton

    private var recording: Recording? = null
    private var cameraProvider: ProcessCameraProvider? = null
    private var outputPath: String? = null
    private val handler = Handler(Looper.getMainLooper())
    private var finishingRecording = false

    private val autoStopRunnable = Runnable {
        stopCurrentRecording()
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContentView(R.layout.activity_dual_camera_recording)

        currentInstance = WeakReference(this)

        previewView = findViewById(R.id.previewView)
        statusText = findViewById(R.id.statusText)
        stopButton = findViewById(R.id.stopButton)

        outputPath = intent.getStringExtra(EXTRA_OUTPUT_PATH)
        if (outputPath.isNullOrBlank()) {
            finish()
            return
        }

        stopButton.setOnClickListener {
            stopCurrentRecording()
        }

        if (!isConcurrentCameraSupported(this)) {
            Toast.makeText(
                this,
                "Dual camera recording is not supported on this device.",
                Toast.LENGTH_LONG
            ).show()
            finish()
            return
        }

        startDualCameraRecording()
    }

    private fun startDualCameraRecording() {
        statusText.text = "Starting dual camera recording..."

        val providerFuture = ProcessCameraProvider.getInstance(this)
        providerFuture.addListener(
            {
                try {
                    cameraProvider = providerFuture.get()
                    bindConcurrentCameras()
                } catch (e: Exception) {
                    storeRecordingError(this, e.message ?: "Failed to initialize dual camera.")
                    finish()
                }
            },
            ContextCompat.getMainExecutor(this)
        )
    }

    private fun bindConcurrentCameras() {
        val provider = cameraProvider ?: return
        val outputFile = File(outputPath!!)
        outputFile.parentFile?.mkdirs()

        val preview = Preview.Builder().build().also {
            it.surfaceProvider = previewView.surfaceProvider
        }

        val recorder = Recorder.Builder()
            .setQualitySelector(
                QualitySelector.from(
                    Quality.HD,
                    FallbackStrategyCompat.lowerQualityOrHigherThan(Quality.HD)
                )
            )
            .build()
        val videoCapture = VideoCapture.withOutput(recorder)
        val useCaseGroup = UseCaseGroup.Builder()
            .addUseCase(preview)
            .addUseCase(videoCapture)
            .build()

        val backConfig = androidx.camera.core.ConcurrentCamera.SingleCameraConfig(
            CameraSelector.DEFAULT_BACK_CAMERA,
            useCaseGroup,
            CompositionSettings.Builder()
                .setAlpha(1.0f)
                .setOffset(0.0f, 0.0f)
                .setScale(1.0f, 1.0f)
                .build(),
            this
        )

        val frontConfig = androidx.camera.core.ConcurrentCamera.SingleCameraConfig(
            CameraSelector.DEFAULT_FRONT_CAMERA,
            useCaseGroup,
            CompositionSettings.Builder()
                .setAlpha(1.0f)
                .setOffset(0.58f, -0.58f)
                .setScale(0.32f, 0.32f)
                .build(),
            this
        )

        provider.unbindAll()
        provider.bindToLifecycle(listOf(backConfig, frontConfig))

        val pendingRecording: PendingRecording = videoCapture.output
            .prepareRecording(this, FileOutputOptions.Builder(outputFile).build())
            .withAudioEnabled()

        recording = pendingRecording.start(ContextCompat.getMainExecutor(this)) { event ->
            when (event) {
                is VideoRecordEvent.Start -> {
                    statusText.text = "Dual recording active"
                    handler.postDelayed(autoStopRunnable, MAX_RECORDING_MS)
                }

                is VideoRecordEvent.Finalize -> {
                    handler.removeCallbacks(autoStopRunnable)
                    recording = null

                    if (event.hasError()) {
                        storeRecordingError(
                            this,
                            event.cause?.message ?: "Dual recording failed."
                        )
                        outputFile.delete()
                    } else {
                        storeCompletedRecordingPath(this, outputFile.absolutePath)
                    }

                    finishSafely()
                }
            }
        }
    }

    private fun stopCurrentRecording() {
        if (finishingRecording) return
        finishingRecording = true
        statusText.text = "Saving dual recording..."
        recording?.stop()
    }

    private fun finishSafely() {
        if (!isFinishing) {
            finish()
        }
    }

    override fun onBackPressed() {
        stopCurrentRecording()
    }

    override fun onDestroy() {
        handler.removeCallbacks(autoStopRunnable)
        if (currentInstance?.get() === this) {
            currentInstance = null
        }
        super.onDestroy()
    }

    companion object {
        private const val PREFS_NAME = "dual_camera_recording"
        private const val KEY_LAST_RECORDING_PATH = "last_recording_path"
        private const val KEY_LAST_RECORDING_ERROR = "last_recording_error"
        private const val EXTRA_OUTPUT_PATH = "output_path"
        private const val MAX_RECORDING_MS = 10 * 60 * 1000L

        private var currentInstance: WeakReference<DualCameraRecordingActivity>? = null

        fun createIntent(context: Context, outputPath: String): Intent {
            return Intent(context, DualCameraRecordingActivity::class.java).apply {
                putExtra(EXTRA_OUTPUT_PATH, outputPath)
            }
        }

        fun isConcurrentCameraSupported(context: Context): Boolean {
            return Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
                context.packageManager.hasSystemFeature(PackageManager.FEATURE_CAMERA_CONCURRENT)
        }

        fun stopActiveRecording() {
            currentInstance?.get()?.stopCurrentRecording()
        }

        fun isRecordingActive(): Boolean {
            return currentInstance?.get()?.recording != null
        }

        fun consumeLastRecordingPath(context: Context): String? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val path = prefs.getString(KEY_LAST_RECORDING_PATH, null)
            if (!path.isNullOrBlank()) {
                prefs.edit().remove(KEY_LAST_RECORDING_PATH).apply()
            }
            return path
        }

        fun consumeLastRecordingError(context: Context): String? {
            val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            val error = prefs.getString(KEY_LAST_RECORDING_ERROR, null)
            if (!error.isNullOrBlank()) {
                prefs.edit().remove(KEY_LAST_RECORDING_ERROR).apply()
            }
            return error
        }

        private fun storeCompletedRecordingPath(context: Context, path: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LAST_RECORDING_PATH, path)
                .remove(KEY_LAST_RECORDING_ERROR)
                .apply()
        }

        private fun storeRecordingError(context: Context, error: String) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_LAST_RECORDING_ERROR, error)
                .apply()
        }
    }
}

private object FallbackStrategyCompat {
    fun lowerQualityOrHigherThan(quality: Quality) =
        androidx.camera.video.FallbackStrategy.lowerQualityOrHigherThan(quality)
}
