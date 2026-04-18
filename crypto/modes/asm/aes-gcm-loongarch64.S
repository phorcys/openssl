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

.globl  loongarch64_vpaes_gcm_encrypt
.type   loongarch64_vpaes_gcm_encrypt,@function
.align  4
loongarch64_vpaes_gcm_encrypt:
.cfi_startproc
    beqz    $a2,.Lgcm_enc_ret0

    addi.d  $sp,$sp,-960
    st.d    $ra,$sp,952
    st.d    $fp,$sp,944
    st.d    $s0,$sp,936
    st.d    $s1,$sp,928
    st.d    $s2,$sp,920
    st.d    $s3,$sp,912
    st.d    $s4,$sp,904
    st.d    $s5,$sp,896
    st.d    $s6,$sp,888
    st.d    $s7,$sp,880
    st.d    $s8,$sp,872

    ori     $fp,$a5,0           # Xi*
    ori     $s1,$a3,0           # AES key schedule
    # aligned_len = len & -32
    ori     $s0,$a2,0
    bstrins.d $s0,$zero,4,0
    beqz    $s0,.Lgcm_enc_done

    # Save inp / out / ivec to stack (GPRs will be reused for GHASH)
    st.d    $a0,$sp,816
    st.d    $a1,$sp,824
    st.d    $a4,$sp,840

    ori     $t3,$s0,0           # remaining aligned bytes

    la.local $s2,.Lrem_8bit
    addi.d  $s3,$fp,32          # Htable base
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

    # Compute raw H^2 into sp+800 using the local 4-bit multiply sequence.
    la.local $t7,.Lrem_4bit
    ld.d    $r6,$sp,800
    ld.d    $r7,$sp,808
    revb.d  $r6,$r6
    revb.d  $r7,$r7

    andi    $r14,$r7,0x0f
    andi    $r15,$r7,0xf0
    slli.d  $r14,$r14,4
    add.d   $r14,$r14,$s3
    ld.d    $r12,$r14,0
    ld.d    $r13,$r14,8

    add.d   $r15,$r15,$s3
    ld.d    $r17,$r15,0
    ld.d    $r18,$r15,8

    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$t7
    ld.d    $r16,$r16,0
    slli.d  $r21,$r12,60
    srli.d  $r13,$r13,4
    or      $r13,$r13,$r21
    srli.d  $r12,$r12,4
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    srli.d  $r7,$r7,8

    addi.d  $r20,$zero,7
.Lgcm_h2_lo:
    andi    $r14,$r7,0x0f
    andi    $r15,$r7,0xf0
    slli.d  $r14,$r14,4
    add.d   $r14,$r14,$s3
    add.d   $r15,$r15,$s3
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$t7
    slli.d  $r21,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r21
    srli.d  $r12,$r12,4
    ld.d    $r17,$r14,0
    ld.d    $r18,$r14,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$t7
    slli.d  $r21,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r21
    srli.d  $r12,$r12,4
    ld.d    $r17,$r15,0
    ld.d    $r18,$r15,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    srli.d  $r7,$r7,8
    addi.d  $r20,$r20,-1
    bnez    $r20,.Lgcm_h2_lo

    or      $r7,$r6,$zero
    addi.d  $r20,$zero,8
