package com.remyo.razecheck
import org.junit.Test
import org.junit.Assert.*
import java.io.ByteArrayInputStream
import java.io.File
import java.io.IOException
import java.io.InputStream

class BoundedCopyTest {
    @Test fun unknownAndLyingMetadataAreBoundedAndPartialIsDeleted() {
        for (reported in listOf<Long?>(null, -1L, 1L)) {
            val file = File.createTempFile("raze-bounded-", ".test")
            try {
                boundedCopy(ByteArrayInputStream(ByteArray(65537)), file, 65536, reported)
                fail("over limit accepted")
            } catch (_: TransferLimitException) { assertFalse(file.exists()) }
        }
    }
    @Test fun excessiveMetadataNeverReadsAndUnavailableCleansPartial() {
        val file = File.createTempFile("raze-bounded-", ".test")
        val never = object : InputStream() { override fun read(): Int = throw AssertionError("read oversized metadata") }
        try { boundedCopy(never, file, 10, Long.MAX_VALUE); fail() }
        catch (_: TransferLimitException) { assertFalse(file.exists()) }
        val unavailable = object : InputStream() { override fun read(): Int = throw IOException("offline") }
        try { boundedCopy(unavailable, file, 10); fail() }
        catch (_: IOException) { assertFalse(file.exists()) }
    }
    @Test fun exactBoundCopiesAndClosesSource() {
        val file = File.createTempFile("raze-bounded-", ".test")
        var closed = false
        val source = object : ByteArrayInputStream(ByteArray(65536) { 42 }) { override fun close() { closed = true; super.close() } }
        try { boundedCopy(source, file, 65536); assertEquals(65536L, file.length()); assertTrue(closed); assertEquals(42, file.readBytes()[65535].toInt()) }
        finally { file.delete() }
    }
}
