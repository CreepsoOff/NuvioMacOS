package com.nuvio.app.features.profiles

import com.nuvio.app.core.keychain.DesktopKeychain

internal actual object ProfilePinCacheStorage {
    actual fun loadPayload(profileIndex: Int): String? =
        DesktopKeychain.get(payloadKey(profileIndex))

    actual fun savePayload(profileIndex: Int, payload: String) {
        DesktopKeychain.put(payloadKey(profileIndex), payload)
    }

    actual fun removePayload(profileIndex: Int) {
        DesktopKeychain.remove(payloadKey(profileIndex))
    }

    private fun payloadKey(profileIndex: Int): String = "profile_pin_cache_$profileIndex"
}
