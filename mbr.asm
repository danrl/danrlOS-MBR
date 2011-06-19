; danrlOS bootloader for x86
; --------------------------------------
%define BIOS_START		0x7C00
%define MBR_SIZE		0x200
%define BLOCKBUFFER_SIZE	0x200
%define	FIRST_PART_OFFSET	0x01BE
; --------------------------------------
%define BLOCKBUFFER		BIOS_START + MBR_SIZE
%define FIRST_PARTITION		BIOS_START + FIRST_PART_OFFSET
%define KERNEL_ADDR		BIOS_START + MBR_SIZE + BLOCKBUFFER_SIZE
%define DFS_DATA_BEGIN		BIOS_START + MBR_SIZE + 0x004
%define DFS_DATA_END		BIOS_START + MBR_SIZE + 0x1FB + 0x01
%define DFS_NEXTBLOCK_0		BIOS_START + MBR_SIZE + 0x1FC
%define DFS_NEXTBLOCK_1		BIOS_START + MBR_SIZE + 0x1FE
; --------------------------------------
[ORG BIOS_START]
[BITS 16]
; boot
	cli				; disable interrupts
	xor	ax, ax			; clear ax
	mov	ds, ax			; set data segment to 0

; set video mode
	mov	ax, 0x03		; 80x25 color mode
	int	0x10			; BIOS interrupt

; print header
	mov	si, danrlos
	call	print_string

; load gdt
	lgdt	[gdt_toc]		; load gdt

; enable A20
	mov	al, 0xDD		; send enable a20 address line command
	out	0x64, al

; look for bootable danrlFS partition type 0xD0, partitions are at offsets 0x01BE, 0x01CE, 0x01DE, 0x01EE
	; start of partition definition
	mov	bx, FIRST_PARTITION
	check_partition_boot:
	; check if bootable
	mov	al, [bx]		; load bootable flag of partition
	cmp 	al, 0x80		; valid bootable flag
	je	check_partition_type
	jmp	next_partition		; to next partition
	; check if partition type is 0xD0
	check_partition_type:
	add	bx, 0x04		; partition type is 0x04 ahead
	mov	al, [bx]
	cmp	al, 0xD0		; compare partition type
	je	partition_found
	next_partition:
	cmp	bx, 0x01F2		; abort after 4 partitions checked
	je	error
	add	bx, 0x0C		; offset to next partition
	jmp	check_partition_boot
	partition_found:
	; save important values for later use
	mov	[boot_device], dl	; save boot device
	; load start LBA into next_block variable
	; for later use with disk address packet
	add	bx, 0x04		; start LBA offset
	mov	ax, [bx]
	mov	[part_lba_0], ax
	add	bx, 0x02
	mov	ax, [bx]
	mov	[part_lba_1], ax

; scan the danrlFS for KERNEL
	find_volume_label:
	call	load_blockbuffer
	call	increment_nextblock
	cmp	ah, 0xFF		; 0xFF indicates volume label
	jne	find_volume_label

	; look for file info block
	find_file_info_block:
	call	load_blockbuffer
	call	increment_nextblock
	cmp	ah, 0x02		; 0x02 indicates file info block
	jne	find_file_info_block
	; look for filename KERNEL
	mov	al, [BLOCKBUFFER + 0x08 + 0x00] 
	cmp	al, 'K'
	jne	find_file_info_block
	mov	al, [BLOCKBUFFER + 0x08 + 0x01] 
	cmp	al, 'E'
	jne	find_file_info_block
	mov	al, [BLOCKBUFFER + 0x08 + 0x02] 
	cmp	al, 'R'
	jne	find_file_info_block
	mov	al, [BLOCKBUFFER + 0x08 + 0x03] 
	cmp	al, 'N'
	jne	find_file_info_block
	mov	al, [BLOCKBUFFER + 0x08 + 0x04] 
	cmp	al, 'E'
	jne	find_file_info_block
	mov	al, [BLOCKBUFFER + 0x08 + 0x05] 
	cmp	al, 'L'
	jne	find_file_info_block
	mov	al, [BLOCKBUFFER + 0x08 + 0x06] 
	cmp	al, 0x0
	jne	find_file_info_block

