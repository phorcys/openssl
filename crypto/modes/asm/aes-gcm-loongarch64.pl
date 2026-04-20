#! /usr/bin/env perl
# Copyright 2026 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the Apache License 2.0 (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

# LoongArch64 fused AES-GCM (LSX + LASX)
#
# Two implementation paths:
#
#   LSX path (128-bit):
#     - encrypt & decrypt
#     - two separate vr0/vr19 states processed in parallel
#     - GHASH x2 interleaved between AES half-rounds
#     - process aligned 32-byte chunks
#
#   LASX path (256-bit):
#     - encrypt & decrypt
#     - two blocks packed into one xvr0 register
#     - all AES constants duplicated to 256-bit via xvreplve0.q
#     - MC tables + ShiftRows + final RK permanently resident in xvr16-25,31
#     - GHASH x2 interleaved between AES half-rounds (same as LSX)
#     - process aligned 32-byte chunks
#
# Both leave tail handling to generic CRYPTO_gcm128_encrypt_ctr32().
#
# This file is intentionally independent from vpaes-loongarch64.pl.
# The fused AES/GHASH schedule has different register ownership and
# different optimization goals from generic VPAES CTR code.
#
# Interface:
#   size_t loongarch64_vpaes_gcm_encrypt(...)       // LSX path
#   size_t loongarch64_vpaes_gcm_decrypt(...)       // LSX path
#   size_t loongarch64_vpaes_lasx_gcm_encrypt(...)  // LASX path
#   size_t loongarch64_vpaes_lasx_gcm_decrypt(...)  // LASX path
#
#   All four share the same signature:
#     (const unsigned char *in, unsigned char *out, size_t len,
#      const void *key, unsigned char ivec[16], u64 *Xi)
#
# Notes on context recovery:
#   - Xi points to GCM128_CONTEXT::Xi.u
#   - Htable is reachable as Xi + 32 bytes
#   - the relative layout is fixed by include/crypto/modes.h
#
# Register ownership
# ------------------
# GPR (shared by both paths)
#   a0  inp
#   a1  out
#   a2  len
#   a3  key
#   a4  ivec
#   a5  Xi
#
#   s0  aligned_len
#   s1  round-key base
#   s2  rem_8bit table
#   s3  H 4-bit table
#   s3  H 8-bit table (256 entries x 16 bytes = 4096 bytes on stack)
#   s6  H^2 8-bit table (4096 bytes on stack, at s3 + 4096)
#
#   t0-t9  AES/GHASH temporaries and loop control
#
# GHASH x2 fixed GPR layout (shared by both paths)
#   stream A: r6/r7 src, r8/r9 z, r10 cur
#   stream B: r11/r12 src, r13/r14 z, r15 cur
#   temps:    r16-r18 (A), r19-r21 (B)
#   common:   r4/r5
#
# VPR – LSX path (128-bit, vr0..vr30)
#   vr9..vr15, vr18    VPAES preheat constants
#   vr27/vr28           Lk_ipt[0]/Lk_ipt[16] (preloaded)
#   vr29/vr30           Lk_sbo[0]/Lk_sbo[16] (preloaded)
#   vr0 / vr19          AES states for block pair
#   vr1-5 / vr20-24     AES x2 round temporaries
#   vr6/vr7/vr8         plaintext/ciphertext staging / counter template
#
# VPR – LASX path (256-bit, xvr0..xvr31)
#   xvr9..xvr15, xvr18  VPAES constants (duplicated to 256-bit)
#   xvr27/xvr28          Lk_ipt[0]/Lk_ipt[16] (duplicated)
#   xvr29/xvr30          Lk_sbo[0]/Lk_sbo[16] (duplicated)
#   xvr0                 AES state (2 blocks packed: [block0 | block1])
#   xvr1..xvr5           AES round temporaries
#   vr6/vr7/vr8          plaintext/ciphertext staging / counter template
#   xvr16,17,19,20       MC_forward[0..3] (preloaded, permanent)
#   xvr21,22,23,24       MC_backward[0..3] (preloaded, permanent)
#   xvr25                ShiftRows table (preloaded per key-size)
#   xvr26                round-key staging temporary
#   xvr31                final round key (preloaded per key-size)
#
# Steady-state schedule
# ---------------------
# Both paths use fully-unrolled AES rounds with GHASH x2 interleaved:
#
#   AES building blocks (per path):
#     init       – IPT + round key 0
#     half_front – top_abc + SubBytes + round-key XOR
#     half_back  – MixColumns (4 shuffles + XORs)
#     final      – last-round sbo + ShiftRows
#
#   GHASH x2 building blocks (shared):
#     INIT2 / PRE2 / POST2_LO / POST2_HI / FINAL2
#
# 15 GHASH byte-steps are evenly distributed across 2*(Nr-1) half-round
# slots between half_front and half_back of each middle AES round.

my $output;
$output = $#ARGV >= 0 && $ARGV[$#ARGV] =~ m|\.\w+$| ? pop : undef;
open STDOUT, ">$output";

my ($zero,$ra,$tp,$sp)=map("\$r$_",(0..3));
my ($a0,$a1,$a2,$a3,$a4,$a5,$a6,$a7)=map("\$r$_",(4..11));
my ($t0,$t1,$t2,$t3,$t4,$t5,$t6,$t7,$t8,$t9)=map("\$r$_",(12..21));
my ($s0,$s1,$s2,$s3,$s4,$s5,$s6,$s7,$s8)=("\$r23","\$r24","\$r25","\$r26","\$r27","\$r28","\$r29","\$r30","\$r31");
my ($fp)=("\$r22");
my ($vr0,$vr1,$vr2,$vr3,$vr4,$vr5,$vr6,$vr7,$vr8,$vr9,$vr10,$vr11,$vr12,$vr13,$vr14,$vr15,
    $vr16,$vr17,$vr18,$vr19,$vr20,$vr21,$vr22,$vr23,$vr24,$vr25,$vr26,$vr27,$vr28,$vr29,$vr30,$vr31)
    = map("\$vr$_",(0..31));

sub emit_rept {
    my ($body, $count, $comment) = @_;
    my $out = "";
    $out .= "    # $comment\n" if $comment;
    $out .= "    .rept $count\n";
    $out .= "    $body\n";
    $out .= "    .endr\n";
    return $out;
}

sub emit_build_8bit_table {
    my ($tab_reg, $label_prefix) = @_;
    # Build 256-entry 8-bit GHASH table from raw H value.
    # Input:  r12 (hi), r13 (lo) = H value in native byte order.
    #         $tab_reg = register pointing to 4096-byte destination area.
    # Output: T8[byte] = shift4(T4[byte & 0xf]) ^ T4[byte >> 4]
    #         where T4 is the standard 4-bit GHASH table.
    # Clobbers: r12-r21, t7 ($r19 is t7 alias on some, using r19 explicitly)
    #
    # Strategy:
    #   Phase 1: Build T4[0..15] at tab_reg+0..255 (standard 4-bit table).
    #   Phase 2: For byte=255..16, compute T8[byte] and store at byte*16.
    #            (reads T4[0..15] which are untouched at this point)
    #   Phase 3: In-place convert T4[0..15] to T8[0..15] = shift4(T4[i]).
    #            (T4[i>>4]=T4[0]={0,0} for i<16, so T8[i] = shift4(T4[i]) ^ 0)

    my $out = "";
    $out .= "    # ── Phase 1: Build 4-bit table T4[0..15] at $tab_reg ──\n";
    $out .= "    st.d    \$r0,$tab_reg,0\n";
    $out .= "    st.d    \$r0,$tab_reg,8\n";
    # T4[8] = H (index 8 → offset 128)
    $out .= "    st.d    \$r12,$tab_reg,128\n";
    $out .= "    st.d    \$r13,$tab_reg,136\n";
    $out .= "    li.d    \$r21,0xe100000000000000\n";
    # T4[4] = rb(H)
    $out .= "    REDUCE1BIT \$r12,\$r13,\$r14,\$r15,\$r21\n";
    $out .= "    st.d    \$r12,$tab_reg,64\n";
    $out .= "    st.d    \$r13,$tab_reg,72\n";
    # T4[2] = rb^2(H)
    $out .= "    REDUCE1BIT \$r12,\$r13,\$r14,\$r15,\$r21\n";
    $out .= "    st.d    \$r12,$tab_reg,32\n";
    $out .= "    st.d    \$r13,$tab_reg,40\n";
    # T4[1] = rb^3(H) (r12/r13 still hold this for composites below)
    $out .= "    REDUCE1BIT \$r12,\$r13,\$r14,\$r15,\$r21\n";
    $out .= "    st.d    \$r12,$tab_reg,16\n";
    $out .= "    st.d    \$r13,$tab_reg,24\n";
    # T4[3] = T4[1] ^ T4[2]
    $out .= "    ld.d    \$r14,$tab_reg,32\n";
    $out .= "    ld.d    \$r15,$tab_reg,40\n";
    $out .= "    xor     \$r14,\$r12,\$r14\n";
    $out .= "    xor     \$r15,\$r13,\$r15\n";
    $out .= "    st.d    \$r14,$tab_reg,48\n";
    $out .= "    st.d    \$r15,$tab_reg,56\n";
    # T4[5..7] = T4[4] ^ T4[1..3]
    $out .= "    ld.d    \$r16,$tab_reg,64\n";
    $out .= "    ld.d    \$r17,$tab_reg,72\n";
    $out .= "    xor     \$r14,\$r16,\$r12\n";   # T4[5]=T4[4]^T4[1]
    $out .= "    xor     \$r15,\$r17,\$r13\n";
    $out .= "    st.d    \$r14,$tab_reg,80\n";
    $out .= "    st.d    \$r15,$tab_reg,88\n";
    $out .= "    ld.d    \$r14,$tab_reg,32\n";
    $out .= "    ld.d    \$r15,$tab_reg,40\n";
    $out .= "    xor     \$r14,\$r16,\$r14\n";   # T4[6]=T4[4]^T4[2]
    $out .= "    xor     \$r15,\$r17,\$r15\n";
    $out .= "    st.d    \$r14,$tab_reg,96\n";
    $out .= "    st.d    \$r15,$tab_reg,104\n";
    $out .= "    ld.d    \$r14,$tab_reg,48\n";
    $out .= "    ld.d    \$r15,$tab_reg,56\n";
    $out .= "    xor     \$r14,\$r16,\$r14\n";   # T4[7]=T4[4]^T4[3]
    $out .= "    xor     \$r15,\$r17,\$r15\n";
    $out .= "    st.d    \$r14,$tab_reg,112\n";
    $out .= "    st.d    \$r15,$tab_reg,120\n";
    # T4[9..15] = T4[8] ^ T4[1..7]
    $out .= "    ld.d    \$r16,$tab_reg,128\n";  # T4[8]
    $out .= "    ld.d    \$r17,$tab_reg,136\n";
    for my $j (1 .. 7) {
        my $src_off = $j * 16;
        my $dst_off = (8 + $j) * 16;
        $out .= "    ld.d    \$r14,$tab_reg,$src_off\n";
        $out .= "    ld.d    \$r15,$tab_reg," . ($src_off+8) . "\n";
        $out .= "    xor     \$r14,\$r16,\$r14\n";
        $out .= "    xor     \$r15,\$r17,\$r15\n";
        $out .= "    st.d    \$r14,$tab_reg,$dst_off\n";
        $out .= "    st.d    \$r15,$tab_reg," . ($dst_off+8) . "\n";
    }

    $out .= "\n    # ── Phase 2: Build T8[16..255] from T4[0..15] ──\n";
    $out .= "    # T8[byte] = shift4(T4[byte & 0xf]) ^ T4[byte >> 4]\n";
    $out .= "    # shift4(Z) = {(Z.hi >> 4) ^ rem_4bit[Z.lo & 0xf], (Z.hi << 60) | (Z.lo >> 4)}\n";
    $out .= "    la.local \$r21,.Lrem_4bit\n";
    $out .= "    ori     \$r20,\$r0,255\n";      # byte counter
    $out .= "${label_prefix}_loop:\n";
    # nlo = byte & 0xf, nhi = byte >> 4
    $out .= "    andi    \$r16,\$r20,0x0f\n";    # nlo
    $out .= "    srli.d  \$r17,\$r20,4\n";        # nhi
    # Load T4[nlo]
    $out .= "    slli.d  \$r16,\$r16,4\n";        # nlo * 16
    $out .= "    add.d   \$r16,$tab_reg,\$r16\n";
    $out .= "    ld.d    \$r12,\$r16,0\n";        # T4[nlo].hi
    $out .= "    ld.d    \$r13,\$r16,8\n";        # T4[nlo].lo
    # shift4(T4[nlo])
    $out .= "    andi    \$r18,\$r13,0x0f\n";     # rem index
    $out .= "    slli.d  \$r18,\$r18,3\n";         # *8 for rem_4bit table
    $out .= "    add.d   \$r18,\$r21,\$r18\n";
    $out .= "    ld.d    \$r18,\$r18,0\n";         # rem_4bit[Z.lo & 0xf]
    $out .= "    slli.d  \$r19,\$r12,60\n";        # Z.hi << 60
    $out .= "    srli.d  \$r13,\$r13,4\n";         # Z.lo >> 4
    $out .= "    or      \$r13,\$r13,\$r19\n";     # new lo
    $out .= "    srli.d  \$r12,\$r12,4\n";         # Z.hi >> 4
    $out .= "    xor     \$r12,\$r12,\$r18\n";     # ^ rem_4bit[rem]
    # XOR T4[nhi]
    $out .= "    slli.d  \$r17,\$r17,4\n";         # nhi * 16
    $out .= "    add.d   \$r17,$tab_reg,\$r17\n";
    $out .= "    ld.d    \$r14,\$r17,0\n";
    $out .= "    ld.d    \$r15,\$r17,8\n";
    $out .= "    xor     \$r12,\$r12,\$r14\n";
    $out .= "    xor     \$r13,\$r13,\$r15\n";
    # Store T8[byte]
    $out .= "    slli.d  \$r16,\$r20,4\n";         # byte * 16
    $out .= "    add.d   \$r16,$tab_reg,\$r16\n";
    $out .= "    st.d    \$r12,\$r16,0\n";
    $out .= "    st.d    \$r13,\$r16,8\n";
    $out .= "    addi.d  \$r20,\$r20,-1\n";
    $out .= "    slti    \$r16,\$r20,16\n";
    $out .= "    beqz    \$r16,${label_prefix}_loop\n";

    $out .= "\n    # ── Phase 3: In-place convert T4[0..15] to T8[0..15] ──\n";
    $out .= "    # T8[i] = shift4(T4[i]) for i=0..15 (since T4[i>>4]=T4[0]={0,0})\n";
    $out .= "    ori     \$r20,\$r0,0\n";          # i = 0
    $out .= "${label_prefix}_fixup:\n";
    $out .= "    slli.d  \$r16,\$r20,4\n";
    $out .= "    add.d   \$r16,$tab_reg,\$r16\n";
    $out .= "    ld.d    \$r12,\$r16,0\n";
    $out .= "    ld.d    \$r13,\$r16,8\n";
    $out .= "    andi    \$r18,\$r13,0x0f\n";
    $out .= "    slli.d  \$r18,\$r18,3\n";
    $out .= "    add.d   \$r18,\$r21,\$r18\n";
    $out .= "    ld.d    \$r18,\$r18,0\n";
    $out .= "    slli.d  \$r19,\$r12,60\n";
    $out .= "    srli.d  \$r13,\$r13,4\n";
    $out .= "    or      \$r13,\$r13,\$r19\n";
    $out .= "    srli.d  \$r12,\$r12,4\n";
    $out .= "    xor     \$r12,\$r12,\$r18\n";
    $out .= "    st.d    \$r12,\$r16,0\n";
    $out .= "    st.d    \$r13,\$r16,8\n";
    $out .= "    addi.d  \$r20,\$r20,1\n";
    $out .= "    slti    \$r16,\$r20,16\n";
    $out .= "    bnez    \$r16,${label_prefix}_fixup\n";

    return $out;
}


