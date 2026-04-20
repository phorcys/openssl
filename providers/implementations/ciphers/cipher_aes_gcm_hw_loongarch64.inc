/*
 * Copyright 2025 The OpenSSL Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").  You may not
 * use this file except in compliance with the License.  You can obtain a copy
 * in the file LICENSE in the source distribution or at
 * https://www.openssl.org/source/license.html
 */

/*
 * LoongArch64 AES GCM provider hook.
 * This file is included by cipher_aes_gcm_hw.c
 *
 * Route AES operations through the VPAES CTR path when LSX is available,
 * and precompute the fused-path 8-bit GHASH tables once per key setup.
 * Fused AES-GCM encrypt/decrypt is handled by generic_aes_gcm_cipher_update
 * via the AES_GCM_ASM macros defined in aes_platform.h.
 */

static const u64 loongarch64_rem_4bit[16] = {
    0x0000000000000000ULL, 0x1C20000000000000ULL,
    0x3840000000000000ULL, 0x2460000000000000ULL,
    0x7080000000000000ULL, 0x6CA0000000000000ULL,
    0x48C0000000000000ULL, 0x54E0000000000000ULL,
    0xE100000000000000ULL, 0xFD20000000000000ULL,
    0xD940000000000000ULL, 0xC560000000000000ULL,
    0x9180000000000000ULL, 0x8DA0000000000000ULL,
    0xA9C0000000000000ULL, 0xB5E0000000000000ULL
};

static ossl_inline u128 loongarch64_gcm_shift4(u128 v)
{
    u128 out;
    u64 rem = v.lo & 0xf;

    out.lo = (v.hi << 60) | (v.lo >> 4);
    out.hi = (v.hi >> 4) ^ loongarch64_rem_4bit[rem];
    return out;
}

static void loongarch64_gcm_init_8bit(u128 T8[256], const u128 T4[16])
{
    int i;

    for (i = 0; i < 256; ++i) {
        u128 z = loongarch64_gcm_shift4(T4[i & 0xf]);

        z.hi ^= T4[i >> 4].hi;
        z.lo ^= T4[i >> 4].lo;
        T8[i] = z;
    }
}

void loongarch64_gcm_prepare_tables(GCM128_CONTEXT *gcm)
{
    if (gcm->Htable8_ready)
        return;

    u64 H2[2] = { gcm->H.u[0], gcm->H.u[1] };
    u128 H2_4bit[16];

    ossl_gcm_gmult_4bit(H2, gcm->Htable);
    ossl_gcm_init_4bit(H2_4bit, H2);
    loongarch64_gcm_init_8bit(gcm->Htable8, gcm->Htable);
    loongarch64_gcm_init_8bit(gcm->Htable8_2, H2_4bit);
    gcm->Htable8_ready = 1;
}

static int loongarch64_aes_gcm_initkey(PROV_GCM_CTX *ctx, const unsigned char *key,
                                       size_t keylen)
{
    PROV_AES_GCM_CTX *actx = (PROV_AES_GCM_CTX *)ctx;
    AES_KEY *ks = &actx->ks.ks;

    if (VPAES_CAPABLE) {
        GCM_HW_SET_KEY_CTR_FN(ks, vpaes_set_encrypt_key, vpaes_encrypt,
                              vpaes_ctr32_encrypt_blocks);
        return 1;
    }

    return aes_gcm_initkey(ctx, key, keylen);
}

static const PROV_GCM_HW loongarch64_aes_gcm = {
    loongarch64_aes_gcm_initkey,
    ossl_gcm_setiv,
    ossl_gcm_aad_update,
    generic_aes_gcm_cipher_update,
    ossl_gcm_cipher_final,
    ossl_gcm_one_shot
};

const PROV_GCM_HW *ossl_prov_aes_hw_gcm(size_t keybits)
{
    (void)keybits;
    return &loongarch64_aes_gcm;
}