.Lgcm_h2_hi:
    andi    $r14,$r7,0x0f
    andi    $r15,$r7,0xf0
    slli.d  $r14,$r14,4
    add.d   $r14,$r14,$s3
    add.d   $r15,$r15,$s3
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$t7
    slli.d  $r21,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r21
    srli.d  $r12,$r12,4
    ld.d    $r17,$r14,0
    ld.d    $r18,$r14,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    andi    $r16,$r13,0x0f
    slli.d  $r16,$r16,3
    add.d   $r16,$r16,$t7
    slli.d  $r21,$r12,60
    srli.d  $r13,$r13,4
    ld.d    $r16,$r16,0
    or      $r13,$r13,$r21
    srli.d  $r12,$r12,4
    ld.d    $r17,$r15,0
    ld.d    $r18,$r15,8
    xor     $r12,$r12,$r16
    xor     $r12,$r12,$r17
    xor     $r13,$r13,$r18
    srli.d  $r7,$r7,8
    addi.d  $r20,$r20,-1
    bnez    $r20,.Lgcm_h2_hi

    revb.d  $r12,$r12
    revb.d  $r13,$r13
    st.d    $r12,$sp,800
    st.d    $r13,$sp,808

    # Expand raw H^2 into the 16-entry 4-bit table layout.
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

    # Load Xi state and counter, save counter to stack.
    ld.d    $r4,$fp,0
    ld.d    $r5,$fp,8
    ld.d    $r16,$sp,840
    vld     $vr8,$r16,0
    ld.w    $r16,$r16,12
    revb.2w $r16,$r16
    st.w    $r16,$sp,848

    # Preheat VPAES constants.
    ori     $a2,$s1,0
    bl      _vpaes_preheat

    # Save MC table base for unrolled steady state.
    la.local $r16,Lk_mc_backward
    st.d    $r16,$sp,832

    # ─── warmup: encrypt pair 0 (loop-based, no GHASH) ──────────────
    ld.w        $r16,$sp,848
    revb.2w     $r17,$r16
    vori.b      $vr0,$vr8,0
    vinsgr2vr.w $vr0,$r17,3
    addi.w      $r16,$r16,1
    revb.2w     $r16,$r16
    vori.b      $vr19,$vr8,0
    vinsgr2vr.w $vr19,$r16,3
    move      $a5,$s1
    li.d      $a7,0x10
    ld.w      $t5,$s1,240
    la.local  $t0,Lk_ipt
    vld       $vr25,$t0,0
    vld       $vr26,$t0,16
    vld       $vr5,$a5,0
    vori.b    $vr1,$vr9,0
    vori.b    $vr20,$vr9,0
    vandn.v   $vr1,$vr1,$vr0
    vandn.v   $vr20,$vr20,$vr19
    vsrli.w   $vr1,$vr1,4
    vsrli.w   $vr20,$vr20,4
    vand.v    $vr0,$vr0,$vr9
    vand.v    $vr19,$vr19,$vr9
    vshuf.b   $vr2,$vr18,$vr25,$vr0
    vshuf.b   $vr21,$vr18,$vr25,$vr19
    vshuf.b   $vr0,$vr18,$vr26,$vr1
    vshuf.b   $vr19,$vr18,$vr26,$vr20
    vxor.v    $vr2,$vr2,$vr5
    vxor.v    $vr21,$vr21,$vr5
    addi.d    $a5,$a5,16
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    la.local  $a6,Lk_mc_backward
    b         .Lwarm_entry

.Lwarm_loop:
    # SubBytes + MixColumns (standard VPAES x2 loop body)
    vld       $vr5,$a5,0
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    add.d     $t0,$a7,$a6
    vld       $vr1,$t0,-0x40
    vori.b    $vr5,$vr15,0
    vld       $vr4,$t0,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    addi.d    $a5,$a5,16
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    addi.d    $a7,$a7,16
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    andi      $a7,$a7,0x30
    addi.d    $t5,$t5,-1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22

