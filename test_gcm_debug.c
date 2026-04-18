/* Debug test: compare fused GHASH with reference */
#include <stdio.h>
#include <string.h>
#include <openssl/evp.h>
#include <openssl/err.h>

/* From modes.h internal header */
typedef struct { uint64_t hi, lo; } my_u128;

/* Minimal reference GHASH implementation */
static const uint64_t rem_4bit_tab[16] = {
    0x0000000000000000ULL, 0x1C20000000000000ULL,
    0x3840000000000000ULL, 0x2460000000000000ULL,
    0x7080000000000000ULL, 0x6CA0000000000000ULL,
    0x48C0000000000000ULL, 0x54E0000000000000ULL,
    0xE100000000000000ULL, 0xFD20000000000000ULL,
    0xD940000000000000ULL, 0xC560000000000000ULL,
    0x9180000000000000ULL, 0x8DA0000000000000ULL,
    0xA9C0000000000000ULL, 0xB5E0000000000000ULL,
};

static uint64_t bswap64(uint64_t x) {
    return __builtin_bswap64(x);
}

static void my_gcm_init_4bit(my_u128 Htable[16], const uint64_t H[2]) {
    my_u128 V;
    Htable[0].hi = 0; Htable[0].lo = 0;
    V.hi = H[0]; V.lo = H[1];
    Htable[8] = V;
    /* REDUCE1BIT */
#define MY_REDUCE1BIT(V) do { \
    uint64_t T = 0xe100000000000000ULL & (0 - (V.lo & 1)); \
    V.lo = (V.hi << 63) | (V.lo >> 1); \
    V.hi = (V.hi >> 1) ^ T; \
} while(0)
    MY_REDUCE1BIT(V); Htable[4] = V;
    MY_REDUCE1BIT(V); Htable[2] = V;
    MY_REDUCE1BIT(V); Htable[1] = V;
    Htable[3].hi = V.hi ^ Htable[2].hi; Htable[3].lo = V.lo ^ Htable[2].lo;
    V = Htable[4];
    Htable[5].hi = V.hi ^ Htable[1].hi; Htable[5].lo = V.lo ^ Htable[1].lo;
    Htable[6].hi = V.hi ^ Htable[2].hi; Htable[6].lo = V.lo ^ Htable[2].lo;
    Htable[7].hi = V.hi ^ Htable[3].hi; Htable[7].lo = V.lo ^ Htable[3].lo;
    V = Htable[8];
    Htable[9].hi  = V.hi ^ Htable[1].hi; Htable[9].lo  = V.lo ^ Htable[1].lo;
    Htable[10].hi = V.hi ^ Htable[2].hi; Htable[10].lo = V.lo ^ Htable[2].lo;
    Htable[11].hi = V.hi ^ Htable[3].hi; Htable[11].lo = V.lo ^ Htable[3].lo;
    Htable[12].hi = V.hi ^ Htable[4].hi; Htable[12].lo = V.lo ^ Htable[4].lo;
    Htable[13].hi = V.hi ^ Htable[5].hi; Htable[13].lo = V.lo ^ Htable[5].lo;
    Htable[14].hi = V.hi ^ Htable[6].hi; Htable[14].lo = V.lo ^ Htable[6].lo;
    Htable[15].hi = V.hi ^ Htable[7].hi; Htable[15].lo = V.lo ^ Htable[7].lo;
}

static void my_gcm_ghash_4bit(uint64_t Xi[2], const my_u128 Htable[16],
                               const uint8_t *inp, size_t len) {
    while (len >= 16) {
        /* XOR input block with Xi */
        uint64_t inp0, inp1;
        memcpy(&inp0, inp, 8); memcpy(&inp1, inp+8, 8);
        Xi[0] ^= inp0; Xi[1] ^= inp1;

        /* 4-bit GHASH multiply */
        my_u128 Z;
        size_t rem, nlo, nhi;
        nlo = ((const uint8_t *)Xi)[15];
        nhi = nlo >> 4; nlo &= 0xf;
        Z.hi = Htable[nlo].hi; Z.lo = Htable[nlo].lo;
        for (int cnt = 15; cnt > 0; cnt--) {
            rem = (size_t)Z.lo & 0xf;
            Z.lo = (Z.hi << 60) | (Z.lo >> 4);
            Z.hi = (Z.hi >> 4) ^ rem_4bit_tab[rem] ^ Htable[nhi].hi;
            Z.lo ^= Htable[nhi].lo;
            nlo = ((const uint8_t *)Xi)[cnt - 1];
            nhi = nlo >> 4; nlo &= 0xf;
            rem = (size_t)Z.lo & 0xf;
            Z.lo = (Z.hi << 60) | (Z.lo >> 4);
            Z.hi = (Z.hi >> 4) ^ rem_4bit_tab[rem] ^ Htable[nlo].hi;
            Z.lo ^= Htable[nlo].lo;
        }
        rem = (size_t)Z.lo & 0xf;
        Z.lo = (Z.hi << 60) | (Z.lo >> 4);
        Z.hi = (Z.hi >> 4) ^ rem_4bit_tab[rem] ^ Htable[nhi].hi;
        Z.lo ^= Htable[nhi].lo;

        Xi[0] = bswap64(Z.hi); Xi[1] = bswap64(Z.lo);
        inp += 16; len -= 16;
    }
}

