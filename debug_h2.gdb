set breakpoint pending on
set pagination off
b loongarch64_vpaes_gcm_encrypt
r
# Step past beqz and addi.d sp,-960
si 2
# Now in prologue, step until we reach the warmup (past H^2 table setup)
# Let's use a breakpoint at the warmup label instead
# Find the address difference from function start + specific offset
# The warmup AES code starts after all the table setup
# Let's just step to a unique instruction and dump tables

# Set a temporary breakpoint after the H^2 prep code
# The emit_528_prep for H^2 runs and then we load Xi + preheat
# After preheat, the MC_base save + Xi load happen, then warmup
# Let's break when $s0 is written with aligned_len (before counter setup)
# This is: "st.d $s0,$sp,856" (which we added for loop counter save)
# OR just wait for a unique store pattern

# Actually, let's break at _vpaes_preheat call and examine the tables then
b _vpaes_preheat
c
# Now at _vpaes_preheat entry, tables should be set up

# Dump H value from context ($fp + 16)
printf "H from context:\n"
x/2gx $fp+16

# Dump H^2 raw (sp+800)
printf "H^2 raw:\n"
x/2gx $sp+800

# Dump Htable from context ($fp+32), first 3 entries
printf "Htable (H) first entries:\n"
x/6gx $fp+32

# Dump H^2 4-bit table ($s6 = sp+272), first 3 entries
printf "H^2 table first entries:\n"
printf "s6 = %p\n", $r29
x/6gx $r29

# Dump entry [8] of both tables
printf "Htable[8] (H):\n"
x/2gx $fp+32+128
printf "H2table[8]:\n"
x/2gx $r29+128

# Continue to see if test runs
c