.Lwarm_entry:
    # nibble split (top_a + top_b + top_c + entry tail)
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
    vld       $vr5,$a5,0
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    bnez      $t5,.Lwarm_loop

    # warmup last round (sbo SubBytes + ShiftRows, no MixColumns)
    vld       $vr25,$a6,-0x60
    vld       $vr26,$a6,-0x50
    vshuf.b   $vr4,$vr18,$vr25,$vr2
    vshuf.b   $vr23,$vr18,$vr25,$vr21
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vshuf.b   $vr0,$vr18,$vr26,$vr3
    vshuf.b   $vr19,$vr18,$vr26,$vr22
    add.d     $t0,$a7,$a6
    vld       $vr1,$t0,0x40
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1

    # ── warmup after-body: xor-store, seed GHASH, INIT2, advance ──
    ld.d        $r16,$sp,816
    ld.d        $r17,$sp,824
    vld         $vr6,$r16,0
    vld         $vr7,$r16,16
    vxor.v      $vr6,$vr6,$vr0
    vxor.v      $vr7,$vr7,$vr19
    vst         $vr6,$r17,0
    vst         $vr7,$r17,16
    addi.d      $r16,$r16,32
    addi.d      $r17,$r17,32
    st.d        $r16,$sp,816
    st.d        $r17,$sp,824
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
    GHASH528_INIT2
    ld.w        $r16,$sp,848
    addi.w      $r16,$r16,2
    st.w        $r16,$sp,848
    revb.2w     $r17,$r16
    vinsgr2vr.w $vr8,$r17,3
    addi.d      $t3,$t3,-32
    b           .Lgcm_drain      # DEBUG: always drain after warmup

    # ─── steady-state dispatcher ────────────────────────────────────
    ld.w        $r16,$sp,848
    revb.2w     $r17,$r16
    vori.b      $vr0,$vr8,0
    vinsgr2vr.w $vr0,$r17,3
    addi.w      $r16,$r16,1
    revb.2w     $r16,$r16
    vori.b      $vr19,$vr8,0
    vinsgr2vr.w $vr19,$r16,3
    la.local  $r16,Lk_ipt
    vld       $vr25,$r16,0
    vld       $vr26,$r16,16
    vld       $vr5,$s1,0
    vori.b    $vr1,$vr9,0
    vori.b    $vr20,$vr9,0
    vandn.v   $vr1,$vr1,$vr0
    vandn.v   $vr20,$vr20,$vr19
    vsrli.w   $vr1,$vr1,4
    vsrli.w   $vr20,$vr20,4
    vand.v    $vr0,$vr0,$vr9
    vand.v    $vr19,$vr19,$vr9
    vshuf.b   $vr2,$vr18,$vr25,$vr0
    vshuf.b   $vr21,$vr18,$vr25,$vr19
    vshuf.b   $vr0,$vr18,$vr26,$vr1
    vshuf.b   $vr19,$vr18,$vr26,$vr20
    vxor.v    $vr2,$vr2,$vr5
    vxor.v    $vr21,$vr21,$vr5
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21

.Lgcm_steady:
    ld.w        $r16,$s1,240
    ori         $r17,$zero,9
    beq         $r16,$r17,.Lgcm_steady_128
    ori         $r17,$zero,11
    beq         $r16,$r17,.Lgcm_steady_192
    ori         $r17,$zero,13
    beq         $r16,$r17,.Lgcm_steady_256
    b           .Lgcm_enc_done

    # ── AES-128 ────────────────────────────────────────────────────
.Lgcm_steady_128:
    # ── round 1  half-front (rk+16) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,16
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 1 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 1  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 2 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 2  half-front (rk+32) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,32
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 3 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 2  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 4 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 3  half-front (rk+48) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,48
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 5 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 3  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 6 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 4  half-front (rk+64) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,64
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 7 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 4  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 8 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 5  half-front (rk+80) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,80
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 9 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 5  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 10 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 6  half-front (rk+96) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,96
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 11 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 6  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 12 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 7  half-front (rk+112) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,112
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 13 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 7  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 14 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 8  half-front (rk+128) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,128
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 15 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 8  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 9  half-front (rk+144) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,144
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 9  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── final round (rk+160, sr_off=96) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,160
    la.local  $r16,Lk_sbo
    vld       $vr25,$r16,0
    vld       $vr26,$r16,16
    vshuf.b   $vr4,$vr18,$vr25,$vr2
    vshuf.b   $vr23,$vr18,$vr25,$vr21
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vshuf.b   $vr0,$vr18,$vr26,$vr3
    vshuf.b   $vr19,$vr18,$vr26,$vr22
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,96
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    b           .Lgcm_steady_after

    # ── AES-192 ────────────────────────────────────────────────────
.Lgcm_steady_192:
    # ── round 1  half-front (rk+16) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,16
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 1 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 1  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 2 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 2  half-front (rk+32) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,32
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 3 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 2  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 4 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 3  half-front (rk+48) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,48
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 5 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 3  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 6 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 4  half-front (rk+64) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,64
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 7 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 4  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 8 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 5  half-front (rk+80) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,80
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 9 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 5  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 10 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 6  half-front (rk+96) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,96
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 11 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 6  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 12 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 7  half-front (rk+112) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,112
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 13 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 7  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 14 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 8  half-front (rk+128) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,128
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 15 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 8  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 9  half-front (rk+144) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,144
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 9  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 10  half-front (rk+160) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,160
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 10  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 11  half-front (rk+176) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,176
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 11  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── final round (rk+192, sr_off=64) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,192
    la.local  $r16,Lk_sbo
    vld       $vr25,$r16,0
    vld       $vr26,$r16,16
    vshuf.b   $vr4,$vr18,$vr25,$vr2
    vshuf.b   $vr23,$vr18,$vr25,$vr21
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vshuf.b   $vr0,$vr18,$vr26,$vr3
    vshuf.b   $vr19,$vr18,$vr26,$vr22
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,64
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    b           .Lgcm_steady_after

    # ── AES-256 ────────────────────────────────────────────────────
