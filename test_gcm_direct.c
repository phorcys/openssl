/*
 * Direct test for loongarch64_vpaes_gcm_encrypt assembly function.
 * Bypasses EVP to isolate assembly-level issues.
 */
#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>

/* Replicate the key parts of the GCM128_CONTEXT structure */
typedef unsigned long long u64;
typedef struct {
    union { u64 u[2]; unsigned char c[16]; } Yi, EKi, EK0, len, Xi, H;
    unsigned char Htable[256]; /* u128 Htable[16] */
} fake_gcm_ctx;

/* External functions from libcrypto */
extern int vpaes_set_encrypt_key(const unsigned char *userKey, int bits, void *key);
extern void vpaes_encrypt(const unsigned char *in, unsigned char *out, const void *key);

/* Our fused function (local symbol, need to find it) */
extern size_t loongarch64_vpaes_gcm_encrypt(const unsigned char *in, unsigned char *out,
    size_t len, const void *key, unsigned char ivec[16], u64 *Xi);

/* GCM init functions */
extern void ossl_gcm_init_4bit(unsigned char Htable[256], const u64 H[2]);

int main(void)
{
    /* AES-128 key */
    const unsigned char key_bytes[16] = {
        0xfe, 0xff, 0xe9, 0x92, 0x86, 0x65, 0x73, 0x1c,
        0x6d, 0x6a, 0x8f, 0x94, 0x67, 0x30, 0x83, 0x08
    };

    /* 64 bytes of plaintext */
    const unsigned char pt[64] = {
        0xd9, 0x31, 0x32, 0x25, 0xf8, 0x84, 0x06, 0xe5,
        0xa5, 0x59, 0x09, 0xc5, 0xaf, 0xf5, 0x26, 0x9a,
        0x86, 0xa7, 0xa9, 0x53, 0x15, 0x34, 0xf7, 0xda,
        0x2e, 0x4c, 0x30, 0x3d, 0x8a, 0x31, 0x8a, 0x72,
        0x1c, 0x3c, 0x0c, 0x95, 0x95, 0x68, 0x09, 0x53,
        0x2f, 0xcf, 0x0e, 0x24, 0x49, 0xa6, 0xb5, 0x25,
        0xb1, 0x6a, 0xed, 0xf5, 0xaa, 0x0d, 0xe6, 0x57,
        0xba, 0x63, 0x7b, 0x39, 0x1a, 0xaf, 0xd2, 0x55
    };

    /* Allocate AES key schedule (needs alignment) */
    unsigned char ks[256] __attribute__((aligned(16)));
    memset(ks, 0, sizeof(ks));

    printf("Setting up AES-128 key...\n");
    vpaes_set_encrypt_key(key_bytes, 128, ks);

    /* Check round count at ks+240 */
    int rounds = *(int *)(ks + 240);
    printf("Rounds at key+240 = %d (expected 9)\n", rounds);

    /* Set up GCM context-like structure */
    fake_gcm_ctx ctx;
    memset(&ctx, 0, sizeof(ctx));

    /* Compute H = AES_K(0) */
    unsigned char zero16[16] = {0};
    unsigned char H_bytes[16];
    vpaes_encrypt(zero16, H_bytes, ks);
    printf("H = ");
    for (int i = 0; i < 16; i++) printf("%02x", H_bytes[i]);
    printf("\n");

    /* Store H in context (as-is, big-endian) */
    memcpy(ctx.H.c, H_bytes, 16);

    /* Initialize 4-bit GHASH table */
    ossl_gcm_init_4bit(ctx.Htable, ctx.H.u);

    /* Set up Yi (IV + counter = 1 in BE) */
    unsigned char ivec[16] = {
        0xca, 0xfe, 0xba, 0xbe, 0xfa, 0xce, 0xdb, 0xad,
        0xde, 0xca, 0xf8, 0x88, 0x00, 0x00, 0x00, 0x02  /* counter=2 for data */
    };

    /* Xi starts at zero (no AAD) */
    memset(&ctx.Xi, 0, 16);

    /* Output buffer */
    unsigned char ct[64];
    memset(ct, 0xAA, sizeof(ct));

    printf("Calling loongarch64_vpaes_gcm_encrypt...\n");
    printf("  in=%p out=%p len=64 key=%p ivec=%p Xi=%p\n",
           pt, ct, ks, ivec, &ctx.Xi.u[0]);
    printf("  Htable at Xi+32: %p\n", (void*)((char*)&ctx.Xi.u[0] + 32));
    printf("  Actual Htable:   %p\n", ctx.Htable);
    printf("  Offset from Xi:  %ld\n", (long)((char*)ctx.Htable - (char*)&ctx.Xi.u[0]));

    size_t processed = loongarch64_vpaes_gcm_encrypt(pt, ct, 64, ks, ivec, ctx.Xi.u);

    printf("Processed: %zu bytes\n", processed);
    printf("CT: ");
    for (int i = 0; i < 64; i++) printf("%02x", ct[i]);
    printf("\n");

    return 0;
}
