package com.bdpay.verifier

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.util.Base64
import java.util.UUID

/**
 * Spec 13a: the phone's own P-256 key, created inside the Android Keystore (sign only, SHA-256). The private key
 * cannot be exported and no method here returns it; only the public key (SPKI) and signatures leave this object.
 * Nothing is logged.
 */
object DeviceKeys {
    private const val ALIAS = "bdpay_device_key_v1"
    private const val PROVIDER = "AndroidKeyStore"
    private const val PREFS = "bdpay_device"
    private const val KEY_INSTALL_ID = "install_id"

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    @Synchronized
    private fun ensureKey(store: KeyStore) {
        if (store.containsAlias(ALIAS)) return
        val spec = KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .build()
        KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER).run {
            initialize(spec)
            generateKeyPair()
        }
    }

    /** The X.509 SubjectPublicKeyInfo of the public key, base64 (what device-register stores). */
    fun publicKeySpki(): String {
        val store = keyStore()
        ensureKey(store)
        return Base64.getEncoder().encodeToString(store.getCertificate(ALIAS).publicKey.encoded)
    }

    /** SHA256withECDSA over [text], DER, base64. */
    fun sign(text: String): String {
        val store = keyStore()
        ensureKey(store)
        val entry = store.getEntry(ALIAS, null) as KeyStore.PrivateKeyEntry
        val sig = Signature.getInstance("SHA256withECDSA").run {
            initSign(entry.privateKey)
            update(text.toByteArray(Charsets.UTF_8))
            sign()
        }
        return Base64.getEncoder().encodeToString(sig)
    }

    /** A UUID made once per install and kept; the server keeps the same device for the same installId. */
    @Synchronized
    fun installId(context: Context): String {
        val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        prefs.getString(KEY_INSTALL_ID, null)?.let { return it }
        val id = UUID.randomUUID().toString()
        prefs.edit().putString(KEY_INSTALL_ID, id).commit()
        return id
    }
}
