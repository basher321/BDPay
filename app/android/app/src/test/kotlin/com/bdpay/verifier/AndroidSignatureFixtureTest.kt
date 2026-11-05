package com.bdpay.verifier

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.security.KeyPairGenerator
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64

/**
 * Spec 13a cross-check: signs a sample sms-ingest request exactly like the phone (P-256, SHA256withECDSA, DER) and
 * writes supabase/functions/tests/fixtures/android_signature.json for the Deno test (device_auth.ts) to verify.
 * The key pair exists only in memory; the fixture holds public data only.
 */
class AndroidSignatureFixtureTest {
    private fun repoRoot(): File {
        var dir: File? = File(".").absoluteFile
        while (dir != null && !File(dir, "supabase/functions").isDirectory) dir = dir.parentFile
        return dir ?: error("repo root not found")
    }

    @Test
    fun writesASignedSampleRequest() {
        val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        val functionName = UploadRun.FUNCTION
        val timestamp = 1_761_800_000_000L
        val body = UploadBatch.body(
            listOf(
                QueueRow(
                    id = "local-1",
                    sender = "16216",
                    body = "Tk1,500.00 received from 017123456789 for A/C: 019876543211. Fee Tk0.00, Balance Tk5,600.00. TxnId: 24010200123",
                    receivedAtMs = timestamp - 60_000,
                    simSlot = "sim1",
                    dedupeHash = "0".repeat(64),
                    syncStatus = "queued",
                    verifyStatus = "pending",
                    retryCount = 0,
                    serverSmsId = null,
                    createdAtMs = timestamp - 60_000,
                ),
            ),
        )
        val signature = Signature.getInstance("SHA256withECDSA").run {
            initSign(pair.private)
            update(SignedText.of(functionName, timestamp, body).toByteArray(Charsets.UTF_8))
            sign()
        }
        assertTrue("DER starts with SEQUENCE", signature[0] == 0x30.toByte())
        val b64 = Base64.getEncoder()
        val fields = linkedMapOf(
            "note" to "Written by AndroidSignatureFixtureTest (spec 13a). Test key, public data only.",
            "publicKeySpki" to b64.encodeToString(pair.public.encoded),
            "functionName" to functionName,
            "timestamp" to timestamp.toString(),
            "body" to body.toString(Charsets.UTF_8),
            "signature" to b64.encodeToString(signature),
        )
        // One key per line, two-space indent: the layout deno fmt keeps, so `deno fmt --check` passes.
        val fixture = fields.entries.joinToString(",\n", "{\n", "\n}") { (k, v) ->
            "  ${JsonWriter.write(k)}: ${JsonWriter.write(v)}"
        }
        val out = File(repoRoot(), "supabase/functions/tests/fixtures/android_signature.json")
        out.parentFile.mkdirs()
        out.writeText(fixture + "\n", Charsets.UTF_8)
        assertTrue(out.length() > 0)
    }
}
