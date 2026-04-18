#include <stdio.h>
#include <string.h>
#include <openssl/evp.h>

int test_inplace(int ptlen) {
    unsigned char key[16] = {0};
    unsigned char iv[12] = {0};
    unsigned char *ct_std = calloc(ptlen + 16, 1);
    unsigned char *buf = calloc(ptlen + 16, 1);  /* in-place */
    unsigned char tag_std[16], tag_ip[16];
    int outl;

    /* Standard */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        for (int off = 0; off < ptlen; off += 16)
            EVP_EncryptUpdate(ctx, ct_std + off, &outl,
                              ct_std + off, /* use ct_std as src since it's zero */
                              ptlen - off < 16 ? ptlen - off : 16);
        EVP_EncryptFinal_ex(ctx, ct_std + ptlen, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_std);
        EVP_CIPHER_CTX_free(ctx);
    }

    /* Fused in-place */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, buf, &outl, buf, ptlen);  /* in-place */
        EVP_EncryptFinal_ex(ctx, buf + ptlen, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_ip);
        EVP_CIPHER_CTX_free(ctx);
    }

    int ok = 1;
    if (memcmp(ct_std, buf, ptlen) != 0) { printf("CT FAIL "); ok = 0; }
    if (memcmp(tag_std, tag_ip, 16) != 0) { printf("TAG FAIL "); ok = 0; }
    free(ct_std); free(buf);
    return ok;
}

int main(void) {
    int sizes[] = {64, 80, 96, 128, 256, 512, 1024};
    for (int i = 0; i < 7; i++) {
        printf("In-place len=%d: ", sizes[i]);
        fflush(stdout);
        printf("%s\n", test_inplace(sizes[i]) ? "PASS" : "FAIL");
    }
    return 0;
}
