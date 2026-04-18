/*
 * Copyright 2025 The OpenSSL Project Authors. All Rights Reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License").  You may not
 * use this file except in compliance with the License.  You can obtain a copy
 * in the file LICENSE in the source distribution or at
 * https://www.openssl.org/source/license.html
 */

/*
 * LoongArch64 VPAES support for AES GCM.
 * This file is included by cipher_aes_gcm_hw.c
 *
 * Uses VPAES (vector permutation AES) for AES operations and the
 * LoongArch64 optimized GHASH for authentication.
 */

static int loongarch64_aes_gcm_initkey(PROV_GCM_CTX *ctx, const unsigned char *key,
                                       size_t keylen)
{
    PROV_AES_GCM_CTX *actx = (PROV_AES_GCM_CTX *)ctx;
    AES_KEY *ks = &actx->ks.ks;

    GCM_HW_SET_KEY_CTR_FN(ks, vpaes_set_encrypt_key, vpaes_encrypt,
                          vpaes_ctr32_encrypt_blocks);
    return 1;
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
    return &loongarch64_aes_gcm;
}
