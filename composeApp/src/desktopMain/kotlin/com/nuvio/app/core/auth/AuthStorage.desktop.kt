package com.nuvio.app.core.auth

import com.nuvio.app.core.keychain.DesktopKeychain

internal actual object AuthStorage {
    private const val KEYCHAIN_KEY = "auth_anonymous_user_id"

    actual fun loadAnonymousUserId(): String? =
        DesktopKeychain.get(KEYCHAIN_KEY)

    actual fun saveAnonymousUserId(userId: String) {
        DesktopKeychain.put(KEYCHAIN_KEY, userId)
    }

    actual fun clearAnonymousUserId() {
        DesktopKeychain.remove(KEYCHAIN_KEY)
    }
}