sub emit_vpaes_lsx2_top_a {
    return <<'___';
    vori.b    $vr1,$vr9,0
    vori.b    $vr20,$vr9,0
    vori.b    $vr5,$vr11,0
    vori.b    $vr24,$vr11,0
    vandn.v   $vr1,$vr1,$vr0
    vandn.v   $vr20,$vr20,$vr19
    vsrli.w   $vr1,$vr1,4
    vsrli.w   $vr20,$vr20,4
    vand.v    $vr0,$vr0,$vr9
    vand.v    $vr19,$vr19,$vr9
    vshuf.b   $vr5,$vr18,$vr5,$vr0
    vshuf.b   $vr24,$vr18,$vr24,$vr19
___
}

sub emit_vpaes_lsx2_top_b {
    return <<'___';
    vori.b    $vr3,$vr10,0
    vori.b    $vr22,$vr10,0
    vxor.v    $vr0,$vr0,$vr1
    vxor.v    $vr19,$vr19,$vr20
    vshuf.b   $vr3,$vr18,$vr3,$vr1
    vshuf.b   $vr22,$vr18,$vr22,$vr20
    vori.b    $vr4,$vr10,0
    vori.b    $vr23,$vr10,0
    vxor.v    $vr3,$vr3,$vr5
    vxor.v    $vr22,$vr22,$vr24
    vshuf.b   $vr4,$vr18,$vr4,$vr0
    vshuf.b   $vr23,$vr18,$vr23,$vr19
___
}

sub emit_vpaes_lsx2_top_c {
    return <<'___';
    vori.b    $vr2,$vr10,0
    vori.b    $vr21,$vr10,0
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr24
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr10,0
    vori.b    $vr22,$vr10,0
    vxor.v    $vr2,$vr2,$vr0
    vxor.v    $vr21,$vr21,$vr19
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr23
___
}

# ── LSX half-round building blocks for fully-unrolled fused AES-GCM ──
#
# These operate on two separate vr0/vr19 states in parallel.
#
# emit_init_gcm()   – IPT + rk[0] via preloaded vr27/vr28
# emit_half_front() – top_a+b+c + jo-vxor + SubBytes  (~51 SIMD)
# emit_half_back()  – MixColumns via memory-loaded MC tables (~27 SIMD)
# emit_final_gcm()  – last-round sbo via vr29/vr30 + ShiftRows

sub emit_init_gcm {
    # Uses preloaded vr27=Lk_ipt[0], vr28=Lk_ipt[16]
    return <<'___';
    vld       $vr5,$s1,0
    vori.b    $vr1,$vr9,0
    vori.b    $vr20,$vr9,0
    vandn.v   $vr1,$vr1,$vr0
    vandn.v   $vr20,$vr20,$vr19
    vsrli.w   $vr1,$vr1,4
    vsrli.w   $vr20,$vr20,4
    vand.v    $vr0,$vr0,$vr9
    vand.v    $vr19,$vr19,$vr9
    vshuf.b   $vr2,$vr18,$vr27,$vr0
    vshuf.b   $vr21,$vr18,$vr27,$vr19
    vshuf.b   $vr0,$vr18,$vr28,$vr1
    vshuf.b   $vr19,$vr18,$vr28,$vr20
    vxor.v    $vr2,$vr2,$vr5
    vxor.v    $vr21,$vr21,$vr5
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
___
}

sub emit_half_front {
    my ($rk_off) = @_;
    my $out = "";
    $out .= emit_vpaes_lsx2_top_a();
    $out .= emit_vpaes_lsx2_top_b();
    $out .= emit_vpaes_lsx2_top_c();
    # Complete jo:  vr3 ^= vr1,  vr22 ^= vr20
    $out .= "    vxor.v    \$vr3,\$vr3,\$vr1\n";
    $out .= "    vxor.v    \$vr22,\$vr22,\$vr20\n";
    # SubBytes core – round-key from $s1 + compile-time offset
    $out .= <<"___";
    vld       \$vr5,\$s1,$rk_off
    vori.b    \$vr4,\$vr13,0
    vori.b    \$vr23,\$vr13,0
    vori.b    \$vr0,\$vr12,0
    vori.b    \$vr19,\$vr12,0
    vshuf.b   \$vr4,\$vr18,\$vr4,\$vr2
    vshuf.b   \$vr23,\$vr18,\$vr23,\$vr21
    vshuf.b   \$vr0,\$vr18,\$vr0,\$vr3
    vshuf.b   \$vr19,\$vr18,\$vr19,\$vr22
    vxor.v    \$vr4,\$vr4,\$vr5
    vxor.v    \$vr23,\$vr23,\$vr5
    vxor.v    \$vr0,\$vr0,\$vr4
    vxor.v    \$vr19,\$vr19,\$vr23
___
    return $out;
}

sub emit_half_back {
    my ($round) = @_;
    my $mc_idx = $round % 4;
    my $bw_off = $mc_idx * 16;
    my $fw_off = $bw_off - 64;
    my $out = "";
    # mid_b: load MC tables from stack base, sb2 lookups
    $out .= <<"___";
    ld.d      \$r16,\$sp,128
    vld       \$vr1,\$r16,$fw_off
    vori.b    \$vr5,\$vr15,0
    vld       \$vr4,\$r16,$bw_off
    vshuf.b   \$vr5,\$vr18,\$vr5,\$vr2
    vori.b    \$vr24,\$vr15,0
    vshuf.b   \$vr24,\$vr18,\$vr24,\$vr21
    vori.b    \$vr2,\$vr14,0
    vori.b    \$vr21,\$vr14,0
    vshuf.b   \$vr2,\$vr18,\$vr2,\$vr3
    vshuf.b   \$vr21,\$vr18,\$vr21,\$vr22
    vori.b    \$vr3,\$vr0,0
    vori.b    \$vr22,\$vr19,0
    vxor.v    \$vr2,\$vr5,\$vr2
    vxor.v    \$vr21,\$vr24,\$vr21
___
    # mid_c
    $out .= <<'___';
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
___
    # mid_d
    $out .= <<'___';
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
___
    return $out;
}

sub emit_final_gcm {
    my ($final_rk_off, $sr_off) = @_;
    # Uses preloaded vr29=Lk_sbo[0], vr30=Lk_sbo[16]
    return <<"___";
    vld       \$vr5,\$s1,$final_rk_off
    vshuf.b   \$vr4,\$vr18,\$vr29,\$vr2
    vshuf.b   \$vr23,\$vr18,\$vr29,\$vr21
    vxor.v    \$vr4,\$vr4,\$vr5
    vxor.v    \$vr23,\$vr23,\$vr5
    vshuf.b   \$vr0,\$vr18,\$vr30,\$vr3
    vshuf.b   \$vr19,\$vr18,\$vr30,\$vr22
    ld.d      \$r16,\$sp,128
    vld       \$vr1,\$r16,$sr_off
    vxor.v    \$vr0,\$vr0,\$vr4
    vxor.v    \$vr19,\$vr19,\$vr23
    vshuf.b   \$vr0,\$vr18,\$vr0,\$vr1
    vshuf.b   \$vr19,\$vr18,\$vr19,\$vr1
___
}