; KERNEL found, load it!
	mov	ax, [DFS_NEXTBLOCK_0]
	mov	bx, [DFS_NEXTBLOCK_1]
	mov	[next_block_0], ax
	mov	[next_block_1], bx

	loadfile_begin:
	call	load_blockbuffer
	mov	cx, DFS_DATA_BEGIN
	mov	dx, [kdata_addr]

	; data transfer
	loadfile_loop:
	mov	bx, cx
	mov	ah, [bx]
	mov	bx, dx
	mov	[bx], ah
	add	cx, 1
	add	dx, 1
	mov	[kdata_addr], dx
	cmp	cx, DFS_DATA_END
	jne	loadfile_loop

	; load next block address
	mov	ax, [DFS_NEXTBLOCK_0]
	mov	bx, [DFS_NEXTBLOCK_1]
	mov	[next_block_0], ax
	mov	[next_block_1], bx
	cmp	ax, 0x0
	jne	loadfile_begin
	cmp	bx, 0x0
	jne	loadfile_begin

; switch to protected mode
	start_protected_mode:
	mov	eax, cr0
	or	al, 1
	mov	cr0, eax
	jmp 0x8:protected_mode
[Bits 32]
	protected_mode:
	; set registers
	mov	ax, 0x10		; dec 16
	mov	ds, ax			; 
	mov	ss, ax			;
	mov	es, ax			;
	xor	eax, eax		; clear eax
	mov	fs, ax			; null descriptor
	mov	gs, ax			; null descriptor
	mov	esp, 0x10000		; set stack below 2mb limit
; far jump to kernel
	jmp	KERNEL_ADDR		; jump to c-kernel

[Bits 16]
; --------------------------------------
; functions
load_blockbuffer:
	; print a fancy dot
	mov	si, dot
	call	print_string

	; copy next_block into dap
	xor	dx, dx
	mov	bx, [next_block_0]
	add	bx, [part_lba_0]
	jnc	.nocarry0
	mov	dx, 1
	.nocarry0:
	mov	[dap_lba_0], bx
	add	dx, [next_block_1]
	add	dx, [part_lba_1]
	mov	[dap_lba_1], dx

	; create disk address packet
	mov	dl, [boot_device]
	mov 	si, disk_address_packet
	mov 	ah, 0x42		; extended disk access
	int 	0x13
	jc	error

	.ret:
	; load block type into ah
	mov	ah, [BLOCKBUFFER]
	ret

increment_nextblock:
	; increment next block
	mov	bx, [next_block_0]
	mov	cx, [next_block_1]
	add	bx, 1
	jnc	.endinc				; jump if carry (for 32 bit LBA)
	add	cx, 1
	.endinc:
	mov	[next_block_0], bx
	mov	[next_block_1], cx
	ret

error:
	mov	si, err		; print error
	call	print_string
	.loop:
	jmp .loop

print_string:
	.loop:
	lodsb				; load byte at address DS:(E)SI into AL
	or	al, al			; or AL by AL
					; 10 or 10 = 10
					; 00 or 00 = 00
					; this sets the zero flag if AL=0x0 (end of string)
	jz	.ret			; exit of end of string 
	mov	ah, 0x0E		; 0x0E=write character and move cursor one step forward
					; character to be written by bios is read from AL
	int	0x10			; trigger bios vga interrupt
	jmp	.loop			; jump back to beginning
	.ret:
	ret				; exit function

; --------------------------------------
; data
; CR=0x0D, LF=0x0A, NULL=0
	danrlos		db '-danrlOS-', 0x0D, 0x0A, '[boot]', 0
	dot		db '.', 0
	boot_device	db 0
	part_lba_0	dw 0
	part_lba_1	dw 0
	next_block_0	dw 0
	next_block_1	dw 0
	kdata_addr	dw KERNEL_ADDR
	err		db 'ERR!', 0
; --------------------------------------
; disk address packet
	disk_address_packet:
	db	0x10			; size of packet
	db	0x00			; reserved
	dw	0x01			; number of blocks to transfer
	dw	BLOCKBUFFER		; buffer destination address
	dw	0x0			; in page 0
	dap_lba_0:
	db	0x01			; start block number byte 1/4
	db	0x00			; start block number byte 2/4
	dap_lba_1:
	db	0x00			; start block number byte 3/4
	db	0x00			; start block number byte 4/4
