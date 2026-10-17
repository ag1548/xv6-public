SRC_DIR       := src
ASM_DIR       := $(SRC_DIR)/asm
OBJ_DIR       := obj
UPROG_OBJ_DIR := $(OBJ_DIR)/uprogs
LD_DIR        := linker
INC_DIR       := include
BUILD_DIR     := build
UPROGS_DIR    := $(BUILD_DIR)/uprogs
IMAGES_DIR    := $(BUILD_DIR)/images
SCRIPTS_DIR   := scripts
RUNOFF_DIR    := $(SCRIPTS_DIR)/runoff

DIRS := \
	$(ASM_DIR) \
	$(BUILD_DIR) \
	$(IMAGES_DIR) \
	$(INC_DIR) \
	$(LD_DIR) \
	$(OBJ_DIR) \
	$(RUNOFF_DIR) \
	$(SCRIPTS_DIR) \
	$(SRC_DIR) \
	$(UPROG_OBJ_DIR) \
	$(UPROGS_DIR) \

$(shell mkdir -p $(DIRS))

C_OBJ_NAMES := \
	bio.o      \
	console.o  \
	exec.o     \
	file.o     \
	fs.o       \
	ide.o      \
	ioapic.o   \
	kalloc.o   \
	kbd.o      \
	lapic.o    \
	log.o      \
	main.o     \
	mp.o       \
	picirq.o   \
	pipe.o     \
	proc.o     \
	sleeplock.o\
	spinlock.o \
	string.o   \
	syscall.o  \
	sysfile.o  \
	sysproc.o  \
	trap.o     \
	uart.o     \
	vm.o       \

C_OBJS = $(addprefix $(OBJ_DIR)/,$(C_OBJ_NAMES))

ASM_OBJ_NAMES := \
	swtch.o        \
	trapasm.o      \

ASM_OBJS = $(addprefix $(OBJ_DIR)/,$(ASM_OBJ_NAMES))

PERL_OBJ_NAMES := \
	vectors.o       \

PERL_OBJS = $(addprefix $(OBJ_DIR)/,$(PERL_OBJ_NAMES))

OBJS := $(C_OBJS) $(ASM_OBJS) $(PERL_OBJS)

# Cross-compiling (e.g., on Mac OS X)
# TOOLPREFIX = i386-jos-elf

# Using native tools (e.g., on X86 Linux)
# TOOLPREFIX =

# Try to infer the correct TOOLPREFIX if not set
ifndef TOOLPREFIX
TOOLPREFIX := $(shell if i386-jos-elf-objdump -i 2>&1 | grep '^elf32-i386$$' >/dev/null 2>&1; \
	then echo 'i386-jos-elf-'; \
	elif objdump -i 2>&1 | grep 'elf32-i386' >/dev/null 2>&1; \
	then echo ''; \
	else echo "***" 1>&2; \
	echo "*** Error: Couldn't find an i386-*-elf version of GCC/binutils." 1>&2; \
	echo "*** Is the directory with i386-jos-elf-gcc in your PATH?" 1>&2; \
	echo "*** If your i386-*-elf toolchain is installed with a command" 1>&2; \
	echo "*** prefix other than 'i386-jos-elf-', set your TOOLPREFIX" 1>&2; \
	echo "*** environment variable to that prefix and run 'make' again." 1>&2; \
	echo "*** To turn off this error, run 'gmake TOOLPREFIX= ...'." 1>&2; \
	echo "***" 1>&2; exit 1; fi)
endif

# If the makefile can't find QEMU, specify its path here
# QEMU = qemu-system-i386