# ── counter / xor-store / seed / advance (stack-based) ───────────────

sub emit_lsx2_counter_pair {
    return <<'___';
    ld.w        $r16,$sp,144
    revb.2w     $r17,$r16
    vori.b      $vr0,$vr8,0
    vinsgr2vr.w $vr0,$r17,3
    addi.w      $r16,$r16,1
    revb.2w     $r16,$r16
    vori.b      $vr19,$vr8,0
    vinsgr2vr.w $vr19,$r16,3
___
}

sub emit_xor_store_from_stack {
    return <<'___';
    ld.d        $r16,$sp,112
    ld.d        $r17,$sp,120
    vld         $vr6,$r16,0
    vld         $vr7,$r16,16
    vxor.v      $vr6,$vr6,$vr0
    vxor.v      $vr7,$vr7,$vr19
    vst         $vr6,$r17,0
    vst         $vr7,$r17,16
    addi.d      $r16,$r16,32
    addi.d      $r17,$r17,32
    st.d        $r16,$sp,112
    st.d        $r17,$sp,120
___
}

sub emit_seed_ghash_from_cipher_pair {
    return <<'___';
    vpickve2gr.d $r16,$vr6,0
    vpickve2gr.d $r17,$vr6,1
    xor         $r4,$r4,$r16
    xor         $r5,$r5,$r17
    vpickve2gr.d $r11,$vr7,0
    vpickve2gr.d $r12,$vr7,1
    revb.d      $r6,$r4
    revb.d      $r7,$r5
    revb.d      $r11,$r11
    revb.d      $r12,$r12
___
}

sub emit_advance_counter_pair {
    return <<'___';
    ld.w        $r16,$sp,144
    addi.w      $r16,$r16,2
    st.w        $r16,$sp,144
    revb.2w     $r17,$r16
    xvinsgr2vr.w $xr8,$r17,3
___
}

# Merged: loads counter, creates pair, advances, updates template.
# Saves 1 ld.w vs separate counter_pair + advance_counter_pair.
sub emit_lsx2_counter_pair_and_advance {
    return <<'___';
    ld.w        $r16,$sp,144
    revb.2w     $r17,$r16
    vori.b      $vr0,$vr8,0
    vinsgr2vr.w $vr0,$r17,3
    addi.w      $r17,$r16,1
    revb.2w     $r17,$r17
    vori.b      $vr19,$vr8,0
    vinsgr2vr.w $vr19,$r17,3
    addi.w      $r16,$r16,2
    st.w        $r16,$sp,144
    revb.2w     $r16,$r16
    xvinsgr2vr.w $xr8,$r16,3
___
}

sub emit_ghash_combine_xi {
    # revb(A) ^ revb(B) == revb(A^B), saves 2 revb.d
    return <<'___';
    xor         $r8,$r8,$r13
    xor         $r9,$r9,$r14
    revb.d      $r4,$r8
    revb.d      $r5,$r9
___
}

# ── Decrypt: combined xor-store + GHASH seed ──────────────────────
# For decrypt, GHASH feeds on ciphertext = the INPUT blocks (before XOR).
# Extract GHASH input first, then XOR with keystream, then store plaintext.
sub emit_xor_store_and_seed_decrypt {
    return <<'___';
    ld.d        $r16,$sp,112
    ld.d        $r17,$sp,120
    vld         $vr6,$r16,0
    vld         $vr7,$r16,16
    # Seed GHASH from ciphertext (input, before XOR)
    vpickve2gr.d $r18,$vr6,0
    vpickve2gr.d $r19,$vr6,1
    xor         $r4,$r4,$r18
    xor         $r5,$r5,$r19
    vpickve2gr.d $r11,$vr7,0
    vpickve2gr.d $r12,$vr7,1
    revb.d      $r6,$r4
    revb.d      $r7,$r5
    revb.d      $r11,$r11
    revb.d      $r12,$r12
    # XOR with keystream to produce plaintext
    vxor.v      $vr6,$vr6,$vr0
    vxor.v      $vr7,$vr7,$vr19
    # Store plaintext output
    vst         $vr6,$r17,0
    vst         $vr7,$r17,16
    addi.d      $r16,$r16,32
    addi.d      $r17,$r17,32
    st.d        $r16,$sp,112
    st.d        $r17,$sp,120
___
}

sub emit_writeback_xi {
    return <<'___';
    st.d        $r4,$fp,0
    st.d        $r5,$fp,8
___
}

# ── GHASH step emitter ──────────────────────────────────────────────

sub emit_ghash_step {
    my ($step) = @_;           # 1..14
    if ($step <= 7) {
        return "    GHASH8B_STEP2_LO\n";
    } elsif ($step <= 14) {
        return "    GHASH8B_STEP2_HI\n";
    } else {
        return "    GHASH8B_FINAL2\n";
    }
}

# ── Fully-unrolled steady-state template ────────────────────────────
#
# Nr-1 middle AES rounds (half_front + GHASH slot + half_back) plus
# 1 final AES round (top + sbo + ShiftRows).
# 15 GHASH byte-steps (7 LO + 7 HI + 1 FINAL) are evenly distributed across
# the 2*(Nr-1) available half-round slots.

sub emit_warmup_state {
    my ($nr_minus_1) = @_;   # stored rounds: 9 / 11 / 13
    my $num_rounds = $nr_minus_1;
    my $final_rk  = ($nr_minus_1 + 1) * 16;
    my $sr_off    = ((($nr_minus_1 + 1) % 4) * 16) + 64;
    my $out = "";

    for my $r (1 .. $num_rounds) {
        my $rk_off = $r * 16;
        $out .= "    # ── warmup round $r  half-front (rk+$rk_off) ──\n";
        $out .= emit_half_front($rk_off);
        $out .= "    # ── warmup round $r  half-back  (mc_idx=" . ($r%4) . ") ──\n";
        $out .= emit_half_back($r);
    }

    # Final round
    $out .= "    # ── warmup final round (rk+$final_rk, sr_off=$sr_off) ──\n";
    $out .= emit_vpaes_lsx2_top_a();
    $out .= emit_vpaes_lsx2_top_b();
    $out .= emit_vpaes_lsx2_top_c();
    $out .= "    vxor.v    \$vr3,\$vr3,\$vr1\n";
    $out .= "    vxor.v    \$vr22,\$vr22,\$vr20\n";
    $out .= emit_final_gcm($final_rk, $sr_off);
    return $out;
}

sub emit_steady_state {
    my ($nr_minus_1) = @_;   # stored rounds: 9 / 11 / 13
    my $num_rounds = $nr_minus_1;
    my $final_rk  = ($nr_minus_1 + 1) * 16;
    my $sr_off    = ((($nr_minus_1 + 1) % 4) * 16) + 64;
    my $out = "";

    # Evenly distribute 15 GHASH steps across 2*num_rounds slots.
    # Slot numbering: round r has slot_A = 2*(r-1) and slot_B = 2*(r-1)+1.
    # Slot_B for last round is not available (final round follows).
    my $total_slots = 2 * $num_rounds - 1;  # slot_B of last round excluded
    my %ghash_at;
    for my $g (0 .. 13) {
        my $slot = int($g * $total_slots / 14 + 0.5);
        $slot = $total_slots - 1 if $slot >= $total_slots;
        $ghash_at{$slot} = $g + 1;  # GHASH step 1..15
    }

    my $slot = 0;
    for my $r (1 .. $num_rounds) {
        my $rk_off = $r * 16;
        $out .= "    # ── round $r  half-front (rk+$rk_off) ──\n";
        $out .= emit_half_front($rk_off);

        # Slot A: between half-front and half-back
        my $slot_a = 2 * ($r - 1);
        if (exists $ghash_at{$slot_a}) {
            my $gs = $ghash_at{$slot_a};
            my $ty = $gs <= 7 ? "LO" : "HI";
            $out .= "    # GHASH step $gs ($ty)\n";
            $out .= emit_ghash_step($gs);
        }

        $out .= "    # ── round $r  half-back  (mc_idx=" . ($r%4) . ") ──\n";
        $out .= emit_half_back($r);

        # Slot B: between rounds (not available for last round)
        if ($r < $num_rounds) {
            my $slot_b = 2 * ($r - 1) + 1;
            if (exists $ghash_at{$slot_b}) {
                my $gs = $ghash_at{$slot_b};
                my $ty = $gs <= 7 ? "LO" : "HI";
                $out .= "    # GHASH step $gs ($ty)\n";
                $out .= emit_ghash_step($gs);
            }
        }
    }

    # Final round
    $out .= "    # ── final round (rk+$final_rk, sr_off=$sr_off) ──\n";
    $out .= emit_vpaes_lsx2_top_a();
    $out .= emit_vpaes_lsx2_top_b();
    $out .= emit_vpaes_lsx2_top_c();
    $out .= "    vxor.v    \$vr3,\$vr3,\$vr1\n";
    $out .= "    vxor.v    \$vr22,\$vr22,\$vr20\n";
    $out .= emit_final_gcm($final_rk, $sr_off);
    return $out;
}

# ═══════════════════════════════════════════════════════════════════
#  LASX (256-bit) half-round building blocks
#
#  Two AES blocks are packed into one xvr0 register.  All VPAES
#  constants are pre-duplicated to 256-bit via xvreplve0.q in preheat.
#  MixColumns tables and ShiftRows/final-RK are permanently resident
#  in xvr16-25,31, eliminating per-round memory loads.
#
#  emit_init_gcm_lasx()      – IPT via preloaded xvr27/xvr28
#  emit_half_front_lasx()    – top_abc + SubBytes + rk XOR (19 insns)
#  emit_half_back_lasx()     – MixColumns via preloaded xvr16-24 (9 insns)
#  emit_final_gcm_lasx()     – sbo via xvr29/30 + SR via xvr25 (5 insns)
#  emit_lasx_top_abc_jo()    – SubBytes GF(2^4) inversion (13 insns)
#  emit_lasx_sr_preload()    – load SR→xvr25 + final RK→xvr31
# ═══════════════════════════════════════════════════════════════════

sub emit_init_gcm_lasx {
    # IPT on packed xvr0 = [block0 | block1]
    # Uses preloaded xvr27=Lk_ipt[0], xvr28=Lk_ipt[16] (dup'd)
    return <<'___';
    vld       $vr26,$s1,0
    xvandn.v  $xr1,$xr9,$xr0
    xvsrli.w  $xr1,$xr1,4
    xvand.v   $xr0,$xr0,$xr9
    xvreplve0.q $xr26,$xr26
    xvshuf.b  $xr2,$xr18,$xr27,$xr0
    xvshuf.b  $xr0,$xr18,$xr28,$xr1
    xvxor.v   $xr2,$xr2,$xr26
    xvxor.v   $xr0,$xr0,$xr2
___
}

