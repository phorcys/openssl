#! /usr/bin/env perl
# Copyright 2025 The OpenSSL Project Authors. All Rights Reserved.
#
# Licensed under the Apache License 2.0 (the "License").  You may not use
# this file except in compliance with the License.  You can obtain a copy
# in the file LICENSE in the source distribution or at
# https://www.openssl.org/source/license.html

# LoongArch64 GHASH
#
# gcm_gmult_4bit:
#   scalar 4-bit table multiply.
#
# gcm_ghash_4bit:
#   528B-style GHASH.
#   - Main path: 2-way aggregated GHASH with explicit PRE/POST interleaving.
#   - Tail path: retained 1x 528B path for the final block / reference path.

my $output;
$output = $#ARGV >= 0 && $ARGV[$#ARGV] =~ m|\.\w+$| ? pop : undef;
open STDOUT, ">$output";

sub emit_lines {
    my ($line, $count) = @_;
    return join('', map { "    $line\n" } 1 .. $count);
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

# Generic 528B byte-step helpers.
# Register convention for generic macros:
#   ZHI/ZLO : current hash state
#   SRC     : current 64-bit source half being consumed byte-by-byte
#   CUR     : current high nibble (0..15)
#   TRED    : reduction temporary
#   THI/TLO : loaded table values / temporaries
#   TSHIFT  : common shift temporary
#   TPTR    : common address temporary

.macro GHASH528_INIT TAB SRCLO CUR ZHI ZLO TBYTE TPTR
    andi    \TBYTE, \SRCLO, 0xff
    andi    \TPTR,  \TBYTE, 0x0f
    srli.d  \CUR,   \TBYTE, 4
    alsl.d  \TPTR,  \TPTR, \TAB, 4
    ld.d    \ZHI,   \TPTR, 0
    ld.d    \ZLO,   \TPTR, 8
    srli.d  \SRCLO, \SRCLO, 8
.endm

.macro GHASH528_PRE SHL SHR CUR ZHI ZLO TRED THI TLO
    ldx.bu  \TLO,  \SHL, \CUR
    andi    \TRED, \ZLO, 0xff
    xor     \TRED, \TRED, \TLO
    alsl.d  \TRED, \TRED, $s2, 1
    ld.hu   \TRED, \TRED, 0
    slli.d  \TRED, \TRED, 48
    alsl.d  \THI,  \CUR,  \SHR, 4
    ld.d    \TLO,  \THI,  8
    ld.d    \THI,  \THI,  0
.endm

.macro GHASH528_POST TAB SRC CUR ZHI ZLO TRED THI TLO TSHIFT TPTR
    slli.d  \TSHIFT, \ZHI, 56
    srli.d  \ZHI,    \ZHI, 8
    srli.d  \ZLO,    \ZLO, 8
    or      \ZLO,    \ZLO, \TSHIFT
    xor     \ZHI,    \ZHI, \TRED
    xor     \ZHI,    \ZHI, \THI
    xor     \ZLO,    \ZLO, \TLO

    andi    \TRED,   \SRC, 0xff
    andi    \TPTR,   \TRED, 0x0f
    srli.d  \CUR,    \TRED, 4
    alsl.d  \TPTR,   \TPTR, \TAB, 4
    ld.d    \THI,    \TPTR, 0
    ld.d    \TLO,    \TPTR, 8
    xor     \ZHI,    \ZHI, \THI
    xor     \ZLO,    \ZLO, \TLO
    srli.d  \SRC,    \SRC, 8
.endm

.macro GHASH528_FINAL TAB CUR ZHI ZLO TRED THI TLO TSHIFT TPTR
    andi    \TRED,   \ZLO, 0xff
    slli.d  \TRED,   \TRED, 4
    andi    \TRED,   \TRED, 0xff
    alsl.d  \TRED,   \TRED, $s2, 1
    ld.hu   \TRED,   \TRED, 0
    slli.d  \TRED,   \TRED, 48
    slli.d  \TSHIFT, \ZHI, 60
    srli.d  \ZHI,    \ZHI, 4
    srli.d  \ZLO,    \ZLO, 4
    or      \ZLO,    \ZLO, \TSHIFT
    alsl.d  \TPTR,   \CUR, \TAB, 4
    ld.d    \THI,    \TPTR, 0
    ld.d    \TLO,    \TPTR, 8
    xor     \ZHI,    \ZHI, \TRED
    xor     \ZHI,    \ZHI, \THI
    xor     \ZLO,    \ZLO, \TLO
.endm

# Single-stream fixed register layout.
#   src_hi/src_lo : r6 / r7
#   z_hi/z_lo     : r8 / r9
#   cur           : r10
#   temps         : r16 / r17 / r18
#   common temps  : r4 / r5

.macro GHASH528_INIT1 TAB
    GHASH528_INIT \TAB, $r7,  $r10, $r8,  $r9,  $r16, $r17
.endm

.macro GHASH528_PRE1 SHL SHR
    GHASH528_PRE  \SHL, \SHR, $r10, $r8,  $r9,  $r16, $r17, $r18
.endm

.macro GHASH528_POST1 TAB SRC
    GHASH528_POST \TAB, \SRC, $r10, $r8,  $r9,  $r16, $r17, $r18, $r4, $r5
.endm

.macro GHASH528_FINAL1 TAB
    GHASH528_FINAL \TAB, $r10, $r8,  $r9,  $r16, $r17, $r18, $r4, $r5
.endm

# Two-stream fixed register layout.
# Stream A:
#   src_hi/src_lo : r6 / r7
#   z_hi/z_lo     : r8 / r9
#   cur           : r10
# Stream B:
#   src_hi/src_lo : r11 / r12
#   z_hi/z_lo     : r13 / r14
#   cur           : r15
# Temp sets:
#   stream A      : r16 / r17 / r18
#   stream B      : r19 / r20 / r21
# Common temps:
#   r4 / r5

.macro GHASH528_INIT2
    GHASH528_INIT $s6, $r7,  $r10, $r8,  $r9,  $r16, $r17
    GHASH528_INIT $s3, $r12, $r15, $r13, $r14, $r19, $r20
.endm

.macro GHASH528_PRE2
    GHASH528_PRE  $s7, $s8, $r10, $r8,  $r9,  $r16, $r17, $r18
    GHASH528_PRE  $s4, $s5, $r15, $r13, $r14, $r19, $r20, $r21
.endm

.macro GHASH528_POST2_LO
    GHASH528_POST $s6, $r7,  $r10, $r8,  $r9,  $r16, $r17, $r18, $r4, $r5
    GHASH528_POST $s3, $r12, $r15, $r13, $r14, $r19, $r20, $r21, $r4, $r5
.endm

.macro GHASH528_POST2_HI
    GHASH528_POST $s6, $r6,  $r10, $r8,  $r9,  $r16, $r17, $r18, $r4, $r5
    GHASH528_POST $s3, $r11, $r15, $r13, $r14, $r19, $r20, $r21, $r4, $r5
.endm

.macro GHASH528_FINAL2
    GHASH528_FINAL $s6, $r10, $r8,  $r9,  $r16, $r17, $r18, $r4, $r5
    GHASH528_FINAL $s3, $r15, $r13, $r14, $r19, $r20, $r21, $r4, $r5
.endm

.section .rodata
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

.text

##
## void gcm_gmult_4bit(u64 Xi[2], const u128 Htable[16])
##
.globl gcm_gmult_4bit
.type gcm_gmult_4bit,@function
.align 4
gcm_gmult_4bit:
.cfi_startproc
    addi.d  $sp,$sp,-16
    st.d    $r25,$sp,8
    st.d    $ra,$sp,0

    la.local $r25,.Lrem_4bit

    ld.d    $r6,$r4,0
    ld.d    $r7,$r4,8
    revb.d  $r6,$r6
    revb.d  $r7,$r7

    andi    $r14,$r7,0x0f
    andi    $r15,$r7,0xf0
    slli.d  $r14,$r14,4
    add.d   $r14,$r14,$r5
    ld.d    $r12,$r14,0
    ld.d    $r13,$r14,8

    add.d   $r15,$r15,$r5
    ld.d    $r17,$r15,0
    ld.d    $r18,$r15,8

    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$r25
    ld.d    $r16,$r16,0
    slli.d  $r19,$r12,60
    srli.d  $r13,$r13,4
    or      $r13,$r13,$r19
    srli.d  $r12,$r12,4
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    srli.d  $r7,$r7,8

    addi.d  $r20,$r0,7
.Lgm_lo:
    andi    $r14,$r7,0x0f
    andi    $r15,$r7,0xf0
    slli.d  $r14,$r14,4
    add.d   $r14,$r14,$r5
    add.d   $r15,$r15,$r5
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$r25
    slli.d  $r19,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r19
    srli.d  $r12,$r12,4
    ld.d    $r17,$r14,0
    ld.d    $r18,$r14,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$r25
    slli.d  $r19,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r19
    srli.d  $r12,$r12,4
    ld.d    $r17,$r15,0
    ld.d    $r18,$r15,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    srli.d  $r7,$r7,8
    addi.d  $r20,$r20,-1
    bnez    $r20,.Lgm_lo

    or      $r7,$r6,$r0
    addi.d  $r20,$r0,8
.Lgm_hi:
    andi    $r14,$r7,0x0f
    andi    $r15,$r7,0xf0
    slli.d  $r14,$r14,4
    add.d   $r14,$r14,$r5
    add.d   $r15,$r15,$r5
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$r25
    slli.d  $r19,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r19
    srli.d  $r12,$r12,4
    ld.d    $r17,$r14,0
    ld.d    $r18,$r14,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$r25
    slli.d  $r19,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r19
    srli.d  $r12,$r12,4
    ld.d    $r17,$r15,0
    ld.d    $r18,$r15,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    srli.d  $r7,$r7,8
    addi.d  $r20,$r20,-1
    bnez    $r20,.Lgm_hi

    revb.d  $r12,$r12
    revb.d  $r13,$r13
    st.d    $r12,$r4,0
    st.d    $r13,$r4,8

    ld.d    $r25,$sp,8
    ld.d    $ra,$sp,0
    addi.d  $sp,$sp,16
    jirl    $r0,$r1,0
.cfi_endproc
.size gcm_gmult_4bit,.-gcm_gmult_4bit

##
## void gcm_ghash_4bit(u64 Xi[2], const u128 Htable[16],
##                     const u8 *inp, size_t len)
##
.globl gcm_ghash_4bit
.type gcm_ghash_4bit,@function
.align 4
gcm_ghash_4bit:
.cfi_startproc
    addi.d  $sp,$sp,-912
    st.d    $ra,$sp,904
    st.d    $fp,$sp,896
    st.d    $s0,$sp,888
    st.d    $s1,$sp,880
    st.d    $s2,$sp,872
    st.d    $s3,$sp,864
    st.d    $s4,$sp,856
    st.d    $s5,$sp,848
    st.d    $s6,$sp,840
    st.d    $s7,$sp,832
    st.d    $s8,$sp,824

    la.local $s2,.Lrem_8bit
    ori     $fp,$r4,0           # Xi*
    ori     $s0,$r6,0           # inp
    ori     $s1,$r7,0           # len
    ori     $s3,$r5,0           # H 4-bit table
    ori     $s4,$sp,0           # H shl4 bytes
    addi.d  $s5,$sp,16          # H shr4 table
    addi.d  $s6,$sp,272         # H^2 4-bit table
    addi.d  $s7,$sp,528         # H^2 shl4 bytes
    addi.d  $s8,$sp,544         # H^2 shr4 table

    # Build H 528B helpers.
    ori     $r14,$s3,0
    ori     $r15,$s5,0
    ori     $r16,$s4,0
    li.d    $r20,16
.Lprep_h_528:
    ld.d    $r17,$r14,0
    ld.d    $r18,$r14,8
    andi    $r19,$r18,0x0f
    slli.d  $r19,$r19,4
    st.b    $r19,$r16,0
    slli.d  $r21,$r17,60
    srli.d  $r18,$r18,4
    or      $r18,$r18,$r21
    srli.d  $r17,$r17,4
    st.d    $r17,$r15,0
    st.d    $r18,$r15,8
    addi.d  $r14,$r14,16
    addi.d  $r15,$r15,16
    addi.d  $r16,$r16,1
    addi.d  $r20,$r20,-1
    bnez    $r20,.Lprep_h_528

    # Compute raw H^2 into sp+800, then build its 4-bit table at s6.
    # gcm_gmult_4bit expects Xi in the byte-reversed form relative to ctx->H.u,
    # so H needs revb before and after the helper call.
    ld.d    $r14,$s3,128
    ld.d    $r15,$s3,136
    revb.d  $r14,$r14
    revb.d  $r15,$r15
    st.d    $r14,$sp,800
    st.d    $r15,$sp,808
    addi.d  $r4,$sp,800
    ori     $r5,$s3,0
    bl      gcm_gmult_4bit

    st.d    $r0,$s6,0
    st.d    $r0,$s6,8
    ld.d    $r12,$sp,800
    ld.d    $r13,$sp,808
    revb.d  $r12,$r12
    revb.d  $r13,$r13
    st.d    $r12,$s6,128
    st.d    $r13,$s6,136
    li.d    $r21,0xe100000000000000
    REDUCE1BIT $r12,$r13,$r14,$r15,$r21
    st.d    $r12,$s6,64
    st.d    $r13,$s6,72
    REDUCE1BIT $r12,$r13,$r14,$r15,$r21
    st.d    $r12,$s6,32
    st.d    $r13,$s6,40
    REDUCE1BIT $r12,$r13,$r14,$r15,$r21
    st.d    $r12,$s6,16
    st.d    $r13,$s6,24

    ld.d    $r14,$s6,32
    ld.d    $r15,$s6,40
    xor     $r14,$r12,$r14
    xor     $r15,$r13,$r15
    st.d    $r14,$s6,48
    st.d    $r15,$s6,56

    ld.d    $r12,$s6,64
    ld.d    $r13,$s6,72
    ld.d    $r14,$s6,16
    ld.d    $r15,$s6,24
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,80
    st.d    $r17,$s6,88
    ld.d    $r14,$s6,32
    ld.d    $r15,$s6,40
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,96
    st.d    $r17,$s6,104
    ld.d    $r14,$s6,48
    ld.d    $r15,$s6,56
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,112
    st.d    $r17,$s6,120

    ld.d    $r12,$s6,128
    ld.d    $r13,$s6,136
    ld.d    $r14,$s6,16
    ld.d    $r15,$s6,24
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,144
    st.d    $r17,$s6,152
    ld.d    $r14,$s6,32
    ld.d    $r15,$s6,40
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,160
    st.d    $r17,$s6,168
    ld.d    $r14,$s6,48
    ld.d    $r15,$s6,56
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,176
    st.d    $r17,$s6,184
    ld.d    $r14,$s6,64
    ld.d    $r15,$s6,72
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,192
    st.d    $r17,$s6,200
    ld.d    $r14,$s6,80
    ld.d    $r15,$s6,88
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,208
    st.d    $r17,$s6,216
    ld.d    $r14,$s6,96
    ld.d    $r15,$s6,104
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,224
    st.d    $r17,$s6,232
    ld.d    $r14,$s6,112
    ld.d    $r15,$s6,120
    xor     $r16,$r12,$r14
    xor     $r17,$r13,$r15
    st.d    $r16,$s6,240
    st.d    $r17,$s6,248

    # Build H^2 528B helpers.
    ori     $r14,$s6,0
    ori     $r15,$s8,0
    ori     $r16,$s7,0
    li.d    $r20,16
.Lprep_h2_528:
    ld.d    $r17,$r14,0
    ld.d    $r18,$r14,8
    andi    $r19,$r18,0x0f
    slli.d  $r19,$r19,4
    st.b    $r19,$r16,0
    slli.d  $r21,$r17,60
    srli.d  $r18,$r18,4
    or      $r18,$r18,$r21
    srli.d  $r17,$r17,4
    st.d    $r17,$r15,0
    st.d    $r18,$r15,8
    addi.d  $r14,$r14,16
    addi.d  $r15,$r15,16
    addi.d  $r16,$r16,1
    addi.d  $r20,$r20,-1
    bnez    $r20,.Lprep_h2_528

    # Current Xi in big-endian memory order lives in r4:r5.
    ld.d    $r4,$fp,0
    ld.d    $r5,$fp,8

.Lghash_pair:
    addi.d  $r16,$s1,-32
    blt     $r16,$r0,.Lghash_tail

    # r4:r5 = Xi xor I0, r11:r12 = I1, all in big-endian memory order.
    ld.d    $r16,$s0,0
    xor     $r4,$r4,$r16
    ld.d    $r16,$s0,8
    xor     $r5,$r5,$r16
    ld.d    $r11,$s0,16
    ld.d    $r12,$s0,24
    addi.d  $s0,$s0,32
    addi.d  $s1,$s1,-32

    revb.d  $r6,$r4
    revb.d  $r7,$r5
    revb.d  $r11,$r11
    revb.d  $r12,$r12

    GHASH528_INIT2
___

$code .= emit_lines("GHASH528_PRE2\n    GHASH528_POST2_LO", 7);
$code .= emit_lines("GHASH528_PRE2\n    GHASH528_POST2_HI", 8);

$code .= <<'___';
    GHASH528_FINAL2

    revb.d  $r8,$r8
    revb.d  $r9,$r9
    revb.d  $r13,$r13
    revb.d  $r14,$r14
    xor     $r4,$r8,$r13
    xor     $r5,$r9,$r14
    b       .Lghash_pair

.Lghash_tail:
    beqz    $s1,.Lghash_done

    ld.d    $r16,$s0,0
    xor     $r4,$r4,$r16
    ld.d    $r16,$s0,8
    xor     $r5,$r5,$r16

    revb.d  $r6,$r4
    revb.d  $r7,$r5
    GHASH528_INIT1 $s3
___

$code .= emit_lines("GHASH528_PRE1 \$s4, \$s5\n    GHASH528_POST1 \$s3, \$r7", 7);
$code .= emit_lines("GHASH528_PRE1 \$s4, \$s5\n    GHASH528_POST1 \$s3, \$r6", 8);

$code .= <<'___';
    GHASH528_FINAL1 $s3
    revb.d  $r4,$r8
    revb.d  $r5,$r9

.Lghash_done:
    st.d    $r4,$fp,0
    st.d    $r5,$fp,8

    ld.d    $ra,$sp,904
    ld.d    $fp,$sp,896
    ld.d    $s0,$sp,888
    ld.d    $s1,$sp,880
    ld.d    $s2,$sp,872
    ld.d    $s3,$sp,864
    ld.d    $s4,$sp,856
    ld.d    $s5,$sp,848
    ld.d    $s6,$sp,840
    ld.d    $s7,$sp,832
    ld.d    $s8,$sp,824
    addi.d  $sp,$sp,912
    jirl    $r0,$r1,0
.cfi_endproc
.size gcm_ghash_4bit,.-gcm_ghash_4bit
___

print $code;
close STDOUT or die "error closing STDOUT: $!";
