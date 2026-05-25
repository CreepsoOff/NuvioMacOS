package com.nuvio.app.features.notifications

import com.nuvio.app.core.deeplink.AppDeepLinkRepository
import java.io.File
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.launch

internal object NativeNotifications {
    private var loaded = false
    private val mainScope = MainScope()

    fun ensureLoaded() {
        if (loaded) return
        val dylib = findDylib()
        if (dylib != null) {
            System.load(dylib.absolutePath)
            loaded = true
        }
    }

    private fun findDylib(): File? {
        val appDir = System.getProperty("jna.library.path") ?: return null
        val dylib = File(appDir, "libnuvio-notify.dylib")
        return if (dylib.isFile) dylib else null
    }

    fun check(): Boolean {
        ensureLoaded()
        return if (loaded) nativeCheck() else false
    }

    fun requestAuthorization(): Boolean {
        ensureLoaded()
        return if (loaded) nativeRequestAuthorization() else false
    }

    fun show(title: String, body: String, deepLink: String? = null, backdropUrl: String? = null) {
        ensureLoaded()
        if (loaded) nativeShow(title, body, deepLink ?: "", backdropUrl ?: "")
    }

    fun clear() {
        ensureLoaded()
        if (loaded) nativeClear()
    }

    fun scheduleFromJson(json: String) {
        ensureLoaded()
        if (loaded) nativeScheduleFromJson(json)
    }

    @JvmStatic
    fun nativeHandleDeepLink(url: String) {
        mainScope.launch {
            AppDeepLinkRepository.handleUrl(url)
        }
    }

    private external fun nativeCheck(): Boolean
    private external fun nativeRequestAuthorization(): Boolean
    private external fun nativeShow(title: String, body: String, deepLink: String, backdropUrl: String)
    private external fun nativeClear()
    private external fun nativeScheduleFromJson(json: String)
}
