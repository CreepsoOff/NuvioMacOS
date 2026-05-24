package com.nuvio.app.features.home.components

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asComposeImageBitmap
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import io.ktor.client.HttpClient
import io.ktor.client.request.prepareGet
import io.ktor.client.statement.bodyAsBytes
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Codec
import org.jetbrains.skia.Data

private data class GifFrame(val bitmap: ImageBitmap, val delayMs: Int)

private object DesktopAnimatedGifCache {
    private val cache = mutableMapOf<String, List<GifFrame>>()

    fun get(url: String): List<GifFrame>? = cache[url]

    fun set(url: String, frames: List<GifFrame>) {
        cache[url] = frames
    }
}

private suspend fun decodeGifFrames(bytes: ByteArray): List<GifFrame> = withContext(Dispatchers.IO) {
    val data = Data.makeFromBytes(bytes)
    val codec = Codec.makeFromData(data) ?: return@withContext emptyList()

    val frameCount = codec.frameCount
    val frames = mutableListOf<GifFrame>()

    for (i in 0 until frameCount) {
        val frameInfo = codec.getFrameInfo(i)
        val bitmap = Bitmap()
        bitmap.allocPixels(codec.imageInfo)
        codec.readPixels(bitmap, i)
        frames.add(
            GifFrame(
                bitmap = bitmap.asComposeImageBitmap(),
                delayMs = frameInfo.duration.coerceAtLeast(20),
            )
        )
    }

    frames
}

@Composable
internal actual fun CollectionCardRemoteImage(
    imageUrl: String,
    contentDescription: String,
    modifier: Modifier,
    contentScale: ContentScale,
    animateIfPossible: Boolean,
) {
    val isAnimated = animateIfPossible && imageUrl.endsWith(".gif", ignoreCase = true)

    if (!isAnimated) {
        AsyncImage(
            model = imageUrl,
            contentDescription = contentDescription,
            modifier = modifier,
            contentScale = contentScale,
        )
        return
    }

    var state by remember { mutableStateOf<Any?>(null) }

    LaunchedEffect(imageUrl) {
        state = DesktopAnimatedGifCache.get(imageUrl)
        if (state != null) return@LaunchedEffect
        val client = HttpClient()
        try {
            val bytes = client.prepareGet(imageUrl).execute().bodyAsBytes()
            val frames = decodeGifFrames(bytes)
            DesktopAnimatedGifCache.set(imageUrl, frames)
            state = frames
        } catch (_: Exception) {
            state = Unit
        }
    }

    when (val s = state) {
        is List<*> -> {
            @Suppress("UNCHECKED_CAST")
            val frames = s as List<GifFrame>
            if (frames.isEmpty()) {
                AsyncImage(model = imageUrl, contentDescription = contentDescription, modifier = modifier, contentScale = contentScale)
            } else {
                var frameIndex by remember { mutableIntStateOf(0) }
                LaunchedEffect(frames) {
                    while (isActive) {
                        val frame = frames[frameIndex]
                        kotlinx.coroutines.delay(frame.delayMs.toLong())
                        frameIndex = (frameIndex + 1) % frames.size
                    }
                }
                Box(modifier = modifier, contentAlignment = Alignment.Center) {
                    AsyncImage(
                        model = imageUrl,
                        contentDescription = contentDescription,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = contentScale,
                    )
                    Image(
                        bitmap = frames[frameIndex].bitmap,
                        contentDescription = contentDescription,
                        modifier = Modifier.fillMaxSize(),
                        contentScale = contentScale,
                    )
                }
            }
        }
        null -> {
            AsyncImage(model = imageUrl, contentDescription = contentDescription, modifier = modifier, contentScale = contentScale)
        }
        else -> {
            AsyncImage(model = imageUrl, contentDescription = contentDescription, modifier = modifier, contentScale = contentScale)
        }
    }
}