# Try to infer the correct QEMU
ifndef QEMU
QEMU = $(shell if which qemu > /dev/null; \
	then echo qemu; exit; \
	elif which qemu-system-i386 > /dev/null; \
	then echo qemu-system-i386; exit; \
	elif which qemu-system-x86_64 > /dev/null; \
	then echo qemu-system-x86_64; exit; \
	else \
	qemu=/Applications/Q.app/Contents/MacOS/i386-softmmu.app/Contents/MacOS/i386-softmmu; \
	if test -x $$qemu; then echo $$qemu; exit; fi; fi; \
	echo "***" 1>&2; \
	echo "*** Error: Couldn't find a working QEMU executable." 1>&2; \
	echo "*** Is the directory containing the qemu binary in your PATH" 1>&2; \
	echo "*** or have you tried setting the QEMU variable in Makefile?" 1>&2; \
	echo "***" 1>&2; exit 1)
endif

CC = $(TOOLPREFIX)gcc
AS = $(TOOLPREFIX)gas
LD = $(TOOLPREFIX)ld
OBJCOPY = $(TOOLPREFIX)objcopy
OBJDUMP = $(TOOLPREFIX)objdump
CFLAGS = -fno-pic -static -fno-builtin -fno-strict-aliasing -O2 -Wall -MD -ggdb -m32 -Werror -fno-omit-frame-pointer -fno-tree-vrp -I$(INC_DIR)
CFLAGS += $(shell $(CC) -fno-stack-protector -E -x c /dev/null >/dev/null 2>&1 && echo -fno-stack-protector)
ASFLAGS = -m32 -gdwarf-2 -Wa,-divide -I$(INC_DIR)
# FreeBSD ld wants ``elf_i386_fbsd''
LDFLAGS += -m $(shell $(LD) -V | grep elf_i386 2>/dev/null | head -n 1)

# Disable PIE when possible (for Ubuntu 16.10 toolchain)
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]no-pie'),)
CFLAGS += -fno-pie -no-pie
endif
ifneq ($(shell $(CC) -dumpspecs 2>/dev/null | grep -e '[^f]nopie'),)
CFLAGS += -fno-pie -nopie
endif

run:
	@${MAKE} clean --no-print-directory
	@${MAKE} $(IMAGES_DIR)/xv6.img --no-print-directory
	@${MAKE} qemu --no-print-directory

$(IMAGES_DIR)/xv6.img: $(BUILD_DIR)/bootblock $(BUILD_DIR)/kernel
	dd if=/dev/zero of=$(IMAGES_DIR)/xv6.img count=10000
	dd if=$(BUILD_DIR)/bootblock of=$(IMAGES_DIR)/xv6.img conv=notrunc
	dd if=$(BUILD_DIR)/kernel of=$(IMAGES_DIR)/xv6.img seek=1 conv=notrunc

xv6memfs.img: bootblock kernelmemfs
	dd if=/dev/zero of=xv6memfs.img count=10000
	dd if=bootblock of=xv6memfs.img conv=notrunc
	dd if=kernelmemfs of=xv6memfs.img seek=1 conv=notrunc

$(BUILD_DIR)/bootblock: $(ASM_DIR)/bootasm.S $(SRC_DIR)/bootmain.c
	$(CC) $(CFLAGS) -fno-pic -O -nostdinc -I$(INC_DIR) -c $(SRC_DIR)/bootmain.c -o $(OBJ_DIR)/bootmain.o
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I$(INC_DIR) -c $(ASM_DIR)/bootasm.S -o $(OBJ_DIR)/bootasm.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7C00 -o $(OBJ_DIR)/bootblock.o $(OBJ_DIR)/bootasm.o $(OBJ_DIR)/bootmain.o
	$(OBJDUMP) -S $(OBJ_DIR)/bootblock.o > $(ASM_DIR)/bootblock.asm
	$(OBJCOPY) -S -O binary -j .text $(OBJ_DIR)/bootblock.o $(BUILD_DIR)/bootblock
	$(SCRIPTS_DIR)/sign.pl $(BUILD_DIR)/bootblock

$(C_OBJS): $(OBJ_DIR)/%.o : $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) -c $< -o $@

$(OBJ_DIR)/entry.o: $(ASM_DIR)/entry.S
	$(CC) $(ASFLAGS) -c $< -o $@

