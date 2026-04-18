#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/evp.h>

int main(void) {
    unsigned char key[16] = {0};
    unsigned char iv[12] = {0};
    unsigned char pt[80] = {0};
    unsigned char ct_std[96], ct_fused[96];
    unsigned char tag_std[16], tag_fused[16];
    int outl;

    /* Standard path: 16-byte updates */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        for (int off = 0; off < 80; off += 16)
            EVP_EncryptUpdate(ctx, ct_std + off, &outl, pt + off, 16);
        EVP_EncryptFinal_ex(ctx, ct_std + 80, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_std);
        EVP_CIPHER_CTX_free(ctx);
    }

    /* Fused path: single update */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, ct_fused, &outl, pt, 80);
        EVP_EncryptFinal_ex(ctx, ct_fused + 80, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_fused);
        EVP_CIPHER_CTX_free(ctx);
    }

    printf("CT match: %s\n", memcmp(ct_std, ct_fused, 80) == 0 ? "YES" : "NO");
    printf("Tag match: %s\n", memcmp(tag_std, tag_fused, 16) == 0 ? "YES" : "NO");
    return 0;
}
