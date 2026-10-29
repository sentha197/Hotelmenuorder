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
    private var upiChannel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        upiChannel = channel
        channel.setMethodCallHandler { call, result ->
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
                // The app itself, with no payment request: the guest starts
                // the payment there (see launchApp).
                "launch" -> result.success(launchApp(call.argument<String>("package")))
                else -> result.notImplemented()
            }
        }
    }

    /// A UPI app opened by [open] finished: its own report (the NPCI
    /// `response` extra, e.g. `Status=FAILURE`) goes to Dart, which only uses
    /// it to choose what to ask the guest. It is never proof of payment.
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != UPI_REQUEST) return
        upiChannel?.invokeMethod(
            "returned",
            mapOf("ok" to (resultCode == RESULT_OK), "response" to data?.getStringExtra("response")),
        )
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
                // Starting a link needs no visibility of the apps: when none
                // can be listed, hand it over plainly (it throws below when
                // no app takes it at all).
                startActivityForResult(
                    if (upiHandlers().isEmpty()) intent else Intent.createChooser(intent, "Pay with"),
                    UPI_REQUEST,
                )
            } else {
                startActivityForResult(intent.setPackage(pkg), UPI_REQUEST)
            }
            "opened"
        } catch (error: ActivityNotFoundException) {
            "noApp"
        } catch (error: SecurityException) {
            "failed"
        }
    }

    /// Opens the app [pkg] on its own home screen. Google Pay and PhonePe
    /// refuse a payment that another app fills in for a personal UPI ID
    /// (Google Pay says "You've exceeded the bank limit"), but a payment the
    /// guest starts in the app is an ordinary one. Returns `opened` or `noApp`.
    private fun launchApp(pkg: String?): String {
        val intent = pkg?.let { packageManager.getLaunchIntentForPackage(it) } ?: return "noApp"
        return try {
            startActivity(intent)
            "opened"
        } catch (error: ActivityNotFoundException) {
            "noApp"
        } catch (error: SecurityException) {
            "failed"
        }
    }

    private companion object {
        const val CHANNEL = "dineqr/upi"
        const val UPI_REQUEST = 4271

        // Shown at 36 logical pixels; this stays sharp up to 3x screens.
        const val ICON_PX = 108
    }
}
