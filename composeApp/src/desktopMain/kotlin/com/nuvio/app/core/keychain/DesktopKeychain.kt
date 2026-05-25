package com.nuvio.app.core.keychain

import java.io.BufferedReader
import java.io.InputStreamReader

internal object DesktopKeychain {
    private const val SERVICE_PREFIX = "com.nuvio.app"

    fun put(key: String, value: String) {
        exec(
            "security", "add-generic-password",
            "-a", System.getProperty("user.name"),
            "-s", prefixed(key),
            "-w", value,
            "-U",
        )
    }

    fun get(key: String): String? {
        val process = exec(
            "security", "find-generic-password",
            "-a", System.getProperty("user.name"),
            "-s", prefixed(key),
            "-w",
        )
        val output = process.inputStream.bufferedReader().readText().trim()
        return output.ifEmpty { null }
    }

    fun remove(key: String) {
        exec(
            "security", "delete-generic-password",
            "-a", System.getProperty("user.name"),
            "-s", prefixed(key),
        )
    }

    fun contains(key: String): Boolean =
        get(key) != null

    fun clearAll() {
        val process = exec("security", "dump-keychain")
        val output = process.inputStream.bufferedReader().readText()
        val pattern = "\"svce\"<blob>=\"$SERVICE_PREFIX".replace(".", "\\.")
        val lines = output.lines().filter { it.contains("\"svce\"<blob>=\"$SERVICE_PREFIX") }
        for (line in lines) {
            val match = Regex("\"svce\"<blob>=\"($SERVICE_PREFIX[^\"]+)\"").find(line)
            val serviceName = match?.groupValues?.getOrNull(1) ?: continue
            exec("security", "delete-generic-password", "-s", serviceName)
        }
    }

    private fun prefixed(key: String): String = "${SERVICE_PREFIX}_$key"

    private fun exec(vararg command: String): Process {
        val process = Runtime.getRuntime().exec(command)
        val exitCode = process.waitFor()
        if (exitCode != 0) {
            val error = process.errorStream.bufferedReader().readText().trim()
            if (exitCode != 44 && error.isNotBlank()) {
                System.err.println("Keychain error (exit=$exitCode): $error")
            }
        }
        return process
    }
}
