#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <openssl/evp.h>

int test_keysize(int keylen, int ptlen) {
    unsigned char key[32] = {0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,
                             0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08,
                             0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,
                             0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08};
    unsigned char iv[12] = {0xca,0xfe,0xba,0xbe,0xfa,0xce,0xdb,0xad,0xde,0xca,0xf8,0x88};
    unsigned char *pt = calloc(ptlen, 1);
    unsigned char *ct_std = calloc(ptlen + 16, 1);
    unsigned char *ct_fused = calloc(ptlen + 16, 1);
    unsigned char tag_std[16], tag_fused[16];
    int outl, ok = 1;
    const EVP_CIPHER *cipher;
    for (int i = 0; i < ptlen; i++) pt[i] = i & 0xff;

    if (keylen == 16) cipher = EVP_aes_128_gcm();
    else if (keylen == 24) cipher = EVP_aes_192_gcm();
    else cipher = EVP_aes_256_gcm();

    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        for (int off = 0; off < ptlen; off += 16)
            EVP_EncryptUpdate(ctx, ct_std + off, &outl, pt + off,
                              ptlen - off < 16 ? ptlen - off : 16);
        EVP_EncryptFinal_ex(ctx, ct_std + ptlen, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_std);
        EVP_CIPHER_CTX_free(ctx);
    }
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, cipher, NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, ct_fused, &outl, pt, ptlen);
        EVP_EncryptFinal_ex(ctx, ct_fused + ptlen, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_fused);
        EVP_CIPHER_CTX_free(ctx);
    }
    if (memcmp(ct_std, ct_fused, ptlen) != 0) { printf("CT FAIL"); ok = 0; }
    if (memcmp(tag_std, tag_fused, 16) != 0) { printf("TAG FAIL"); ok = 0; }
    free(pt); free(ct_std); free(ct_fused);
    return ok;
}

int main(void) {
    int keys[] = {16, 24, 32};
    int sizes[] = {64, 96, 128, 256, 512, 1024, 4096};
    for (int k = 0; k < 3; k++) {
        for (int s = 0; s < 7; s++) {
            printf("AES-%d len=%d: ", keys[k]*8, sizes[s]);
            fflush(stdout);
            printf("%s\n", test_keysize(keys[k], sizes[s]) ? "PASS" : "FAIL");
        }
    }
    return 0;
}
