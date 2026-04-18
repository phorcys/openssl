set breakpoint pending on
set pagination off
b loongarch64_vpaes_gcm_encrypt
r
# At function entry, check $a5 (Xi pointer) = $r9
printf "Entry: a5(Xi)=%p fp=%p\n", $r9, $r22
si 2
# After sp adjustment
printf "After prologue sp adj: sp=%p\n", $sp
# Continue to the bl _vpaes_preheat
b _vpaes_preheat
c
printf "At preheat: fp=%p s1=%p\n", $r22, $r24
printf "Xi(fp) = %p\n", $r22
x/2gx $r22
printf "H(fp+16):\n"
x/2gx $r22+16
printf "Htable[0](fp+32):\n"
x/2gx $r22+32
printf "Htable[8](fp+32+128):\n"
x/2gx $r22+32+128
c
