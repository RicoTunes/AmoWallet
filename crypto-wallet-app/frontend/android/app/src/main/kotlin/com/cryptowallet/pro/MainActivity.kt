package com.cryptowallet.pro

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * MILITARY-GRADE SECURITY: MainActivity with configurable anti-screenshot protection
 */
class MainActivity : FlutterFragmentActivity() {
    
    private val CHANNEL = "com.amo.wallet/screenshot"
    private var isSecureFlagEnabled = true
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    val secure = call.argument<Boolean>("secure") ?: true
                    isSecureFlagEnabled = secure
                    applySecureFlag()
                    result.success(true)
                }
                "getSecureFlag" -> {
                    result.success(isSecureFlagEnabled)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // MILITARY-GRADE: Apply screenshot prevention based on setting
        applySecureFlag()
    }
    
    override fun onResume() {
        super.onResume()
        // Re-apply FLAG_SECURE on resume to prevent bypass attempts
        applySecureFlag()
    }
    
    private fun applySecureFlag() {
        if (isSecureFlagEnabled) {
            window.setFlags(
                WindowManager.LayoutParams.FLAG_SECURE,
                WindowManager.LayoutParams.FLAG_SECURE
            )
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }
}