sub emit_half_front_lasx {
    my ($rk_off) = @_;
    return <<"___";
    vld       \$vr26,\$s1,$rk_off
    xvandn.v  \$xr1,\$xr9,\$xr0
    xvsrli.w  \$xr1,\$xr1,4
    xvand.v   \$xr0,\$xr0,\$xr9
    xvshuf.b  \$xr5,\$xr18,\$xr11,\$xr0
    xvshuf.b  \$xr3,\$xr18,\$xr10,\$xr1
    xvreplve0.q \$xr26,\$xr26
    xvxor.v   \$xr0,\$xr0,\$xr1
    xvshuf.b  \$xr4,\$xr18,\$xr10,\$xr0
    xvxor.v   \$xr3,\$xr3,\$xr5
    xvxor.v   \$xr4,\$xr4,\$xr5
    xvshuf.b  \$xr2,\$xr18,\$xr10,\$xr3
    xvshuf.b  \$xr3,\$xr18,\$xr10,\$xr4
    xvxor.v   \$xr2,\$xr2,\$xr0
    xvxor.v   \$xr3,\$xr3,\$xr1
    xvshuf.b  \$xr4,\$xr18,\$xr13,\$xr2
    xvshuf.b  \$xr0,\$xr18,\$xr12,\$xr3
    xvxor.v   \$xr4,\$xr4,\$xr26
    xvxor.v   \$xr0,\$xr0,\$xr4
___
}

sub emit_half_back_lasx {
    my ($round) = @_;
    my $mc_idx = $round % 4;
    # MC forward/backward are preloaded into xvr16-24
    my @fw_regs = ('$xr16', '$xr17', '$xr19', '$xr20');
    my @bw_regs = ('$xr21', '$xr22', '$xr23', '$xr24');
    my $fw = $fw_regs[$mc_idx];
    my $bw = $bw_regs[$mc_idx];
    return <<"___";
    xvshuf.b  \$xr5,\$xr18,\$xr15,\$xr2
    xvshuf.b  \$xr2,\$xr18,\$xr14,\$xr3
    xvshuf.b  \$xr3,\$xr18,\$xr0,$bw
    xvxor.v   \$xr2,\$xr5,\$xr2
    xvshuf.b  \$xr0,\$xr18,\$xr0,$fw
    xvxor.v   \$xr0,\$xr0,\$xr2
    xvxor.v   \$xr3,\$xr3,\$xr0
    xvshuf.b  \$xr0,\$xr18,\$xr0,$fw
    xvxor.v   \$xr0,\$xr0,\$xr3
___
}

sub emit_final_gcm_lasx {
    my ($final_rk_off, $sr_off) = @_;
    # Uses preloaded xvr29/30 for Lk_sbo, xvr25 for ShiftRows, xvr31 for final RK
    return <<"___";
    xvshuf.b  \$xr4,\$xr18,\$xr29,\$xr2
    xvshuf.b  \$xr0,\$xr18,\$xr30,\$xr3
    xvxor.v   \$xr4,\$xr4,\$xr31
    xvxor.v   \$xr0,\$xr0,\$xr4
    xvshuf.b  \$xr0,\$xr18,\$xr0,\$xr25
___
}

sub emit_lasx_top_abc_jo {
    # SubBytes GF(2^4) inversion → io in xr2, jo in xr3
    return <<'___';
    xvandn.v  $xr1,$xr9,$xr0
    xvsrli.w  $xr1,$xr1,4
    xvand.v   $xr0,$xr0,$xr9
    xvshuf.b  $xr5,$xr18,$xr11,$xr0
    xvxor.v   $xr0,$xr0,$xr1
    xvshuf.b  $xr3,$xr18,$xr10,$xr1
    xvshuf.b  $xr4,$xr18,$xr10,$xr0
    xvxor.v   $xr3,$xr3,$xr5
    xvxor.v   $xr4,$xr4,$xr5
    xvshuf.b  $xr2,$xr18,$xr10,$xr3
    xvshuf.b  $xr3,$xr18,$xr10,$xr4
    xvxor.v   $xr2,$xr2,$xr0
    xvxor.v   $xr3,$xr3,$xr1
___
}

# Preload ShiftRows table for given key size into xvr25
# and final round key into xvr31
sub emit_lasx_sr_preload {
    my ($nr_minus_1) = @_;
    my $sr_idx = ($nr_minus_1 + 1) % 4;     # 0..3
    my $sr_off = $sr_idx * 16;               # offset from Lk_sr
    my $final_rk_off = ($nr_minus_1 + 1) * 16;
    return <<"___";
    la.local    \$r16,Lk_sr
    vld         \$vr25,\$r16,$sr_off
    xvreplve0.q \$xr25,\$xr25
    vld         \$vr31,\$s1,$final_rk_off
    xvreplve0.q \$xr31,\$xr31
___
}

# ── LASX counter / xor-store / seed / advance ───────────────────

sub emit_lasx_counter_pair {
    return <<'___';
    ld.w        $r16,$sp,144
    revb.2w     $r17,$r16
    xvori.b     $xr0,$xr8,0
    xvinsgr2vr.w $xr0,$r17,3
    addi.w      $r17,$r16,1
    revb.2w     $r17,$r17
    xvinsgr2vr.w $xr0,$r17,7
___
}

sub emit_lasx_counter_pair_and_advance {
    return <<'___';
    ld.w        $r16,$sp,144
    revb.2w     $r17,$r16
    xvori.b     $xr0,$xr8,0
    xvinsgr2vr.w $xr0,$r17,3
    addi.w      $r17,$r16,1
    revb.2w     $r17,$r17
    xvinsgr2vr.w $xr0,$r17,7
    addi.w      $r16,$r16,2
    st.w        $r16,$sp,144
    revb.2w     $r16,$r16
    xvinsgr2vr.w $xr8,$r16,3
___
}

sub emit_xor_store_from_stack_lasx {
    return <<'___';
    ld.d        $r16,$sp,112
    ld.d        $r17,$sp,120
    xvld        $xr6,$r16,0
    xvxor.v     $xr6,$xr6,$xr0
    xvst        $xr6,$r17,0
    addi.d      $r16,$r16,32
    addi.d      $r17,$r17,32
    st.d        $r16,$sp,112
    st.d        $r17,$sp,120
___
}

sub emit_seed_ghash_from_cipher_pair_lasx {
    return <<'___';
    vpickve2gr.d $r16,$vr6,0
    vpickve2gr.d $r17,$vr6,1
    xor         $r4,$r4,$r16
    xor         $r5,$r5,$r17
    xvpermi.q   $xr7,$xr6,0x01
    vpickve2gr.d $r11,$vr7,0
    vpickve2gr.d $r12,$vr7,1
    revb.d      $r6,$r4
    revb.d      $r7,$r5
    revb.d      $r11,$r11
    revb.d      $r12,$r12
___
}

sub emit_xor_store_and_seed_decrypt_lasx {
    return <<'___';
    ld.d        $r16,$sp,112
    ld.d        $r17,$sp,120
    xvld        $xr6,$r16,0
    # Seed GHASH from ciphertext (before XOR)
    vpickve2gr.d $r18,$vr6,0
    vpickve2gr.d $r19,$vr6,1
    xor         $r4,$r4,$r18
    xor         $r5,$r5,$r19
    xvpermi.q   $xr7,$xr6,0x01
    vpickve2gr.d $r11,$vr7,0
    vpickve2gr.d $r12,$vr7,1
    revb.d      $r6,$r4
    revb.d      $r7,$r5
    revb.d      $r11,$r11
    revb.d      $r12,$r12
    # XOR with keystream + store plaintext
    xvxor.v     $xr6,$xr6,$xr0
    xvst        $xr6,$r17,0
    addi.d      $r16,$r16,32
    addi.d      $r17,$r17,32
    st.d        $r16,$sp,112
    st.d        $r17,$sp,120
___
}

# ── LASX warmup / steady-state templates ─────────────────────────

sub emit_warmup_state_lasx {
    my ($nr_minus_1) = @_;
    my $num_rounds = $nr_minus_1;
    my $final_rk  = ($nr_minus_1 + 1) * 16;
    my $sr_off    = ((($nr_minus_1 + 1) % 4) * 16) + 64;
    my $out = "";

    for my $r (1 .. $num_rounds) {
        my $rk_off = $r * 16;
        $out .= "    # ── LASX warmup round $r  half-front (rk+$rk_off) ──\n";
        $out .= emit_half_front_lasx($rk_off);
        $out .= "    # ── LASX warmup round $r  half-back  (mc_idx=" . ($r%4) . ") ──\n";
        $out .= emit_half_back_lasx($r);
    }

    $out .= "    # ── LASX warmup final round (rk+$final_rk, sr_off=$sr_off) ──\n";
    $out .= emit_lasx_top_abc_jo();
    $out .= emit_final_gcm_lasx($final_rk, $sr_off);
    return $out;
}

sub emit_steady_state_lasx {
    my ($nr_minus_1) = @_;
    my $num_rounds = $nr_minus_1;
    my $final_rk  = ($nr_minus_1 + 1) * 16;
    my $sr_off    = ((($nr_minus_1 + 1) % 4) * 16) + 64;
    my $out = "";

    my $total_slots = 2 * $num_rounds - 1;
    my %ghash_at;
    for my $g (0 .. 13) {
        my $slot = int($g * $total_slots / 14 + 0.5);
        $slot = $total_slots - 1 if $slot >= $total_slots;
        $ghash_at{$slot} = $g + 1;
    }

    for my $r (1 .. $num_rounds) {
        my $rk_off = $r * 16;
        $out .= "    # ── LASX round $r  half-front (rk+$rk_off) ──\n";
        $out .= emit_half_front_lasx($rk_off);

        my $slot_a = 2 * ($r - 1);
        if (exists $ghash_at{$slot_a}) {
            my $gs = $ghash_at{$slot_a};
            my $ty = $gs <= 7 ? "LO" : "HI";
            $out .= "    # GHASH step $gs ($ty)\n";
            $out .= emit_ghash_step($gs);
        }

        $out .= "    # ── LASX round $r  half-back  (mc_idx=" . ($r%4) . ") ──\n";
        $out .= emit_half_back_lasx($r);

        if ($r < $num_rounds) {
            my $slot_b = 2 * ($r - 1) + 1;
            if (exists $ghash_at{$slot_b}) {
                my $gs = $ghash_at{$slot_b};
                my $ty = $gs <= 7 ? "LO" : "HI";
                $out .= "    # GHASH step $gs ($ty)\n";
                $out .= emit_ghash_step($gs);
            }
        }
    }

    $out .= "    # ── LASX final round (rk+$final_rk, sr_off=$sr_off) ──\n";
    $out .= emit_lasx_top_abc_jo();
    $out .= emit_final_gcm_lasx($final_rk, $sr_off);
    return $out;
}

my $code = <<'___';
.text

.macro REDUCE1BIT HI LO TMP0 TMP1 POLY
    andi    \TMP0,\LO,0x1
    sub.d   \TMP0,$r0,\TMP0
    and     \TMP0,\TMP0,\POLY
    slli.d  \TMP1,\HI,63
    srli.d  \LO,\LO,1
    or      \LO,\LO,\TMP1
    srli.d  \HI,\HI,1
    xor     \HI,\HI,\TMP0
.endm

# ── 8-bit table GHASH macros ─────────────────────────────────────────
# Each H value has a 256-entry table (4096 bytes = 256 x 16).
# T[i] = i * H in GF(2^128), reflected GCM convention.
# Index 128 = H (x^0), basis via REDUCE1BIT: T[64]=x*H, ..., T[1]=x^7*H.
#
# GHASH8B_INIT:   5 instructions - extract byte 0, look up Z=T[byte], advance
# GHASH8B_STEP:  14 instructions - shift Z>>8, reduce, XOR T[next_byte], advance
# GHASH8B_FINAL: 13 instructions - same as STEP without final advance

