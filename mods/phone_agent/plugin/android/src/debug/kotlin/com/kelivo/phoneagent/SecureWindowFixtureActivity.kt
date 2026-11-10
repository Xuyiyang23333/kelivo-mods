package com.kelivo.phoneagent

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.view.Gravity
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.FrameLayout
import android.widget.TextView

/**
 * Debug-only fixture for real FLAG_SECURE and system permission-window tests.
 *
 * It is compiled into the debug variant only and is never part of a release
 * build. The activity never grants a permission and never records audio; it
 * only asks for the already-declared POST_NOTIFICATIONS permission so the
 * system permission window can be observed on API 33+.
 */
class SecureWindowFixtureActivity : Activity() {
    companion object {
        const val EXTRA_SECURE = "secure"
        const val EXTRA_REQUEST_PERMISSION = "requestPermission"
        const val FIXTURE_TEXT = "PHONE_AGENT_SECURE_FIXTURE"

        private const val PERMISSION_REQUEST_CODE = 41
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applySecureFlag(intent)
        val root = FrameLayout(this).apply {
            setBackgroundColor(Color.rgb(0, 200, 255))
        }
        val label = TextView(this).apply {
            text = FIXTURE_TEXT
            setTextColor(Color.BLACK)
            textSize = 24f
        }
        root.addView(
            label,
            FrameLayout.LayoutParams(
                ViewGroup.LayoutParams.WRAP_CONTENT,
                ViewGroup.LayoutParams.WRAP_CONTENT,
                Gravity.CENTER,
            ),
        )
        setContentView(root)
        requestPermissionIfNeeded(intent)
    }

    override fun onNewIntent(intent: Intent?) {
        super.onNewIntent(intent)
        setIntent(intent)
        applySecureFlag(intent)
        requestPermissionIfNeeded(intent)
    }

    private fun applySecureFlag(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_SECURE, false) == true) {
            window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        }
    }

    private fun requestPermissionIfNeeded(intent: Intent?) {
        if (intent?.getBooleanExtra(EXTRA_REQUEST_PERMISSION, false) != true) {
            return
        }
        if (Build.VERSION.SDK_INT < 33) return
        if (checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            requestPermissions(
                arrayOf(Manifest.permission.POST_NOTIFICATIONS),
                PERMISSION_REQUEST_CODE,
            )
        }
    }
}
