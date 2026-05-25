package com.nuvio.app.core.storage

import com.nuvio.app.core.keychain.DesktopKeychain
import com.nuvio.app.desktop.DesktopPreferences
import java.nio.file.Path
import java.nio.file.Paths
import kotlin.io.path.deleteExisting
import kotlin.io.path.exists
import kotlin.io.path.isDirectory
import kotlin.io.path.listDirectoryEntries

internal actual object PlatformLocalAccountDataCleaner {
    private val preferenceNames = listOf(
        "nuvio_addons",
        "nuvio_library",
        "nuvio_home_catalog_settings",
        "nuvio_meta_screen_settings",
        "nuvio_player_settings",
        "nuvio_profile_cache",
        "nuvio_search_history",
        "nuvio_theme_settings",
        "nuvio_poster_card_style",
        "nuvio_mdblist_settings",
        "nuvio_trakt_auth",
        "nuvio_trakt_comments",
        "nuvio_trakt_library",
        "nuvio_watched",
        "nuvio_stream_link_cache",
        "nuvio_continue_watching_preferences",
        "nuvio_cw_enrichment",
        "nuvio_resume_prompt",
        "nuvio_episode_release_notifications",
        "nuvio_watch_progress",
        "nuvio_plugins",
        "nuvio_collections",
        "nuvio_downloads",
        "nuvio_tmdb_settings",
        "nuvio_season_view_mode",
    )

    actual fun wipe() {
        preferenceNames.forEach(DesktopPreferences::clearNode)
        DesktopKeychain.clearAll()
        clearJavaPrefsSession()
    }

    fun fullWipe() {
        wipe()
        deleteDirectory(Paths.get(System.getProperty("user.home"), "Library", "Caches", "com.nuvio.app"))
        deleteDirectory(Paths.get(System.getProperty("user.home"), "Library", "Caches", "Nuvio"))
        deleteDirectory(Paths.get(System.getProperty("user.home"), "Library", "Containers", "com.nuvio.media"))
        deleteDirectory(Paths.get(System.getProperty("user.home"), "Library", "Application Scripts", "com.nuvio.media"))
        deleteDirectory(Paths.get(System.getProperty("user.home"), "Library", "HTTPStorages", "com.nuvio.app"))
    }

    private fun clearJavaPrefsSession() {
        runCatching {
            java.util.prefs.Preferences.userRoot().remove("sb-dpyhjjcoabcglfmgecug-supabase-co-session")
            java.util.prefs.Preferences.userRoot().flush()
        }
    }

    private fun deleteDirectory(path: Path) {
        runCatching {
            if (path.isDirectory()) {
                path.listDirectoryEntries().forEach { child ->
                    deleteDirectory(child)
                }
            }
            if (path.exists()) {
                path.deleteExisting()
            }
        }
    }
}