int main(void) {
    uint8_t key[] = {0xfe,0xff,0xe9,0x92,0x86,0x65,0x73,0x1c,
                     0x6d,0x6a,0x8f,0x94,0x67,0x30,0x83,0x08};
    uint8_t iv[] = {0xca,0xfe,0xba,0xbe,0xfa,0xce,0xdb,0xad,
                    0xde,0xca,0xf8,0x88};
    uint8_t pt[64] = {
        0xd9,0x31,0x32,0x25,0xf8,0x84,0x06,0xe5,0x55,0x90,0x9c,0x5a,0xff,0x52,0x69,0xaa,
        0x6a,0x7a,0x95,0x38,0x53,0x4f,0x7d,0xa1,0xe4,0xc3,0x03,0xd2,0xa3,0x18,0xa7,0x28,
        0xc3,0xc0,0xc9,0x51,0x56,0x80,0x95,0x39,0xfc,0xf0,0xe2,0x42,0x9a,0x6b,0x52,0x54,
        0x16,0xae,0xdb,0xf5,0xa0,0xde,0x6a,0x57,0xa6,0x37,0xb3,0x9b,0x00,0x00,0x00,0x00};
    uint8_t ct_std[80], ct_fused[80];
    uint8_t tag_std[16], tag_fused[16];
    int outl;

    /* Standard path (small updates) */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, ct_std, &outl, pt, 16);
        EVP_EncryptUpdate(ctx, ct_std+16, &outl, pt+16, 16);
        EVP_EncryptUpdate(ctx, ct_std+32, &outl, pt+32, 16);
        EVP_EncryptUpdate(ctx, ct_std+48, &outl, pt+48, 16);
        EVP_EncryptFinal_ex(ctx, ct_std+64, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_std);
        EVP_CIPHER_CTX_free(ctx);
    }

    /* Fused path */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        EVP_EncryptUpdate(ctx, ct_fused, &outl, pt, 64);
        EVP_EncryptFinal_ex(ctx, ct_fused+64, &outl);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_GET_TAG, 16, tag_fused);
        EVP_CIPHER_CTX_free(ctx);
    }

    printf("CT match: %s\n", memcmp(ct_std, ct_fused, 64) == 0 ? "YES" : "NO");
    printf("Tag std:   "); for (int i=0;i<16;i++) printf("%02x",tag_std[i]); printf("\n");
    printf("Tag fused: "); for (int i=0;i<16;i++) printf("%02x",tag_fused[i]); printf("\n");
    printf("Tag match: %s\n", memcmp(tag_std, tag_fused, 16) == 0 ? "YES" : "NO");

    /* Now compute reference GHASH manually using H^2 table */
    /* First get H from a context */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_gcm(), NULL, NULL, NULL);
        EVP_CIPHER_CTX_ctrl(ctx, EVP_CTRL_GCM_SET_IVLEN, 12, NULL);
        EVP_EncryptInit_ex(ctx, NULL, NULL, key, iv);
        /* Encrypt to get ciphertext */
        uint8_t ct2[80];
        EVP_EncryptUpdate(ctx, ct2, &outl, pt, 16);

        /* We can't easily extract H from EVP, so let's compute H = AES(K, 0) */
        EVP_CIPHER_CTX_free(ctx);
    }

    /* Compute H = AES(K, 0) using raw AES */
    {
        EVP_CIPHER_CTX *ctx = EVP_CIPHER_CTX_new();
        EVP_EncryptInit_ex(ctx, EVP_aes_128_ecb(), NULL, key, NULL);
        uint8_t zero16[16] = {0}, H_bytes[16];
        int olen = 0;
        EVP_CIPHER_CTX_set_padding(ctx, 0);
        EVP_EncryptUpdate(ctx, H_bytes, &olen, zero16, 16);
        EVP_CIPHER_CTX_free(ctx);

        printf("\nH = AES(K,0): ");
        for (int i=0;i<16;i++) printf("%02x", H_bytes[i]);
        printf("\n");

        /* H in u64 format (native endian) */
        uint64_t H_u64[2];
        memcpy(H_u64, H_bytes, 16);
        printf("H.u[0] = %016lx  H.u[1] = %016lx\n", H_u64[0], H_u64[1]);

        /* Build Htable from H */
        my_u128 Htable[16];
        ossl_gcm_init_4bit(Htable, H_u64);
        printf("Htable[8].hi=%016lx .lo=%016lx\n", Htable[8].hi, Htable[8].lo);

        /* Compute GHASH(H, H_bytes) = H * H = H^2 */
        /* In GHASH: Xi = Xi ^ inp, then multiply by H */
        /* If Xi starts as 0, ghash(0, inp) = H * inp */
        uint64_t h2_xi[2] = {0, 0};
        my_gcm_ghash_4bit(h2_xi, Htable, H_bytes, 16);
        printf("\nH^2 = GHASH(H, H_bytes):\n");
        printf("  H2.u[0] = %016lx  H2.u[1] = %016lx\n", h2_xi[0], h2_xi[1]);

        /* Build H^2 table first */
        my_u128 H2table[16];
        my_gcm_init_4bit(H2table, h2_xi);
        printf("H2table[8].hi=%016lx .lo=%016lx\n", H2table[8].hi, H2table[8].lo);

        /* Verify H^2: C0*H^2 should equal ghash(C0*H, zeros) */
        printf("=== VERIFY START ===\n"); fflush(stdout);
        uint64_t c0_times_h[2] = {0, 0};
        my_gcm_ghash_4bit(c0_times_h, Htable, ct_std, 16);
        printf("\nC0*H:\n  %016lx %016lx\n", c0_times_h[0], c0_times_h[1]);

        uint64_t c0_times_h2[2] = {0, 0};
        my_gcm_ghash_4bit(c0_times_h2, H2table, ct_std, 16);
        printf("C0*H^2 (via H^2 table):\n  %016lx %016lx\n", c0_times_h2[0], c0_times_h2[1]);

        uint8_t zero16v[16] = {0};
        uint64_t verify_h2[2] = {c0_times_h[0], c0_times_h[1]};
        my_gcm_ghash_4bit(verify_h2, Htable, zero16v, 16);
        printf("C0*H^2 (via double ghash):\n  %016lx %016lx\n", verify_h2[0], verify_h2[1]);
        printf("H^2 verify: %s\n",
            memcmp(c0_times_h2, verify_h2, 16) == 0 ? "YES" : "NO");

        /* Now compute the GHASH of the ciphertext manually using 2-block-at-a-time */
        /* Xi_2 = H^2*(Xi_0 ^ C0) + H*C1 */
        /* Xi_4 = H^2*(Xi_2 ^ C2) + H*C3 */
        uint64_t xi_a[2] = {0, 0};  /* Xi_0 ^ C0 */
        uint64_t xi_b[2] = {0, 0};  /* C1 */
        
        /* GHASH of first pair: */
        /* A-stream: H^2 * (Xi ^ C0) */
        ossl_gcm_ghash_4bit(xi_a, H2table, ct_std, 16);  /* ghash(0, C0) = H^2 * C0 */
        /* B-stream: H * C1 */
        ossl_gcm_ghash_4bit(xi_b, Htable, ct_std+16, 16); /* ghash(0, C1) = H * C1 */
        uint64_t xi_2[2] = { xi_a[0] ^ xi_b[0], xi_a[1] ^ xi_b[1] };
        printf("\nXi after pair 0 (manual 2-at-a-time):\n");
        printf("  Xi2.u[0] = %016lx  Xi2.u[1] = %016lx\n", xi_2[0], xi_2[1]);

        /* Verify against standard sequential GHASH */
        uint64_t xi_seq[2] = {0, 0};
        ossl_gcm_ghash_4bit(xi_seq, Htable, ct_std, 32);
        printf("Xi after pair 0 (sequential):\n");
        printf("  Xi.u[0] = %016lx  Xi.u[1] = %016lx\n", xi_seq[0], xi_seq[1]);
        printf("  Match: %s\n", memcmp(xi_2, xi_seq, 16) == 0 ? "YES" : "NO");

        /* Second pair */
        xi_a[0] = xi_2[0]; xi_a[1] = xi_2[1];
        ossl_gcm_ghash_4bit(xi_a, H2table, ct_std+32, 16);
        xi_b[0] = 0; xi_b[1] = 0;
        ossl_gcm_ghash_4bit(xi_b, Htable, ct_std+48, 16);
        uint64_t xi_4[2] = { xi_a[0] ^ xi_b[0], xi_a[1] ^ xi_b[1] };
        printf("\nXi after pair 1 (manual 2-at-a-time):\n");
        printf("  Xi4.u[0] = %016lx  Xi4.u[1] = %016lx\n", xi_4[0], xi_4[1]);

        ossl_gcm_ghash_4bit(xi_seq, Htable, ct_std+32, 32);
        printf("Xi after pair 1 (sequential):\n");
        printf("  Xi.u[0] = %016lx  Xi.u[1] = %016lx\n", xi_seq[0], xi_seq[1]);
        printf("  Match: %s\n", memcmp(xi_4, xi_seq, 16) == 0 ? "YES" : "NO");
    }

    return (memcmp(tag_std, tag_fused, 16) != 0) ? 1 : 0;
}