.macro GHASH8B_INIT TAB SRCLO ZHI ZLO T0
    andi    \T0,    \SRCLO, 0xff
    alsl.d  \T0,    \T0, \TAB, 4
    ld.d    \ZHI,   \T0, 0
    ld.d    \ZLO,   \T0, 8
    srli.d  \SRCLO, \SRCLO, 8
.endm

.macro GHASH8B_STEP TAB SRC ZHI ZLO T0 T1
    andi    \T0,    \ZLO, 0xff
    srli.d  \ZLO,   \ZLO, 8
    bstrins.d \ZLO, \ZHI, 63, 56
    srli.d  \ZHI,   \ZHI, 8
    alsl.d  \T0,    \T0, $s2, 3
    ld.d    \T0,    \T0, 0
    xor     \ZHI,   \ZHI, \T0
    andi    \T1,    \SRC, 0xff
    alsl.d  \T1,    \T1, \TAB, 4
    ld.d    \T0,    \T1, 0
    ld.d    \T1,    \T1, 8
    xor     \ZHI,   \ZHI, \T0
    xor     \ZLO,   \ZLO, \T1
    srli.d  \SRC,   \SRC, 8
.endm

.macro GHASH8B_FINAL TAB SRC ZHI ZLO T0 T1
    andi    \T0,    \ZLO, 0xff
    srli.d  \ZLO,   \ZLO, 8
    bstrins.d \ZLO, \ZHI, 63, 56
    srli.d  \ZHI,   \ZHI, 8
    alsl.d  \T0,    \T0, $s2, 3
    ld.d    \T0,    \T0, 0
    xor     \ZHI,   \ZHI, \T0
    andi    \T1,    \SRC, 0xff
    alsl.d  \T1,    \T1, \TAB, 4
    ld.d    \T0,    \T1, 0
    ld.d    \T1,    \T1, 8
    xor     \ZHI,   \ZHI, \T0
    xor     \ZLO,   \ZLO, \T1
.endm

.macro GHASH8B_INIT2
    GHASH8B_INIT $s6, $r7,  $r8,  $r9,  $r16
    GHASH8B_INIT $s3, $r12, $r13, $r14, $r19
.endm

.macro GHASH8B_STEP2_LO
    GHASH8B_STEP $s6, $r7,  $r8,  $r9,  $r16, $r17
    GHASH8B_STEP $s3, $r12, $r13, $r14, $r19, $r20
.endm

.macro GHASH8B_STEP2_HI
    GHASH8B_STEP $s6, $r6,  $r8,  $r9,  $r16, $r17
    GHASH8B_STEP $s3, $r11, $r13, $r14, $r19, $r20
.endm

.macro GHASH8B_FINAL2
    GHASH8B_FINAL $s6, $r6,  $r8,  $r9,  $r16, $r17
    GHASH8B_FINAL $s3, $r11, $r13, $r14, $r19, $r20
.endm

.section .rodata

# VPAES constant tables (duplicated from vpaes-loongarch64 for same-unit access)
.align 6
Lk_inv:
    .quad 0x0E05060F0D080110, 0x040703090A0B0C02
    .quad 0x01040A060F0B0710, 0x030D0E0C02050809

Lk_s0F:
    .quad 0x0F0F0F0F0F0F0F0F, 0x0F0F0F0F0F0F0F0F

Lk_ipt:
    .quad 0xC2B2E8985A2A7000, 0xCABAE09052227808
    .quad 0x4C01307D317C4D00, 0xCD80B1FCB0FDCC81

Lk_sb1:
    .quad 0xB19BE18FCB503E00, 0xA5DF7A6E142AF544
    .quad 0x3618D415FAE22300, 0x3BF7CCC10D2ED9EF
Lk_sb2:
    .quad 0xE27A93C60B712400, 0x5EB7E955BC982FCD
    .quad 0x69EB88400AE12900, 0xC2A163C8AB82234A
Lk_sbo:
    .quad 0xD0D26D176FBDC700, 0x15AABF7AC502A878
    .quad 0xCFE474A55FBB6A00, 0x8E1E90D1412B35FA

Lk_mc_forward:
    .quad 0x0407060500030201, 0x0C0F0E0D080B0A09
    .quad 0x080B0A0904070605, 0x000302010C0F0E0D
    .quad 0x0C0F0E0D080B0A09, 0x0407060500030201
    .quad 0x000302010C0F0E0D, 0x080B0A0904070605

Lk_mc_backward:
    .quad 0x0605040702010003, 0x0E0D0C0F0A09080B
    .quad 0x020100030E0D0C0F, 0x0A09080B06050407
    .quad 0x0E0D0C0F0A09080B, 0x0605040702010003
    .quad 0x0A09080B06050407, 0x020100030E0D0C0F

Lk_sr:
    .quad 0x0706050403020100, 0x0F0E0D0C0B0A0908
    .quad 0x030E09040F0A0500, 0x0B06010C07020D08
    .quad 0x0F060D040B020900, 0x070E050C030A0108
    .quad 0x0B0E0104070A0D00, 0x0306090C0F020508

.align 4
.Lrem_4bit:
    .dword 0x0000000000000000
    .dword 0x1C20000000000000
    .dword 0x3840000000000000
    .dword 0x2460000000000000
    .dword 0x7080000000000000
    .dword 0x6CA0000000000000
    .dword 0x48C0000000000000
    .dword 0x54E0000000000000
    .dword 0xE100000000000000
    .dword 0xFD20000000000000
    .dword 0xD940000000000000
    .dword 0xC560000000000000
    .dword 0x9180000000000000
    .dword 0x8DA0000000000000
    .dword 0xA9C0000000000000
    .dword 0xB5E0000000000000

.align 4
.Lrem_8bit:
    .hword 0x0000, 0x01C2, 0x0384, 0x0246, 0x0708, 0x06CA, 0x048C, 0x054E
    .hword 0x0E10, 0x0FD2, 0x0D94, 0x0C56, 0x0918, 0x08DA, 0x0A9C, 0x0B5E
    .hword 0x1C20, 0x1DE2, 0x1FA4, 0x1E66, 0x1B28, 0x1AEA, 0x18AC, 0x196E
    .hword 0x1230, 0x13F2, 0x11B4, 0x1076, 0x1538, 0x14FA, 0x16BC, 0x177E
    .hword 0x3840, 0x3982, 0x3BC4, 0x3A06, 0x3F48, 0x3E8A, 0x3CCC, 0x3D0E
    .hword 0x3650, 0x3792, 0x35D4, 0x3416, 0x3158, 0x309A, 0x32DC, 0x331E
    .hword 0x2460, 0x25A2, 0x27E4, 0x2626, 0x2368, 0x22AA, 0x20EC, 0x212E
    .hword 0x2A70, 0x2BB2, 0x29F4, 0x2836, 0x2D78, 0x2CBA, 0x2EFC, 0x2F3E
    .hword 0x7080, 0x7142, 0x7304, 0x72C6, 0x7788, 0x764A, 0x740C, 0x75CE
    .hword 0x7E90, 0x7F52, 0x7D14, 0x7CD6, 0x7998, 0x785A, 0x7A1C, 0x7BDE
    .hword 0x6CA0, 0x6D62, 0x6F24, 0x6EE6, 0x6BA8, 0x6A6A, 0x682C, 0x69EE
    .hword 0x62B0, 0x6372, 0x6134, 0x60F6, 0x65B8, 0x647A, 0x663C, 0x67FE
    .hword 0x48C0, 0x4902, 0x4B44, 0x4A86, 0x4FC8, 0x4E0A, 0x4C4C, 0x4D8E
    .hword 0x46D0, 0x4712, 0x4554, 0x4496, 0x41D8, 0x401A, 0x425C, 0x439E
    .hword 0x54E0, 0x5522, 0x5764, 0x56A6, 0x53E8, 0x522A, 0x506C, 0x51AE
    .hword 0x5AF0, 0x5B32, 0x5974, 0x58B6, 0x5DF8, 0x5C3A, 0x5E7C, 0x5FBE
    .hword 0xE100, 0xE0C2, 0xE284, 0xE346, 0xE608, 0xE7CA, 0xE58C, 0xE44E
    .hword 0xEF10, 0xEED2, 0xEC94, 0xED56, 0xE818, 0xE9DA, 0xEB9C, 0xEA5E
    .hword 0xFD20, 0xFCE2, 0xFEA4, 0xFF66, 0xFA28, 0xFBEA, 0xF9AC, 0xF86E
    .hword 0xF330, 0xF2F2, 0xF0B4, 0xF176, 0xF438, 0xF5FA, 0xF7BC, 0xF67E
    .hword 0xD940, 0xD882, 0xDAC4, 0xDB06, 0xDE48, 0xDF8A, 0xDDCC, 0xDC0E
    .hword 0xD750, 0xD692, 0xD4D4, 0xD516, 0xD058, 0xD19A, 0xD3DC, 0xD21E
    .hword 0xC560, 0xC4A2, 0xC6E4, 0xC726, 0xC268, 0xC3AA, 0xC1EC, 0xC02E
    .hword 0xCB70, 0xCAB2, 0xC8F4, 0xC936, 0xCC78, 0xCDBA, 0xCFFC, 0xCE3E
    .hword 0x9180, 0x9042, 0x9204, 0x93C6, 0x9688, 0x974A, 0x950C, 0x94CE
    .hword 0x9F90, 0x9E52, 0x9C14, 0x9DD6, 0x9898, 0x995A, 0x9B1C, 0x9ADE
    .hword 0x8DA0, 0x8C62, 0x8E24, 0x8FE6, 0x8AA8, 0x8B6A, 0x892C, 0x88EE
    .hword 0x83B0, 0x8272, 0x8034, 0x81F6, 0x84B8, 0x857A, 0x873C, 0x86FE
    .hword 0xA9C0, 0xA802, 0xAA44, 0xAB86, 0xAEC8, 0xAF0A, 0xAD4C, 0xAC8E
    .hword 0xA7D0, 0xA612, 0xA454, 0xA596, 0xA0D8, 0xA11A, 0xA35C, 0xA29E
    .hword 0xB5E0, 0xB422, 0xB664, 0xB7A6, 0xB2E8, 0xB32A, 0xB16C, 0xB0AE
    .hword 0xBBF0, 0xBA32, 0xB874, 0xB9B6, 0xBCF8, 0xBD3A, 0xBF7C, 0xBEBE