.Lgcm_steady_256:
    # ── round 1  half-front (rk+16) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,16
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 1 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 1  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 2 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 2  half-front (rk+32) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,32
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 3 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 2  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 4 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 3  half-front (rk+48) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,48
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 5 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 3  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 6 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 4  half-front (rk+64) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,64
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 7 (LO)
    GHASH528_PRE2
    GHASH528_POST2_LO
    # ── round 4  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 8 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 5  half-front (rk+80) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,80
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 9 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 5  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 10 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 6  half-front (rk+96) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,96
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 11 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 6  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 12 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 7  half-front (rk+112) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,112
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 13 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 7  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # GHASH step 14 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 8  half-front (rk+128) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,128
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # GHASH step 15 (HI)
    GHASH528_PRE2
    GHASH528_POST2_HI
    # ── round 8  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 9  half-front (rk+144) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,144
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 9  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 10  half-front (rk+160) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,160
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 10  half-back  (mc_idx=2) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-32
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,32
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 11  half-front (rk+176) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,176
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 11  half-back  (mc_idx=3) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-16
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,48
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 12  half-front (rk+192) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,192
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 12  half-back  (mc_idx=0) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-64
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,0
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── round 13  half-front (rk+208) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,208
    vori.b    $vr4,$vr13,0
    vori.b    $vr23,$vr13,0
    vori.b    $vr0,$vr12,0
    vori.b    $vr19,$vr12,0
    vshuf.b   $vr4,$vr18,$vr4,$vr2
    vshuf.b   $vr23,$vr18,$vr23,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr3
    vshuf.b   $vr19,$vr18,$vr19,$vr22
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    # ── round 13  half-back  (mc_idx=1) ──
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,-48
    vori.b    $vr5,$vr15,0
    vld       $vr4,$r16,16
    vshuf.b   $vr5,$vr18,$vr5,$vr2
    vori.b    $vr24,$vr15,0
    vshuf.b   $vr24,$vr18,$vr24,$vr21
    vori.b    $vr2,$vr14,0
    vori.b    $vr21,$vr14,0
    vshuf.b   $vr2,$vr18,$vr2,$vr3
    vshuf.b   $vr21,$vr18,$vr21,$vr22
    vori.b    $vr3,$vr0,0
    vori.b    $vr22,$vr19,0
    vxor.v    $vr2,$vr5,$vr2
    vxor.v    $vr21,$vr24,$vr21
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    vshuf.b   $vr3,$vr18,$vr3,$vr4
    vshuf.b   $vr22,$vr18,$vr22,$vr4
    vxor.v    $vr3,$vr3,$vr0
    vxor.v    $vr22,$vr22,$vr19
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1
    vxor.v    $vr0,$vr0,$vr3
    vxor.v    $vr19,$vr19,$vr22
    # ── final round (rk+224, sr_off=96) ──
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
    vxor.v    $vr3,$vr3,$vr1
    vxor.v    $vr22,$vr22,$vr20
    vld       $vr5,$s1,224
    la.local  $r16,Lk_sbo
    vld       $vr25,$r16,0
    vld       $vr26,$r16,16
    vshuf.b   $vr4,$vr18,$vr25,$vr2
    vshuf.b   $vr23,$vr18,$vr25,$vr21
    vxor.v    $vr4,$vr4,$vr5
    vxor.v    $vr23,$vr23,$vr5
    vshuf.b   $vr0,$vr18,$vr26,$vr3
    vshuf.b   $vr19,$vr18,$vr26,$vr22
    ld.d      $r16,$sp,832
    vld       $vr1,$r16,96
    vxor.v    $vr0,$vr0,$vr4
    vxor.v    $vr19,$vr19,$vr23
    vshuf.b   $vr0,$vr18,$vr0,$vr1
    vshuf.b   $vr19,$vr18,$vr19,$vr1

    # ── after-body: FINAL2, combine, xor-store, seed, INIT2, loop ─