$(ASM_OBJS): $(OBJ_DIR)/%.o : $(ASM_DIR)/%.S
	$(CC) $(ASFLAGS) -c $< -o $@

$(PERL_OBJS): $(OBJ_DIR)/%.o : $(BUILD_DIR)/vectors.S
	$(CC) $(ASFLAGS) -c $< -o $@

$(BUILD_DIR)/entryother: $(ASM_DIR)/entryother.S
	$(CC) $(CFLAGS) -fno-pic -nostdinc -I$(INC_DIR) -c $(ASM_DIR)/entryother.S -o $(OBJ_DIR)/entryother.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0x7000 -o $(OBJ_DIR)/bootblockother.o $(OBJ_DIR)/entryother.o
	$(OBJCOPY) -S -O binary -j .text $(OBJ_DIR)/bootblockother.o $(BUILD_DIR)/entryother
	$(OBJDUMP) -S $(OBJ_DIR)/bootblockother.o > $(ASM_DIR)/entryother.asm

$(BUILD_DIR)/initcode: $(ASM_DIR)/initcode.S
	$(CC) $(CFLAGS) -nostdinc -I$(INC_DIR) -c $(ASM_DIR)/initcode.S -o $(OBJ_DIR)/initcode.o
	$(LD) $(LDFLAGS) -N -e start -Ttext 0 -o $(BUILD_DIR)/initcode.out $(OBJ_DIR)/initcode.o
	$(OBJCOPY) -S -O binary $(BUILD_DIR)/initcode.out $(BUILD_DIR)/initcode
	$(OBJDUMP) -S $(OBJ_DIR)/initcode.o > $(ASM_DIR)/initcode.asm

$(BUILD_DIR)/kernel: $(OBJS) $(OBJ_DIR)/entry.o $(BUILD_DIR)/entryother $(BUILD_DIR)/initcode $(LD_DIR)/kernel.ld
	$(LD) $(LDFLAGS) -T $(LD_DIR)/kernel.ld -o $(BUILD_DIR)/kernel $(OBJ_DIR)/entry.o $(OBJS) -b binary $(BUILD_DIR)/initcode $(BUILD_DIR)/entryother
	$(OBJDUMP) -S $(BUILD_DIR)/kernel > $(ASM_DIR)/kernel.asm
	$(OBJDUMP) -t $(BUILD_DIR)/kernel | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILD_DIR)/kernel.sym

# kernelmemfs is a copy of kernel that maintains the
# disk image in memory instead of writing to a disk.
# This is not so useful for testing persistent storage or
# exploring disk buffering implementations, but it is
# great for testing the kernel on real hardware without
# needing a scratch disk.
MEMFSOBJS = $(filter-out ide.o,$(OBJS)) memide.o
kernelmemfs: $(MEMFSOBJS) entry.o entryother initcode kernel.ld fs.img
	$(LD) $(LDFLAGS) -T kernel.ld -o kernelmemfs entry.o  $(MEMFSOBJS) -b binary initcode entryother fs.img
	$(OBJDUMP) -S kernelmemfs > kernelmemfs.asm
	$(OBJDUMP) -t kernelmemfs | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > kernelmemfs.sym

tags: $(OBJS) entryother.S _init
	etags *.S *.c

$(BUILD_DIR)/vectors.S: $(SCRIPTS_DIR)/vectors.pl
	$(SCRIPTS_DIR)/vectors.pl > $(BUILD_DIR)/vectors.S

$(UPROG_OBJ_DIR)/%.o: $(SRC_DIR)/%.c
	$(CC) $(CFLAGS) $(CFLAGS) -c $< -o $@

$(UPROG_OBJ_DIR)/usys.o: src/asm/usys.S
	$(CC) $(ASFLAGS) -c -o $(UPROG_OBJ_DIR)/usys.o src/asm/usys.S

$(UPROG_OBJ_DIR)/ulib.o: src/ulib.c
	$(CC) $(CFLAGS) -c -o $(UPROG_OBJ_DIR)/ulib.o src/ulib.c