# Pre-shifted reduction table: each entry = rem_8bit[i] << 48, stored as .dword
# Eliminates slli.d 48 after each lookup in GHASH8B_STEP/FINAL
.align 4
.Lrem_8bit_shl48:
    .dword 0x0000000000000000, 0x01C2000000000000, 0x0384000000000000, 0x0246000000000000
    .dword 0x0708000000000000, 0x06CA000000000000, 0x048C000000000000, 0x054E000000000000
    .dword 0x0E10000000000000, 0x0FD2000000000000, 0x0D94000000000000, 0x0C56000000000000
    .dword 0x0918000000000000, 0x08DA000000000000, 0x0A9C000000000000, 0x0B5E000000000000
    .dword 0x1C20000000000000, 0x1DE2000000000000, 0x1FA4000000000000, 0x1E66000000000000
    .dword 0x1B28000000000000, 0x1AEA000000000000, 0x18AC000000000000, 0x196E000000000000
    .dword 0x1230000000000000, 0x13F2000000000000, 0x11B4000000000000, 0x1076000000000000
    .dword 0x1538000000000000, 0x14FA000000000000, 0x16BC000000000000, 0x177E000000000000
    .dword 0x3840000000000000, 0x3982000000000000, 0x3BC4000000000000, 0x3A06000000000000
    .dword 0x3F48000000000000, 0x3E8A000000000000, 0x3CCC000000000000, 0x3D0E000000000000
    .dword 0x3650000000000000, 0x3792000000000000, 0x35D4000000000000, 0x3416000000000000
    .dword 0x3158000000000000, 0x309A000000000000, 0x32DC000000000000, 0x331E000000000000
    .dword 0x2460000000000000, 0x25A2000000000000, 0x27E4000000000000, 0x2626000000000000
    .dword 0x2368000000000000, 0x22AA000000000000, 0x20EC000000000000, 0x212E000000000000
    .dword 0x2A70000000000000, 0x2BB2000000000000, 0x29F4000000000000, 0x2836000000000000
    .dword 0x2D78000000000000, 0x2CBA000000000000, 0x2EFC000000000000, 0x2F3E000000000000
    .dword 0x7080000000000000, 0x7142000000000000, 0x7304000000000000, 0x72C6000000000000
    .dword 0x7788000000000000, 0x764A000000000000, 0x740C000000000000, 0x75CE000000000000
    .dword 0x7E90000000000000, 0x7F52000000000000, 0x7D14000000000000, 0x7CD6000000000000
    .dword 0x7998000000000000, 0x785A000000000000, 0x7A1C000000000000, 0x7BDE000000000000
    .dword 0x6CA0000000000000, 0x6D62000000000000, 0x6F24000000000000, 0x6EE6000000000000
    .dword 0x6BA8000000000000, 0x6A6A000000000000, 0x682C000000000000, 0x69EE000000000000
    .dword 0x62B0000000000000, 0x6372000000000000, 0x6134000000000000, 0x60F6000000000000
    .dword 0x65B8000000000000, 0x647A000000000000, 0x663C000000000000, 0x67FE000000000000
    .dword 0x48C0000000000000, 0x4902000000000000, 0x4B44000000000000, 0x4A86000000000000
    .dword 0x4FC8000000000000, 0x4E0A000000000000, 0x4C4C000000000000, 0x4D8E000000000000
    .dword 0x46D0000000000000, 0x4712000000000000, 0x4554000000000000, 0x4496000000000000
    .dword 0x41D8000000000000, 0x401A000000000000, 0x425C000000000000, 0x439E000000000000
    .dword 0x54E0000000000000, 0x5522000000000000, 0x5764000000000000, 0x56A6000000000000
    .dword 0x53E8000000000000, 0x522A000000000000, 0x506C000000000000, 0x51AE000000000000
    .dword 0x5AF0000000000000, 0x5B32000000000000, 0x5974000000000000, 0x58B6000000000000
    .dword 0x5DF8000000000000, 0x5C3A000000000000, 0x5E7C000000000000, 0x5FBE000000000000
    .dword 0xE100000000000000, 0xE0C2000000000000, 0xE284000000000000, 0xE346000000000000
    .dword 0xE608000000000000, 0xE7CA000000000000, 0xE58C000000000000, 0xE44E000000000000
    .dword 0xEF10000000000000, 0xEED2000000000000, 0xEC94000000000000, 0xED56000000000000
    .dword 0xE818000000000000, 0xE9DA000000000000, 0xEB9C000000000000, 0xEA5E000000000000
    .dword 0xFD20000000000000, 0xFCE2000000000000, 0xFEA4000000000000, 0xFF66000000000000
    .dword 0xFA28000000000000, 0xFBEA000000000000, 0xF9AC000000000000, 0xF86E000000000000
    .dword 0xF330000000000000, 0xF2F2000000000000, 0xF0B4000000000000, 0xF176000000000000
    .dword 0xF438000000000000, 0xF5FA000000000000, 0xF7BC000000000000, 0xF67E000000000000
    .dword 0xD940000000000000, 0xD882000000000000, 0xDAC4000000000000, 0xDB06000000000000
    .dword 0xDE48000000000000, 0xDF8A000000000000, 0xDDCC000000000000, 0xDC0E000000000000
    .dword 0xD750000000000000, 0xD692000000000000, 0xD4D4000000000000, 0xD516000000000000
    .dword 0xD058000000000000, 0xD19A000000000000, 0xD3DC000000000000, 0xD21E000000000000
    .dword 0xC560000000000000, 0xC4A2000000000000, 0xC6E4000000000000, 0xC726000000000000
    .dword 0xC268000000000000, 0xC3AA000000000000, 0xC1EC000000000000, 0xC02E000000000000
    .dword 0xCB70000000000000, 0xCAB2000000000000, 0xC8F4000000000000, 0xC936000000000000
    .dword 0xCC78000000000000, 0xCDBA000000000000, 0xCFFC000000000000, 0xCE3E000000000000
    .dword 0x9180000000000000, 0x9042000000000000, 0x9204000000000000, 0x93C6000000000000
    .dword 0x9688000000000000, 0x974A000000000000, 0x950C000000000000, 0x94CE000000000000
    .dword 0x9F90000000000000, 0x9E52000000000000, 0x9C14000000000000, 0x9DD6000000000000
    .dword 0x9898000000000000, 0x995A000000000000, 0x9B1C000000000000, 0x9ADE000000000000
    .dword 0x8DA0000000000000, 0x8C62000000000000, 0x8E24000000000000, 0x8FE6000000000000
    .dword 0x8AA8000000000000, 0x8B6A000000000000, 0x892C000000000000, 0x88EE000000000000
    .dword 0x83B0000000000000, 0x8272000000000000, 0x8034000000000000, 0x81F6000000000000
    .dword 0x84B8000000000000, 0x857A000000000000, 0x873C000000000000, 0x86FE000000000000
    .dword 0xA9C0000000000000, 0xA802000000000000, 0xAA44000000000000, 0xAB86000000000000
    .dword 0xAEC8000000000000, 0xAF0A000000000000, 0xAD4C000000000000, 0xAC8E000000000000
    .dword 0xA7D0000000000000, 0xA612000000000000, 0xA454000000000000, 0xA596000000000000
    .dword 0xA0D8000000000000, 0xA11A000000000000, 0xA35C000000000000, 0xA29E000000000000
    .dword 0xB5E0000000000000, 0xB422000000000000, 0xB664000000000000, 0xB7A6000000000000
    .dword 0xB2E8000000000000, 0xB32A000000000000, 0xB16C000000000000, 0xB0AE000000000000
    .dword 0xBBF0000000000000, 0xBA32000000000000, 0xB874000000000000, 0xB9B6000000000000
    .dword 0xBCF8000000000000, 0xBD3A000000000000, 0xBF7C000000000000, 0xBEBE000000000000

.text

# Local copy of _vpaes_preheat for this compilation unit.
# Loads VPAES constant tables into vr9-vr15, vr18.
.align 4
_vpaes_preheat:
    la.local  $a6,Lk_s0F
    vld       $vr10,$a6,-0x20
    vld       $vr11,$a6,-0x10
    vld       $vr9,$a6,0
    vld       $vr13,$a6,0x30
    vld       $vr12,$a6,0x40
    vld       $vr15,$a6,0x50
    vld       $vr14,$a6,0x60
    vldi      $vr18,0
    jirl      $zero,$ra,0

# LASX preheat: load 256-bit constants + Lk_ipt/Lk_sbo + MC forward/backward
# Registers loaded:
#   xvr9-15,18     VPAES constants (duplicated)
#   xvr27/28       Lk_ipt[0/16]
#   xvr29/30       Lk_sbo[0/16]
#   xvr16,17,19,20 MC_forward[0..3]
#   xvr21,22,23,24 MC_backward[0..3]
.align 4
_vpaes_lasx_preheat_gcm:
    la.local  $a6,Lk_s0F
    vld       $vr10,$a6,-0x20
    xvreplve0.q $xr10,$xr10
    vld       $vr11,$a6,-0x10
    xvreplve0.q $xr11,$xr11
    vld       $vr9,$a6,0
    xvreplve0.q $xr9,$xr9
    vld       $vr13,$a6,0x30
    xvreplve0.q $xr13,$xr13
    vld       $vr12,$a6,0x40
    xvreplve0.q $xr12,$xr12
    vld       $vr15,$a6,0x50
    xvreplve0.q $xr15,$xr15
    vld       $vr14,$a6,0x60
    xvreplve0.q $xr14,$xr14
    xvldi     $xr18,0
    la.local  $r16,Lk_ipt
    vld       $vr27,$r16,0
    xvreplve0.q $xr27,$xr27
    vld       $vr28,$r16,16
    xvreplve0.q $xr28,$xr28
    la.local  $r16,Lk_sbo
    vld       $vr29,$r16,0
    xvreplve0.q $xr29,$xr29
    vld       $vr30,$r16,16
    xvreplve0.q $xr30,$xr30
    # Preload MC forward[0..3] into xvr16,17,19,20
    la.local  $r16,Lk_mc_forward
    vld       $vr16,$r16,0
    xvreplve0.q $xr16,$xr16
    vld       $vr17,$r16,16
    xvreplve0.q $xr17,$xr17
    vld       $vr19,$r16,32
    xvreplve0.q $xr19,$xr19
    vld       $vr20,$r16,48
    xvreplve0.q $xr20,$xr20
    # Preload MC backward[0..3] into xvr21,22,23,24
    la.local  $r16,Lk_mc_backward
    vld       $vr21,$r16,0
    xvreplve0.q $xr21,$xr21
    vld       $vr22,$r16,16
    xvreplve0.q $xr22,$xr22
    vld       $vr23,$r16,32
    xvreplve0.q $xr23,$xr23
    vld       $vr24,$r16,48
    xvreplve0.q $xr24,$xr24
    jirl      $zero,$ra,0

.globl  loongarch64_vpaes_gcm_encrypt
.type   loongarch64_vpaes_gcm_encrypt,@function
.align  4
loongarch64_vpaes_gcm_encrypt:
.cfi_startproc
    beqz    $a2,.Lgcm_enc_ret0

    addi.d  $sp,$sp,-192
    st.d    $ra,$sp,0
    st.d    $fp,$sp,8
    st.d    $s0,$sp,16
    st.d    $s1,$sp,24
    st.d    $s2,$sp,32
    st.d    $s3,$sp,40
    st.d    $s4,$sp,48
    st.d    $s5,$sp,56
    st.d    $s6,$sp,64
    st.d    $s7,$sp,72
    st.d    $s8,$sp,80

    ori     $fp,$a5,0           # Xi*
    ori     $s1,$a3,0           # AES key schedule
    # aligned_len = len & -32
    ori     $s0,$a2,0
    bstrins.d $s0,$zero,4,0
    beqz    $s0,.Lgcm_enc_done

    # Save inp / out / ivec to stack (GPRs will be reused for GHASH)
    st.d    $a0,$sp,112
    st.d    $a1,$sp,120
    st.d    $a4,$sp,136

    st.d    $s0,$sp,152         # save aligned_len for return

    la.local $s2,.Lrem_8bit_shl48
    addi.d  $s3,$fp,288         # cached H 8-bit table
    lu12i.w $r16,1
    add.d   $s6,$s3,$r16        # cached H^2 8-bit table

    # Load counter, save counter to stack.
    ld.d    $r16,$sp,136
    vld     $vr8,$r16,0
    ld.w    $r16,$r16,12
    revb.2w $r16,$r16
    st.w    $r16,$sp,144

    # Preheat VPAES constants.
    ori     $a2,$s1,0
    bl      _vpaes_preheat

    # Save MC table base for unrolled steady state.
    la.local $r16,Lk_mc_backward
    st.d    $r16,$sp,128

    # Preload Lk_ipt and Lk_sbo into persistent VPRs (survive across loop).
    la.local $r16,Lk_ipt
    vld     $vr27,$r16,0
    vld     $vr28,$r16,16
    la.local $r16,Lk_sbo
    vld     $vr29,$r16,0
    vld     $vr30,$r16,16

    # Load Xi state (must be after preheat which clobbers $r4/$r5).
    ld.d    $r4,$fp,0
    ld.d    $r5,$fp,8

    # ─── warmup: encrypt pair 0 (unrolled, no GHASH) ──────────────