.Lgcm_steady_after:
    GHASH528_FINAL2
    revb.d      $r8,$r8
    revb.d      $r9,$r9
    revb.d      $r13,$r13
    revb.d      $r14,$r14
    xor         $r4,$r8,$r13
    xor         $r5,$r9,$r14
    ld.d        $r16,$sp,816
    ld.d        $r17,$sp,824
    vld         $vr6,$r16,0
    vld         $vr7,$r16,16
    vxor.v      $vr6,$vr6,$vr0
    vxor.v      $vr7,$vr7,$vr19
    vst         $vr6,$r17,0
    vst         $vr7,$r17,16
    addi.d      $r16,$r16,32
    addi.d      $r17,$r17,32
    st.d        $r16,$sp,816
    st.d        $r17,$sp,824
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
    GHASH528_INIT2
    ld.w        $r16,$sp,848
    addi.w      $r16,$r16,2
    st.w        $r16,$sp,848
    revb.2w     $r17,$r16
    vinsgr2vr.w $vr8,$r17,3
    addi.d      $t3,$t3,-32
    beqz        $t3,.Lgcm_drain
    ld.w        $r16,$sp,848
    revb.2w     $r17,$r16
    vori.b      $vr0,$vr8,0
    vinsgr2vr.w $vr0,$r17,3
    addi.w      $r16,$r16,1
    revb.2w     $r16,$r16
    vori.b      $vr19,$vr8,0
    vinsgr2vr.w $vr19,$r16,3
    la.local  $r16,Lk_ipt
    vld       $vr25,$r16,0
    vld       $vr26,$r16,16
    vld       $vr5,$s1,0
    vori.b    $vr1,$vr9,0
    vori.b    $vr20,$vr9,0
    vandn.v   $vr1,$vr1,$vr0
    vandn.v   $vr20,$vr20,$vr19
    vsrli.w   $vr1,$vr1,4
    vsrli.w   $vr20,$vr20,4
    vand.v    $vr0,$vr0,$vr9
    vand.v    $vr19,$vr19,$vr9
    vshuf.b   $vr2,$vr18,$vr25,$vr0
    vshuf.b   $vr21,$vr18,$vr25,$vr19
    vshuf.b   $vr0,$vr18,$vr26,$vr1
    vshuf.b   $vr19,$vr18,$vr26,$vr20
    vxor.v    $vr2,$vr2,$vr5
    vxor.v    $vr21,$vr21,$vr5
    vxor.v    $vr0,$vr0,$vr2
    vxor.v    $vr19,$vr19,$vr21
    b           .Lgcm_steady

    # ─── drain: finish last GHASH (non-interleaved) ─────────────────
.Lgcm_drain:
    .rept 7
    GHASH528_PRE2
    GHASH528_POST2_LO
    .endr
    .rept 8
    GHASH528_PRE2
    GHASH528_POST2_HI
    .endr
    GHASH528_FINAL2
    revb.d      $r8,$r8
    revb.d      $r9,$r9
    revb.d      $r13,$r13
    revb.d      $r14,$r14
    xor         $r4,$r8,$r13
    xor         $r5,$r9,$r14
    st.d        $r4,$fp,0
    st.d        $r5,$fp,8
    # Write counter back to ivec.
    ld.w    $r16,$sp,848
    revb.2w $r16,$r16
    vinsgr2vr.w $vr8,$r16,3
    ld.d    $r16,$sp,840
    vst     $vr8,$r16,0

.Lgcm_enc_done:
    ori     $a0,$s0,0

.Lgcm_epilogue:
    ld.d    $ra,$sp,952
    ld.d    $fp,$sp,944
    ld.d    $s0,$sp,936
    ld.d    $s1,$sp,928
    ld.d    $s2,$sp,920
    ld.d    $s3,$sp,912
    ld.d    $s4,$sp,904
    ld.d    $s5,$sp,896
    ld.d    $s6,$sp,888
    ld.d    $s7,$sp,880
    ld.d    $s8,$sp,872
    addi.d  $sp,$sp,960
    jirl    $zero,$ra,0

.Lgcm_enc_ret0:
    move    $a0,$zero
    jirl    $zero,$ra,0
.cfi_endproc
.size   loongarch64_vpaes_gcm_encrypt,.-loongarch64_vpaes_gcm_encrypt