; gdt-data
	gdt_null_descriptor:
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	db 	00000000b		; null byte
	gdt_code_descriptor:
	db 	11111111b		; 1st byte of segment length
	db 	11111111b		; 2nd byte of segment length
	db 	00000000b		; 1st byte of base address
	db 	00000000b		; 2nd byte of base address
	db 	00000000b		; 3rd byte of base address
	db 	10011010b		; access rights
					; 1        	: present
					;  00		: DPL level 0
					;    1    	: code, data or stack descriptor
					;     101	: type, code read/execute
					;        0 	: accessed bit
	db 	11001111b		; granularity
					; 1       	: 4kb
					;  1      	: use 32 segment
					;   00    	: reserved
					;     xxxx	: last 4 bit of segment length
	db 	00000000b		; 4th byte of base address
	gdt_data_descriptor:
	db 	11111111b		; 1st byte of segment length
	db 	11111111b		; 2nd byte of segment length
	db 	00000000b		; 1st byte of base address
	db 	00000000b		; 2nd byte of base address
	db 	00000000b		; 3rd byte of base address
	db 	10010010b		; access rights
					; 1        	: present
					;  00		: DPL level 0
					;    1    	: code, data or stack descriptor
					;     001	: type, data read/write
					;        0 	: accessed bit
	db 	11001111b		; granularity
					; 1       	: 4kb
					;  1      	: use 32 segment
					;   00    	: reserved
					;     xxxx	: last 4 bit of segment length
	db 	00000000b		; 4th byte of base address
	gdt_toc:
	dw 	24			; size of gdt
	dd	gdt_null_descriptor	; base of gdt
; --------------------------------------
; fill up to 440 byte
	times	440-($-$$) db 0		; padding
	; disk signature (optional)
	db	0x49
	db	0x40
	db	0x87
	db	0x21
	; 16 zeros (only heaven knows why)
	db	0
	db	0
; --------------------------------------
; partition table
	; -------- PARTITION NUMBER 1 --------
	; status flag
	db	0x80			; 0x80=bootable 0x00=non-bootable 0x??=invalid
	; CHS start address
	db	00000001b		; head bits 7-0
	db	00000001b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; partition type
	db	0xD0			; 0x0B=FAT32 0xD0=danrlFS
	; CHS end address
	db	00111001b		; head bits 7-0
	db	00010011b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000110b		; cylinder bits 7-0
	; logical block address of first sector
	db	0x01
	db	0x00
	db	0x00
	db	0x00
	; number of sectors, little endian!
	db	0x61
	db	0x86
	db	0x01
	db	0x00
	; -------- PARTITION NUMBER 2 --------
	; status flag
	db	0x00			; 0x80=bootable 0x00=non-bootable 0x??=invalid
	; CHS start address
	db	00000000b		; head bits 7-0
	db	00000000b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; partition type
	db	0x00			; 0x0B=FAT32 0xD0=danrlFS
	; CHS end address
	db	00000000b		; head bits 7-0
	db	00000000b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; logical block address of first sector
	db	0x00
	db	0x00
	db	0x00
	db	0x00
	; number of sectors, little endian!
	db	0x00
	db	0x00
	db	0x00
	db	0x00
	; -------- PARTITION NUMBER 3 --------
	; status flag
	db	0x00			; 0x80=bootable 0x00=non-bootable 0x??=invalid
	; CHS start address
	db	00000000b		; head bits 7-0
	db	00000000b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; partition type
	db	0x00			; 0x0B=FAT32 0xD0=danrlFS
	; CHS end address
	db	00000000b		; head bits 7-0
	db	00000000b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; logical block address of first sector
	db	0x00
	db	0x00
	db	0x00
	db	0x00
	; number of sectors, little endian!
	db	0x00
	db	0x00
	db	0x00
	db	0x00
	; -------- PARTITION NUMBER 4 --------
	; status flag
	db	0x00			; 0x80=bootable 0x00=non-bootable 0x??=invalid
	; CHS start address
	db	00000000b		; head bits 7-0
	db	00000000b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; partition type
	db	0x00			; 0x0B=FAT32 0xD0=danrlFS
	; CHS end address
	db	00000000b		; head bits 7-0
	db	00000000b		; cylinder and sector
					; xx       : cylinder bits 9-8
					;   xxxxxx : sector bits 5-0
	db	00000000b		; cylinder bits 7-0
	; logical block address of first sector
	db	0x00
	db	0x00
	db	0x00
	db	0x00
	; number of sectors, little endian!
	db	0x00
	db	0x00
	db	0x00
	db	0x00

	; MBR signature
	db	0x55			; boot sector signature
	db	0xAA			; boot sector signature