___
$code .= emit_lsx2_counter_pair();
$code .= emit_init_gcm();

# Warmup dispatch by key size
$code .= <<'___';
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Lwarm_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Lwarm_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Lwarm_256
    b           .Lgcm_enc_done
.Lwarm_128:
___
$code .= emit_warmup_state(9);
$code .= <<'___';
    b           .Lwarm_after
.Lwarm_192:
___
$code .= emit_warmup_state(11);
$code .= <<'___';
    b           .Lwarm_after
.Lwarm_256:
___
$code .= emit_warmup_state(13);
$code .= <<'___';
.Lwarm_after:

    # ── warmup after-body: xor-store, seed GHASH, INIT2, advance ──
___
$code .= emit_xor_store_from_stack();
$code .= emit_seed_ghash_from_cipher_pair();
$code .= <<'___';
    GHASH8B_INIT2
___
$code .= emit_advance_counter_pair();
$code .= <<'___';
    addi.d      $s0,$s0,-32
    beqz        $s0,.Lgcm_drain

    # ─── key-size dispatch (once, outside loop) ─────────────────────
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Lgcm_loop_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Lgcm_loop_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Lgcm_loop_256
    b           .Lgcm_enc_done

    # ── AES-128 self-contained loop ────────────────────────────────
.Lgcm_loop_128:
___
$code .= emit_lsx2_counter_pair_and_advance();
$code .= emit_init_gcm();
$code .= emit_steady_state(9);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_from_stack();
$code .= emit_seed_ghash_from_cipher_pair();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_loop_128
    b           .Lgcm_drain

    # ── AES-192 self-contained loop ────────────────────────────────
.Lgcm_loop_192:
___
$code .= emit_lsx2_counter_pair_and_advance();
$code .= emit_init_gcm();
$code .= emit_steady_state(11);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_from_stack();
$code .= emit_seed_ghash_from_cipher_pair();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_loop_192
    b           .Lgcm_drain

    # ── AES-256 self-contained loop ────────────────────────────────
.Lgcm_loop_256:
___
$code .= emit_lsx2_counter_pair_and_advance();
$code .= emit_init_gcm();
$code .= emit_steady_state(13);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_from_stack();
$code .= emit_seed_ghash_from_cipher_pair();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_loop_256
    b           .Lgcm_drain

    # ─── drain: finish last GHASH (non-interleaved) ─────────────────
.Lgcm_drain:
    .rept 7
    GHASH8B_STEP2_LO
    .endr
    .rept 7
    GHASH8B_STEP2_HI
    .endr
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_writeback_xi();
$code .= <<'___';
    # Write counter back to ivec.
    ld.w    $r16,$sp,144
    revb.2w $r16,$r16
    xvinsgr2vr.w $xr8,$r16,3
    ld.d    $r16,$sp,136
    vst     $vr8,$r16,0

.Lgcm_enc_done:
    ld.d    $a0,$sp,152         # return aligned_len

.Lgcm_epilogue:
    ld.d    $ra,$sp,0
    ld.d    $fp,$sp,8
    ld.d    $s0,$sp,16
    ld.d    $s1,$sp,24
    ld.d    $s2,$sp,32
    ld.d    $s3,$sp,40
    ld.d    $s4,$sp,48
    ld.d    $s5,$sp,56
    ld.d    $s6,$sp,64
    ld.d    $s7,$sp,72
    ld.d    $s8,$sp,80
    addi.d  $sp,$sp,192
    jirl    $zero,$ra,0

.Lgcm_enc_ret0:
    move    $a0,$zero
    jirl    $zero,$ra,0
.cfi_endproc
.size   loongarch64_vpaes_gcm_encrypt,.-loongarch64_vpaes_gcm_encrypt

___

# ═══════════════════════════════════════════════════════════════════
#  DECRYPT function
# ═══════════════════════════════════════════════════════════════════
# Identical to encrypt except GHASH feeds on ciphertext (input)
# rather than on the XOR result (output).

$code .= <<'___';
.globl  loongarch64_vpaes_gcm_decrypt
.type   loongarch64_vpaes_gcm_decrypt,@function
.align  4
loongarch64_vpaes_gcm_decrypt:
.cfi_startproc
    beqz    $a2,.Lgcm_dec_ret0

    addi.d  $sp,$sp,-192
    st.d    $ra,$sp,0
    st.d    $fp,$sp,8
    st.d    $s0,$sp,16
    st.d    $s1,$sp,24
    st.d    $s2,$sp,32
    st.d    $s3,$sp,40
    st.d    $s4,$sp,48
    st.d    $s5,$sp,56
    st.d    $s6,$sp,64
    st.d    $s7,$sp,72
    st.d    $s8,$sp,80

    ori     $fp,$a5,0           # Xi*
    ori     $s1,$a3,0           # AES key schedule
    # aligned_len = len & -32
    ori     $s0,$a2,0
    bstrins.d $s0,$zero,4,0
    beqz    $s0,.Lgcm_dec_done

    # Save inp / out / ivec to stack (GPRs will be reused for GHASH)
    st.d    $a0,$sp,112
    st.d    $a1,$sp,120
    st.d    $a4,$sp,136

    st.d    $s0,$sp,152         # save aligned_len for return

    la.local $s2,.Lrem_8bit_shl48
    addi.d  $s3,$fp,288         # cached H 8-bit table
    lu12i.w $r16,1
    add.d   $s6,$s3,$r16        # cached H^2 8-bit table

    # Load counter, save counter to stack.
    ld.d    $r16,$sp,136
    vld     $vr8,$r16,0
    ld.w    $r16,$r16,12
    revb.2w $r16,$r16
    st.w    $r16,$sp,144

    # Preheat VPAES constants.
    ori     $a2,$s1,0
    bl      _vpaes_preheat

    # Save MC table base for unrolled steady state.
    la.local $r16,Lk_mc_backward
    st.d    $r16,$sp,128

    # Preload Lk_ipt and Lk_sbo into persistent VPRs (survive across loop).
    la.local $r16,Lk_ipt
    vld     $vr27,$r16,0
    vld     $vr28,$r16,16
    la.local $r16,Lk_sbo
    vld     $vr29,$r16,0
    vld     $vr30,$r16,16

    # Load Xi state (must be after preheat which clobbers $r4/$r5).
    ld.d    $r4,$fp,0
    ld.d    $r5,$fp,8

    # ─── warmup: decrypt pair 0 (unrolled, no GHASH) ──────────────
___
$code .= emit_lsx2_counter_pair();
$code .= emit_init_gcm();

# Warmup dispatch by key size (decrypt)
$code .= <<'___';
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Ldec_warm_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Ldec_warm_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Ldec_warm_256
    b           .Lgcm_dec_done
.Ldec_warm_128:
___
$code .= emit_warmup_state(9);
$code .= <<'___';
    b           .Ldec_warm_after
.Ldec_warm_192:
___
$code .= emit_warmup_state(11);
$code .= <<'___';
    b           .Ldec_warm_after
.Ldec_warm_256:
___
$code .= emit_warmup_state(13);
$code .= <<'___';
.Ldec_warm_after:

    # ── warmup after-body: xor-store+seed (decrypt), INIT2, advance ──
___
$code .= emit_xor_store_and_seed_decrypt();
$code .= <<'___';
    GHASH8B_INIT2
___
$code .= emit_advance_counter_pair();
$code .= <<'___';
    addi.d      $s0,$s0,-32
    beqz        $s0,.Lgcm_dec_drain

    # ─── key-size dispatch (once, outside loop) ─────────────────────
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Lgcm_dec_loop_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Lgcm_dec_loop_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Lgcm_dec_loop_256
    b           .Lgcm_dec_done

    # ── AES-128 decrypt self-contained loop ────────────────────────
.Lgcm_dec_loop_128:
___
$code .= emit_lsx2_counter_pair_and_advance();
$code .= emit_init_gcm();
$code .= emit_steady_state(9);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_and_seed_decrypt();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_dec_loop_128
    b           .Lgcm_dec_drain

    # ── AES-192 decrypt self-contained loop ────────────────────────
.Lgcm_dec_loop_192:
___
$code .= emit_lsx2_counter_pair_and_advance();
$code .= emit_init_gcm();
$code .= emit_steady_state(11);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_and_seed_decrypt();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_dec_loop_192
    b           .Lgcm_dec_drain

    # ── AES-256 decrypt self-contained loop ────────────────────────
.Lgcm_dec_loop_256:
___
$code .= emit_lsx2_counter_pair_and_advance();
$code .= emit_init_gcm();
$code .= emit_steady_state(13);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_and_seed_decrypt();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_dec_loop_256
    b           .Lgcm_dec_drain

    # ─── drain: finish last GHASH (non-interleaved) ─────────────────
.Lgcm_dec_drain:
    .rept 7
    GHASH8B_STEP2_LO
    .endr
    .rept 7
    GHASH8B_STEP2_HI
    .endr
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_writeback_xi();
$code .= <<'___';
    # Write counter back to ivec.
    ld.w    $r16,$sp,144
    revb.2w $r16,$r16
    xvinsgr2vr.w $xr8,$r16,3
    ld.d    $r16,$sp,136
    vst     $vr8,$r16,0

.Lgcm_dec_done:
    ld.d    $a0,$sp,152         # return aligned_len

.Lgcm_dec_epilogue:
    ld.d    $ra,$sp,0
    ld.d    $fp,$sp,8
    ld.d    $s0,$sp,16
    ld.d    $s1,$sp,24
    ld.d    $s2,$sp,32
    ld.d    $s3,$sp,40
    ld.d    $s4,$sp,48
    ld.d    $s5,$sp,56
    ld.d    $s6,$sp,64
    ld.d    $s7,$sp,72
    ld.d    $s8,$sp,80
    addi.d  $sp,$sp,192
    jirl    $zero,$ra,0

.Lgcm_dec_ret0:
    move    $a0,$zero
    jirl    $zero,$ra,0
.cfi_endproc
.size   loongarch64_vpaes_gcm_decrypt,.-loongarch64_vpaes_gcm_decrypt

___

# ═══════════════════════════════════════════════════════════════════
#  LASX ENCRYPT function
# ═══════════════════════════════════════════════════════════════════

