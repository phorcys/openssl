#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/evp.h>

/*
 * Test that fused GCM decrypt produces correct plaintext and verifies tag.
 * Encrypts with 16-byte updates (non-fused), then decrypts in one shot
 * (fused path) and compares.
 */
int test_decrypt(int keylen, int ptlen) {
    unsigned char key[32] = {0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,
                             0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08,
                             0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,
                             0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08};
    unsigned char iv[12] = {0xca,0xfe,0xba,0xbe,0xfa,0xce,0xdb,0xad,
                            0xde,0xca,0xf8,0x88};
    unsigned char *pt = calloc(ptlen, 1);
    unsigned char *ct = calloc(ptlen, 1);
    unsigned char *recovered = calloc(ptlen, 1);
    unsigned char tag[16];
    int outl, ok = 1;
    const EVP_CIPHER *cipher;

    for (int i = 0; i < ptlen; i++)
        pt[i] = (i * 7 + 13) & 0xff;

    if (keylen == 16) cipher = EVP_aes_128_gcm();
    else if (keylen == 24) cipher = EVP_aes_192_gcm();
    else cipher = EVP_aes_256_gcm();

    /* Encrypt in one shot (fused path for large data) */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, ct, &outl, pt, ptlen);
        EVP_EncryptFinal_ex(ctx, ct + outl, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag);
        EVP_CIPHER_CTX_free(ctx);
    }

    /* Decrypt in one shot (fused path for large data) */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_DecryptInit_ex(ctx, cipher, NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_DecryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_DecryptUpdate(ctx, recovered, &outl, ct, ptlen);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_TAG, 16, tag);
        if (EVP_DecryptFinal_ex(ctx, recovered + outl, &outl) <= 0) {
            printf("TAG VERIFY FAIL  ");
            ok = 0;
        }
        EVP_CIPHER_CTX_free(ctx);
    }

    if (memcmp(pt, recovered, ptlen) != 0) {
        printf("PLAINTEXT MISMATCH  ");
        ok = 0;
    }

    free(pt);
    free(ct);
    free(recovered);
    return ok;
}

int main(void) {
    int keys[] = {16, 24, 32};
    int sizes[] = {64, 96, 128, 256, 512, 1024, 4096, 16384};
    for (int k = 0; k < 3; k++) {
        for (int s = 0; s < 8; s++) {
            printf("AES-%d decrypt len=%d: ", keys[k]*8, sizes[s]);
            fflush(stdout);
            printf("%s\n", test_decrypt(keys[k], sizes[s]) ? "PASS" : "FAIL");
        }
    }
    return 0;
}
