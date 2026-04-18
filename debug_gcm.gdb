set breakpoint pending on
set pagination off
b loongarch64_vpaes_gcm_encrypt
r
# Step past the beqz and addi.d sp, sp, -960 in prologue
si 2
# Now sp is adjusted, set watchpoint on actual sp+816
watch *(long long*)($sp+816)
c
# First hit: st.d $a0,$sp,816 in prologue
x/gx $sp+816
c
# Second hit: warmup xor_store advances inp
x/gx $sp+816
c
# Third hit: should be in steady_after xor_store or corruption
x/5i $pc-16
x/gx $sp+816
info reg r16 r17
bt 1
c
# Fourth hit
x/5i $pc-16
x/gx $sp+816
info reg r16 r17
c
