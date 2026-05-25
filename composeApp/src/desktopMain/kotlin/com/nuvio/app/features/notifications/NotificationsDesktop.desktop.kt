package com.nuvio.app.features.notifications

import com.nuvio.app.core.storage.ProfileScopedKey
import com.nuvio.app.desktop.DesktopPreferences
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

internal actual object EpisodeReleaseNotificationsStorage {
    private const val preferencesName = "nuvio_episode_release_notifications"
    private const val payloadKey = "episode_release_notifications_payload"

    actual fun loadPayload(): String? =
        DesktopPreferences.getString(preferencesName, ProfileScopedKey.of(payloadKey))

    actual fun savePayload(payload: String) {
        DesktopPreferences.putString(preferencesName, ProfileScopedKey.of(payloadKey), payload)
    }
}

internal actual object EpisodeReleaseNotificationPlatform {
    private const val scheduledIdsKey = "episode_release_notification_scheduled_ids"

    actual suspend fun notificationsAuthorized(): Boolean {
        return runCatching { NativeNotifications.check() }.getOrDefault(false)
    }

    actual suspend fun requestAuthorization(): Boolean {
        return runCatching { NativeNotifications.requestAuthorization() }.getOrDefault(false)
    }

    actual suspend fun scheduleEpisodeReleaseNotifications(requests: List<EpisodeReleaseNotificationRequest>) {
        withContext(Dispatchers.IO) {
            NativeNotifications.clear()
            if (requests.isEmpty()) return@withContext

            val json = buildScheduleJson(requests)
            NativeNotifications.scheduleFromJson(json)

            val ids = requests.map { it.requestId }
            DesktopPreferences.putString(
                namespace = "episode_release_notifications",
                key = ProfileScopedKey.of(scheduledIdsKey),
                value = ids.joinToString("|"),
            )
        }
    }

    actual suspend fun clearScheduledEpisodeReleaseNotifications() {
        withContext(Dispatchers.IO) {
            NativeNotifications.clear()
        }
    }

    actual suspend fun showTestNotification(request: EpisodeReleaseNotificationRequest) {
        withContext(Dispatchers.IO) {
            NativeNotifications.show(
                title = request.notificationTitle,
                body = request.notificationBody,
                deepLink = request.deepLinkUrl.takeIf { it.isNotBlank() },
                backdropUrl = request.backdropUrl?.takeIf { it.isNotBlank() },
            )
        }
    }

    private fun buildScheduleJson(requests: List<EpisodeReleaseNotificationRequest>): String {
        val sb = StringBuilder("[")
        requests.forEachIndexed { i, r ->
            if (i > 0) sb.append(",")
            sb.append("{\"id\":\"${escapeJson(r.requestId)}\",\"title\":\"${escapeJson(r.notificationTitle)}\",\"body\":\"${escapeJson(r.notificationBody)}\",\"dateIso\":\"${r.releaseDateIso}\"")
            if (r.deepLinkUrl.isNotBlank()) {
                sb.append(",\"deepLink\":\"${escapeJson(r.deepLinkUrl)}\"")
            }
            val backdrop = r.backdropUrl?.takeIf { it.isNotBlank() }
            if (backdrop != null) {
                sb.append(",\"backdropUrl\":\"${escapeJson(backdrop)}\"")
            }
            sb.append("}")
        }
        sb.append("]")
        return sb.toString()
    }

    private fun escapeJson(s: String): String =
        s.replace("\\", "\\\\").replace("\"", "\\\"")
            .replace("\n", "\\n").replace("\r", "\\r").replace("\t", "\\t")
}

internal actual object EpisodeReleaseNotificationsClock {
    actual fun isoDateFromEpochMs(epochMs: Long): String =
        Instant.ofEpochMilli(epochMs)
            .atZone(ZoneId.systemDefault())
            .toLocalDate()
            .toString()
}