$(UPROG_OBJ_DIR)/printf.o: src/printf.c
	$(CC) $(CFLAGS) -c -o $(UPROG_OBJ_DIR)/printf.o src/printf.c

$(UPROG_OBJ_DIR)/umalloc.o: src/umalloc.c
	$(CC) $(CFLAGS) -c -o $(UPROG_OBJ_DIR)/umalloc.o src/umalloc.c

$(UPROG_OBJ_DIR)/forktest.o: src/forktest.c
	$(CC) $(CFLAGS) -c -o $(UPROG_OBJ_DIR)/forktest.o src/forktest.c

ULIB_OBJ_NAMES := \
	ulib.o     \
	usys.o     \
	printf.o   \
	umalloc.o  \

ULIB = $(addprefix $(UPROG_OBJ_DIR)/,$(ULIB_OBJ_NAMES))

$(UPROGS_DIR)/_%: $(UPROG_OBJ_DIR)/%.o $(ULIB)
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $@ $^
	$(OBJDUMP) -S $@ > $(ASM_DIR)/$*.asm
	$(OBJDUMP) -t $@ | sed '1,/SYMBOL TABLE/d; s/ .* / /; /^$$/d' > $(BUILD_DIR)/$*.sym

$(UPROGS_DIR)/_forktest: $(UPROG_OBJ_DIR)/forktest.o $(ULIB)
	# forktest has less library code linked in - needs to be small
	# in order to be able to max out the proc table.
	$(LD) $(LDFLAGS) -N -e main -Ttext 0 -o $(UPROGS_DIR)/_forktest $(UPROG_OBJ_DIR)/forktest.o $(UPROG_OBJ_DIR)/ulib.o $(UPROG_OBJ_DIR)/usys.o
	$(OBJDUMP) -S $(UPROGS_DIR)/_forktest > $(ASM_DIR)/forktest.asm

$(BUILD_DIR)/mkfs: $(SRC_DIR)/mkfs.c $(INC_DIR)/fs.h
	gcc -Werror -Wall -o $(BUILD_DIR)/mkfs $(SRC_DIR)/mkfs.c -iquote $(INC_DIR)

# Prevent deletion of intermediate files, e.g. cat.o, after first build, so
# that disk image changes after first build are persistent until clean.  More
# details:
# http://www.gnu.org/software/make/manual/html_node/Chained-Rules.html
.PRECIOUS: $(OBJ_DIR)/%.o
.PRECIOUS: $(UPROG_OBJ_DIR)/%.o

UPROG_NAMES := \
	_cat         \
	_echo        \
	_forktest    \
	_grep        \
	_init        \
	_kill        \
	_ln          \
	_ls          \
	_mkdir       \
	_rm          \
	_sh          \
	_stressfs    \
	_usertests   \
	_wc          \
	_zombie      \

UPROGS := $(addprefix $(UPROGS_DIR)/,$(UPROG_NAMES))

$(IMAGES_DIR)/fs.img: $(BUILD_DIR)/mkfs README.md $(UPROGS)
	$(BUILD_DIR)/mkfs $(IMAGES_DIR)/fs.img README.md $(UPROGS)

