package com.bdpay.verifier

/**
 * Plan 13a D171: an unsent row belongs to the merchant that was registered on this phone when it was caught.
 * When another merchant registers here, those rows are held for their own merchant: never uploaded, listed or
 * counted under the new one, and released when their own merchant registers again. held = merchantId -> row ids.
 * Pure.
 */
object MerchantHold {
    /** The held map after [newMerchant] registers; [owner] = the merchant registered before, [pendingIds] = unsent rows. */
    fun onRegister(
        owner: String?,
        newMerchant: String,
        held: Map<String, Set<String>>,
        pendingIds: Set<String>,
    ): Map<String, Set<String>> {
        val out = HashMap<String, MutableSet<String>>()
        for ((merchant, ids) in held) {
            val still = ids.intersect(pendingIds) // rows sent since then need no hold
            if (still.isNotEmpty()) out[merchant] = still.toMutableSet()
        }
        if (owner != null && owner != newMerchant) {
            val alreadyHeld = out.values.flatten().toSet()
            val owners = pendingIds - alreadyHeld
            if (owners.isNotEmpty()) out.getOrPut(owner) { HashSet() } += owners
        }
        out.remove(newMerchant)
        return out
    }

    /** Rows the [current] merchant must not upload, list or count. */
    fun blocked(current: String?, held: Map<String, Set<String>>): Set<String> =
        held.filterKeys { it != current }.values.flatten().toSet()

    fun encode(held: Map<String, Set<String>>): String = JsonWriter.write(held.mapValues { it.value.sorted() })

    fun decode(text: String?): Map<String, Set<String>> = try {
        (text?.let { MiniJson.parse(it) } as? Map<*, *>)
            ?.mapNotNull { (k, v) ->
                val ids = (v as? List<*>)?.filterIsInstance<String>()?.toSet()
                if (k is String && ids != null) k to ids else null
            }
            ?.toMap() ?: emptyMap()
    } catch (_: Exception) {
        emptyMap()
    }
}
