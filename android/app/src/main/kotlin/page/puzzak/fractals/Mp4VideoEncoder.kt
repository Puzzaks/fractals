package page.puzzak.fractals

import android.graphics.BitmapFactory
import android.graphics.Paint
import android.graphics.Rect
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaFormat
import android.media.MediaMuxer
import android.view.Surface
import java.io.File

class Mp4VideoEncoder(
    outputPath: String,
    width: Int,
    height: Int,
    fps: Int,
) {
    private val encWidth = (width and 1.inv()).coerceAtLeast(2)
    private val encHeight = (height and 1.inv()).coerceAtLeast(2)
    private val encFps = fps.coerceIn(1, 120)
    private val frameDurationUs = 1_000_000L / encFps

    private var codec: MediaCodec? = null
    private var inputSurface: Surface? = null
    private var muxer: MediaMuxer? = null
    private val bufferInfo = MediaCodec.BufferInfo()
    private val drawPaint = Paint(Paint.FILTER_BITMAP_FLAG)
    private val destRect = Rect(0, 0, encWidth, encHeight)

    private var trackIndex = -1
    private var muxerStarted = false
    private var nextOutputPtsUs = 0L
    private var released = false

    init {
        val outFile = File(outputPath)
        outFile.parentFile?.mkdirs()
        if (outFile.exists()) {
            outFile.delete()
        }

        val bitRate = (encWidth.toLong() * encHeight * encFps / 8L)
            .coerceIn(2_000_000L, 20_000_000L)
            .toInt()

        val format = MediaFormat.createVideoFormat(
            MediaFormat.MIMETYPE_VIDEO_AVC,
            encWidth,
            encHeight,
        ).apply {
            setInteger(
                MediaFormat.KEY_COLOR_FORMAT,
                MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface,
            )
            setInteger(MediaFormat.KEY_BIT_RATE, bitRate)
            setInteger(MediaFormat.KEY_FRAME_RATE, encFps)
            setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 1)
        }

        try {
            val encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            codec = encoder
            encoder.configure(format, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            inputSurface = encoder.createInputSurface()
            encoder.start()

            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
        } catch (e: Throwable) {
            release()
            throw e
        }
    }

    fun appendFrame(pngBytes: ByteArray) {
        check(!released) { "Encoder already released" }
        val surface = inputSurface ?: throw IllegalStateException("Encoder surface unavailable")
        val bitmap = BitmapFactory.decodeByteArray(pngBytes, 0, pngBytes.size)
            ?: throw IllegalArgumentException("Failed to decode PNG frame")
        try {
            val canvas = surface.lockCanvas(null)
            try {
                canvas.drawBitmap(bitmap, null, destRect, drawPaint)
            } finally {
                surface.unlockCanvasAndPost(canvas)
            }
        } finally {
            bitmap.recycle()
        }
        drainEncoder(endOfStream = false)
    }

    fun finish() {
        if (released) return
        try {
            drainEncoder(endOfStream = true)
            if (!muxerStarted) {
                throw IllegalStateException("Video encoder produced no output frames")
            }
        } finally {
            release()
        }
    }

    fun release() {
        if (released) return
        released = true
        try {
            codec?.stop()
        } catch (_: Exception) {}
        try {
            codec?.release()
        } catch (_: Exception) {}
        codec = null
        try {
            inputSurface?.release()
        } catch (_: Exception) {}
        inputSurface = null
        try {
            if (muxerStarted) {
                muxer?.stop()
            }
        } catch (_: Exception) {}
        try {
            muxer?.release()
        } catch (_: Exception) {}
        muxer = null
    }

    private fun drainEncoder(endOfStream: Boolean) {
        val encoder = codec ?: return
        val activeMuxer = muxer ?: return

        if (endOfStream) {
            encoder.signalEndOfInputStream()
        }

        var emptyPolls = 0
        while (true) {
            val outputBufferId = encoder.dequeueOutputBuffer(bufferInfo, 10_000L)
            when {
                outputBufferId == MediaCodec.INFO_TRY_AGAIN_LATER -> {
                    if (!endOfStream) {
                        break
                    }
                    emptyPolls++
                    if (emptyPolls > 200) {
                        break
                    }
                }

                outputBufferId == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                    if (!muxerStarted) {
                        trackIndex = activeMuxer.addTrack(encoder.outputFormat)
                        activeMuxer.start()
                        muxerStarted = true
                    }
                }

                outputBufferId >= 0 -> {
                    emptyPolls = 0
                    val encodedData = encoder.getOutputBuffer(outputBufferId)
                    if (encodedData != null) {
                        if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG) != 0) {
                            bufferInfo.size = 0
                        }
                        if (bufferInfo.size != 0 && muxerStarted) {
                            encodedData.position(bufferInfo.offset)
                            encodedData.limit(bufferInfo.offset + bufferInfo.size)
                            bufferInfo.presentationTimeUs = nextOutputPtsUs
                            nextOutputPtsUs += frameDurationUs
                            activeMuxer.writeSampleData(trackIndex, encodedData, bufferInfo)
                        }
                    }
                    encoder.releaseOutputBuffer(outputBufferId, false)
                    if ((bufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                        break
                    }
                }
            }
        }
    }
}