-include $(OBJ_DIR)/*.d

list-ignored-files:
	git ls-files --others --ignored --exclude-standard

clean:
	rm -f                     \
	*.tex                     \
	*.dvi                     \
	*.idx                     \
	*.aux                     \
	*.log                     \
	*.ind                     \
	*.ilg                     \
	$(OBJ_DIR)/*.o            \
	$(OBJ_DIR)/*.d            \
	$(ASM_DIR)/*.asm          \
	$(BUILD_DIR)/*.sym        \
	$(BUILD_DIR)/vectors.S    \
	$(BUILD_DIR)/bootblock    \
	$(BUILD_DIR)/entryother   \
	$(BUILD_DIR)/initcode     \
	$(BUILD_DIR)/initcode.out \
	$(BUILD_DIR)/kernel       \
	$(IMAGES_DIR)/xv6.img     \
	fs.img                    \
	kernelmemfs               \
	xv6memfs.img              \
	mkfs                      \
	.gdbinit                  \
	$(UPROGS)

# make a printout
FILES = $(shell grep -v '^\#' $(RUNOFF_DIR)/runoff.list)
PRINT = runoff.list runoff.spec README.md toc.hdr toc.ftr $(FILES)

xv6.pdf: $(PRINT)
	./runoff
	ls -l xv6.pdf

print: xv6.pdf

# run in emulators

bochs : fs.img xv6.img
	if [ ! -e .bochsrc ]; then ln -s dot-bochsrc .bochsrc; fi
	bochs -q

# try to generate a unique GDB port
GDBPORT = $(shell expr `id -u` % 5000 + 25000)
# QEMU's gdb stub command line changed in 0.11
QEMUGDB = $(shell if $(QEMU) -help | grep -q '^-gdb'; \
	then echo "-gdb tcp::$(GDBPORT)"; \
	else echo "-s -p $(GDBPORT)"; fi)
ifndef CPUS
CPUS := 2
endif

QEMUOPTS =                                                        \
	-drive file=$(IMAGES_DIR)/fs.img,index=1,media=disk,format=raw  \
	-drive file=$(IMAGES_DIR)/xv6.img,index=0,media=disk,format=raw \
	-smp $(CPUS)                                                    \
	-m 512                                                          \
	$(QEMUEXTRA)                                                    \

qemu: $(IMAGES_DIR)/fs.img $(IMAGES_DIR)/xv6.img
	$(QEMU) -serial mon:stdio $(QEMUOPTS)

qemu-memfs: xv6memfs.img
	$(QEMU) -drive file=xv6memfs.img,index=0,media=disk,format=raw -smp $(CPUS) -m 256

qemu-nox: fs.img xv6.img
	$(QEMU) -nographic $(QEMUOPTS)

.gdbinit: .gdbinit.tmpl
	sed "s/localhost:1234/localhost:$(GDBPORT)/" < $^ > $@

qemu-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -serial mon:stdio $(QEMUOPTS) -S $(QEMUGDB)

qemu-nox-gdb: fs.img xv6.img .gdbinit
	@echo "*** Now run 'gdb'." 1>&2
	$(QEMU) -nographic $(QEMUOPTS) -S $(QEMUGDB)

# CUT HERE
# prepare dist for students
# after running make dist, probably want to
# rename it to rev0 or rev1 or so on and then
# check in that version.

EXTRA=\
	mkfs.c ulib.c user.h cat.c echo.c forktest.c grep.c kill.c\
	ln.c ls.c mkdir.c rm.c stressfs.c usertests.c wc.c zombie.c\
	printf.c umalloc.c\
	README.md dot-bochsrc *.pl toc.* runoff runoff1 runoff.list\
	.gdbinit.tmpl gdbutil\

dist:
	rm -rf dist
	mkdir dist
	for i in $(FILES); \
	do \
		grep -v PAGEBREAK $$i >dist/$$i; \
	done
	sed '/CUT HERE/,$$d' Makefile >dist/Makefile
	echo >dist/runoff.spec
	cp $(EXTRA) dist

dist-test:
	rm -rf dist
	make dist
	rm -rf dist-test
	mkdir dist-test
	cp dist/* dist-test
	cd dist-test; $(MAKE) print
	cd dist-test; $(MAKE) bochs || true
	cd dist-test; $(MAKE) qemu

# update this rule (change rev#) when it is time to
# make a new revision.
tar:
	rm -rf /tmp/xv6
	mkdir -p /tmp/xv6
	cp dist/* dist/.gdbinit.tmpl /tmp/xv6
	(cd /tmp; tar cf - xv6) | gzip >xv6-rev10.tar.gz  # the next one will be 10 (9/17)

.PHONY: dist-test dist
