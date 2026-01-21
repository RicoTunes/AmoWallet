package com.cryptowallet.pro

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterFragmentActivity

/**
 * MILITARY-GRADE SECURITY: MainActivity with anti-screenshot protection
 */
class MainActivity : FlutterFragmentActivity() {
    
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        // MILITARY-GRADE: Prevent screenshots and screen recording
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
    
    override fun onResume() {
        super.onResume()
        // Re-apply FLAG_SECURE on resume to prevent bypass attempts
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
    }
}
