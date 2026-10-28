package com.dineqr.customer

import android.content.ActivityNotFoundException
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ResolveInfo
import android.graphics.Bitmap
import android.graphics.Canvas
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.util.concurrent.Executors

/// The app, plus the `dineqr/upi` channel used by the payment screen
/// (lib/app/upi_launcher.dart): which UPI apps this phone has, with the name
/// and icon the guest knows them by, and opening a payment in the one the
/// guest picks.
class MainActivity : FlutterActivity() {
    private val background = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                // Icons take a moment to draw: off the main thread.
                "apps" -> background.execute {
                    val apps = try {
                        upiApps()
                    } catch (error: RuntimeException) {
                        null
                    }
                    main.post {
                        if (apps == null) {
                            result.error("failed", "Could not list the UPI apps", null)
                        } else {
                            result.success(apps)
                        }
                    }
                }
                "open" -> {
                    val link = call.argument<String>("link")
                    if (link == null) {
                        result.error("badLink", "No link to open", null)
                    } else {
                        result.success(open(link, call.argument<String>("package")))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onDestroy() {
        background.shutdown()
        super.onDestroy()
    }

    private fun upiHandlers(): List<ResolveInfo> {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("upi://pay"))
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            packageManager.queryIntentActivities(
                intent,
                PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_DEFAULT_ONLY.toLong()),
            )
        } else {
            @Suppress("DEPRECATION")
            packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        }
    }

    /// Every app that takes `upi://pay` links (seen thanks to the manifest's
    /// <queries>), once each: its package, name and icon (PNG).
    private fun upiApps(): List<Map<String, Any?>> =
        upiHandlers()
            .filter { it.activityInfo?.packageName.let { pkg -> pkg != null && pkg != packageName } }
            .distinctBy { it.activityInfo.packageName }
            .map { info ->
                mapOf(
                    "package" to info.activityInfo.packageName,
                    "label" to info.loadLabel(packageManager).toString(),
                    "icon" to iconOf(info),
                )
            }

    private fun iconOf(info: ResolveInfo): ByteArray? = try {
        val bitmap = Bitmap.createBitmap(ICON_PX, ICON_PX, Bitmap.Config.ARGB_8888)
        info.loadIcon(packageManager).apply {
            setBounds(0, 0, ICON_PX, ICON_PX)
            draw(Canvas(bitmap))
        }
        ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
            out.toByteArray()
        }
    } catch (error: RuntimeException) {
        null
    }

    /// Opens [link] in the app [pkg] (as Google documents for Google Pay:
    /// the plain `upi://pay` link sent to its package), or, with no package,
    /// lets the guest pick from every UPI app. Returns `opened`, `noApp` or
    /// `failed`. Opening says nothing about whether the guest pays.
    private fun open(link: String, pkg: String?): String {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(link))
        return try {
            if (pkg.isNullOrEmpty()) {
                if (upiHandlers().isEmpty()) return "noApp"
                startActivity(Intent.createChooser(intent, "Pay with"))
            } else {
                startActivity(intent.setPackage(pkg))
            }
            "opened"
        } catch (error: ActivityNotFoundException) {
            "noApp"
        } catch (error: SecurityException) {
            "failed"
        }
    }

    private companion object {
        const val CHANNEL = "dineqr/upi"

        // Shown at 36 logical pixels; this stays sharp up to 3x screens.
        const val ICON_PX = 108
    }
}
