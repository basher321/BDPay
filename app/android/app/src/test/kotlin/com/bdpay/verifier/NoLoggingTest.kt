package com.bdpay.verifier

import org.junit.Assert.assertEquals
import org.junit.Test
import java.io.File

/** Spec 13a: no logging anywhere in the native code, and the private key is never read out of the Keystore. */
class NoLoggingTest {
    private val sources = File("src/main/kotlin").walkTopDown().filter { it.extension == "kt" }.toList()

    @Test
    fun noLogCallsInTheKotlinSources() {
        val bad = Regex("""\bandroid\.util\.Log\b|\bLog\.(v|d|i|w|e|wtf)\(|\bprintln\(|\bprint\(|\.printStackTrace\(|System\.(out|err)""")
        val offenders = sources.filter { bad.containsMatchIn(it.readText()) }.map { it.name }
        assertEquals(emptyList<String>(), offenders)
    }

    @Test
    fun channelErrorsNeverCarryAnExceptionMessage() {
        // A PlatformException message can end up in Flutter's error log.
        val bad = Regex("""\.error\([^)]*(\.message|\.localizedMessage|toString\(\))""")
        val offenders = sources.filter { bad.containsMatchIn(it.readText()) }.map { it.name }
        assertEquals(emptyList<String>(), offenders)
    }

    @Test
    fun noPrivateKeyMaterialIsRead() {
        val bad = Regex("""privateKey\??\.encoded|\.getPrivate\(\)\.encoded|PrivateKey\)\.encoded""")
        val offenders = sources.filter { bad.containsMatchIn(it.readText()) }.map { it.name }
        assertEquals(emptyList<String>(), offenders)
    }
}