$code .= <<'___';
.globl  loongarch64_vpaes_lasx_gcm_encrypt
.type   loongarch64_vpaes_lasx_gcm_encrypt,@function
.align  4
loongarch64_vpaes_lasx_gcm_encrypt:
.cfi_startproc
    beqz    $a2,.Lgcm_lasx_enc_ret0

    addi.d  $sp,$sp,-192
    st.d    $ra,$sp,0
    st.d    $fp,$sp,8
    st.d    $s0,$sp,16
    st.d    $s1,$sp,24
    st.d    $s2,$sp,32
    st.d    $s3,$sp,40
    st.d    $s4,$sp,48
    st.d    $s5,$sp,56
    st.d    $s6,$sp,64
    st.d    $s7,$sp,72
    st.d    $s8,$sp,80

    ori     $fp,$a5,0
    ori     $s1,$a3,0
    ori     $s0,$a2,0
    bstrins.d $s0,$zero,4,0
    beqz    $s0,.Lgcm_lasx_enc_done

    st.d    $a0,$sp,112
    st.d    $a1,$sp,120
    st.d    $a4,$sp,136
    st.d    $s0,$sp,152

    la.local $s2,.Lrem_8bit_shl48
    addi.d  $s3,$fp,288         # cached H 8-bit table
    lu12i.w $r16,1
    add.d   $s6,$s3,$r16        # cached H^2 8-bit table

    # Load counter, save counter to stack.
    ld.d    $r16,$sp,136
    vld     $vr8,$r16,0
    xvpermi.q $xr8,$xr8,0x00
    ld.w    $r16,$r16,12
    revb.2w $r16,$r16
    st.w    $r16,$sp,144

    # LASX preheat (constants + Lk_ipt/Lk_sbo + MC tables).
    bl      _vpaes_lasx_preheat_gcm

    # Load Xi state.
    ld.d    $r4,$fp,0
    ld.d    $r5,$fp,8

    # ─── LASX warmup: encrypt pair 0 (no GHASH) ──────────────────
___
$code .= emit_lasx_counter_pair();
$code .= emit_init_gcm_lasx();

# Preload SR table per key size into xvr25
$code .= <<'___';
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Llasx_enc_warm_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Llasx_enc_warm_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Llasx_enc_warm_256
    b           .Lgcm_lasx_enc_done
.Llasx_enc_warm_128:
___
$code .= emit_lasx_sr_preload(9);
$code .= emit_warmup_state_lasx(9);
$code .= <<'___';
    b           .Llasx_enc_warm_after
.Llasx_enc_warm_192:
___
$code .= emit_lasx_sr_preload(11);
$code .= emit_warmup_state_lasx(11);
$code .= <<'___';
    b           .Llasx_enc_warm_after
.Llasx_enc_warm_256:
___
$code .= emit_lasx_sr_preload(13);
$code .= emit_warmup_state_lasx(13);
$code .= <<'___';
.Llasx_enc_warm_after:
___
$code .= emit_xor_store_from_stack_lasx();
$code .= emit_seed_ghash_from_cipher_pair_lasx();
$code .= <<'___';
    GHASH8B_INIT2
___
$code .= emit_advance_counter_pair();
$code .= <<'___';
    addi.d      $s0,$s0,-32
    beqz        $s0,.Lgcm_lasx_enc_drain

    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Lgcm_lasx_enc_loop_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Lgcm_lasx_enc_loop_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Lgcm_lasx_enc_loop_256
    b           .Lgcm_lasx_enc_done

.Lgcm_lasx_enc_loop_128:
___
$code .= emit_lasx_counter_pair_and_advance();
$code .= emit_init_gcm_lasx();
$code .= emit_steady_state_lasx(9);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_from_stack_lasx();
$code .= emit_seed_ghash_from_cipher_pair_lasx();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_lasx_enc_loop_128
    b           .Lgcm_lasx_enc_drain

.Lgcm_lasx_enc_loop_192:
___
$code .= emit_lasx_counter_pair_and_advance();
$code .= emit_init_gcm_lasx();
$code .= emit_steady_state_lasx(11);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_from_stack_lasx();
$code .= emit_seed_ghash_from_cipher_pair_lasx();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_lasx_enc_loop_192
    b           .Lgcm_lasx_enc_drain

.Lgcm_lasx_enc_loop_256:
___
$code .= emit_lasx_counter_pair_and_advance();
$code .= emit_init_gcm_lasx();
$code .= emit_steady_state_lasx(13);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_from_stack_lasx();
$code .= emit_seed_ghash_from_cipher_pair_lasx();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_lasx_enc_loop_256
    b           .Lgcm_lasx_enc_drain

.Lgcm_lasx_enc_drain:
    .rept 7
    GHASH8B_STEP2_LO
    .endr
    .rept 7
    GHASH8B_STEP2_HI
    .endr
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_writeback_xi();
$code .= <<'___';
    ld.w    $r16,$sp,144
    revb.2w $r16,$r16
    xvinsgr2vr.w $xr8,$r16,3
    ld.d    $r16,$sp,136
    vst     $vr8,$r16,0

.Lgcm_lasx_enc_done:
    ld.d    $a0,$sp,152

    ld.d    $ra,$sp,0
    ld.d    $fp,$sp,8
    ld.d    $s0,$sp,16
    ld.d    $s1,$sp,24
    ld.d    $s2,$sp,32
    ld.d    $s3,$sp,40
    ld.d    $s4,$sp,48
    ld.d    $s5,$sp,56
    ld.d    $s6,$sp,64
    ld.d    $s7,$sp,72
    ld.d    $s8,$sp,80
    addi.d  $sp,$sp,192
    jirl    $zero,$ra,0

.Lgcm_lasx_enc_ret0:
    move    $a0,$zero
    jirl    $zero,$ra,0
.cfi_endproc
.size   loongarch64_vpaes_lasx_gcm_encrypt,.-loongarch64_vpaes_lasx_gcm_encrypt

___

# ═══════════════════════════════════════════════════════════════════
#  LASX DECRYPT function
# ═══════════════════════════════════════════════════════════════════

$code .= <<'___';
.globl  loongarch64_vpaes_lasx_gcm_decrypt
.type   loongarch64_vpaes_lasx_gcm_decrypt,@function
.align  4
loongarch64_vpaes_lasx_gcm_decrypt:
.cfi_startproc
    beqz    $a2,.Lgcm_lasx_dec_ret0

    addi.d  $sp,$sp,-192
    st.d    $ra,$sp,0
    st.d    $fp,$sp,8
    st.d    $s0,$sp,16
    st.d    $s1,$sp,24
    st.d    $s2,$sp,32
    st.d    $s3,$sp,40
    st.d    $s4,$sp,48
    st.d    $s5,$sp,56
    st.d    $s6,$sp,64
    st.d    $s7,$sp,72
    st.d    $s8,$sp,80

    ori     $fp,$a5,0
    ori     $s1,$a3,0
    ori     $s0,$a2,0
    bstrins.d $s0,$zero,4,0
    beqz    $s0,.Lgcm_lasx_dec_done

    st.d    $a0,$sp,112
    st.d    $a1,$sp,120
    st.d    $a4,$sp,136
    st.d    $s0,$sp,152

    la.local $s2,.Lrem_8bit_shl48
    addi.d  $s3,$fp,288         # cached H 8-bit table
    lu12i.w $r16,1
    add.d   $s6,$s3,$r16        # cached H^2 8-bit table

    # Load counter, save counter to stack.
    ld.d    $r16,$sp,136
    vld     $vr8,$r16,0
    xvpermi.q $xr8,$xr8,0x00
    ld.w    $r16,$r16,12
    revb.2w $r16,$r16
    st.w    $r16,$sp,144

    # LASX preheat.
    bl      _vpaes_lasx_preheat_gcm

    ld.d    $r4,$fp,0
    ld.d    $r5,$fp,8

    # ─── LASX warmup: decrypt pair 0 (no GHASH) ──────────────────
___
$code .= emit_lasx_counter_pair();
$code .= emit_init_gcm_lasx();

$code .= <<'___';
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Llasx_dec_warm_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Llasx_dec_warm_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Llasx_dec_warm_256
    b           .Lgcm_lasx_dec_done
.Llasx_dec_warm_128:
___
$code .= emit_lasx_sr_preload(9);
$code .= emit_warmup_state_lasx(9);
$code .= <<'___';
    b           .Llasx_dec_warm_after
.Llasx_dec_warm_192:
___
$code .= emit_lasx_sr_preload(11);
$code .= emit_warmup_state_lasx(11);
$code .= <<'___';
    b           .Llasx_dec_warm_after
.Llasx_dec_warm_256:
___
$code .= emit_lasx_sr_preload(13);
$code .= emit_warmup_state_lasx(13);
$code .= <<'___';
.Llasx_dec_warm_after:
___
$code .= emit_xor_store_and_seed_decrypt_lasx();
$code .= <<'___';
    GHASH8B_INIT2
___
$code .= emit_advance_counter_pair();
$code .= <<'___';
    addi.d      $s0,$s0,-32
    beqz        $s0,.Lgcm_lasx_dec_drain

    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Lgcm_lasx_dec_loop_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Lgcm_lasx_dec_loop_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Lgcm_lasx_dec_loop_256
    b           .Lgcm_lasx_dec_done

.Lgcm_lasx_dec_loop_128:
___
$code .= emit_lasx_counter_pair_and_advance();
$code .= emit_init_gcm_lasx();
$code .= emit_steady_state_lasx(9);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_and_seed_decrypt_lasx();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_lasx_dec_loop_128
    b           .Lgcm_lasx_dec_drain

.Lgcm_lasx_dec_loop_192:
___
$code .= emit_lasx_counter_pair_and_advance();
$code .= emit_init_gcm_lasx();
$code .= emit_steady_state_lasx(11);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_and_seed_decrypt_lasx();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_lasx_dec_loop_192
    b           .Lgcm_lasx_dec_drain

.Lgcm_lasx_dec_loop_256:
___
$code .= emit_lasx_counter_pair_and_advance();
$code .= emit_init_gcm_lasx();
$code .= emit_steady_state_lasx(13);
$code .= <<'___';
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_xor_store_and_seed_decrypt_lasx();
$code .= <<'___';
    GHASH8B_INIT2
    addi.d      $s0,$s0,-32
    bnez        $s0,.Lgcm_lasx_dec_loop_256
    b           .Lgcm_lasx_dec_drain

.Lgcm_lasx_dec_drain:
    .rept 7
    GHASH8B_STEP2_LO
    .endr
    .rept 7
    GHASH8B_STEP2_HI
    .endr
    GHASH8B_FINAL2
___
$code .= emit_ghash_combine_xi();
$code .= emit_writeback_xi();
$code .= <<'___';
    ld.w    $r16,$sp,144
    revb.2w $r16,$r16
    xvinsgr2vr.w $xr8,$r16,3
    ld.d    $r16,$sp,136
    vst     $vr8,$r16,0

.Lgcm_lasx_dec_done:
    ld.d    $a0,$sp,152

    ld.d    $ra,$sp,0
    ld.d    $fp,$sp,8
    ld.d    $s0,$sp,16
    ld.d    $s1,$sp,24
    ld.d    $s2,$sp,32
    ld.d    $s3,$sp,40
    ld.d    $s4,$sp,48
    ld.d    $s5,$sp,56
    ld.d    $s6,$sp,64
    ld.d    $s7,$sp,72
    ld.d    $s8,$sp,80
    addi.d  $sp,$sp,192
    jirl    $zero,$ra,0

.Lgcm_lasx_dec_ret0:
    move    $a0,$zero
    jirl    $zero,$ra,0
.cfi_endproc
.size   loongarch64_vpaes_lasx_gcm_decrypt,.-loongarch64_vpaes_lasx_gcm_decrypt

___

print $code;
close STDOUT or die "error closing STDOUT: $!";
