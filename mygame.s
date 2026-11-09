.var mapwidth=64
.var mapheight=64
.var charbuf1=$0400
.var charbuf2=$0800
.var colbuf=$D800
.var readyprompt=$A483
.var charsetaddr=$3800
.var vichposval=%11010000
.var vichpos=$D016
.var vicvposval=%00010000
.var vicvpos=$D011
.var vicpointers=$D018
.var spritebase=$2000
.var vicbuf1=((((>charset)>>2)&14)|(((>charbuf1)&60)<<2)|1)
.var vicbuf2=((((>charset)>>2)&14)|(((>charbuf2)&60)<<2)|1)
.var sprite_xlo=0
.var sprite_xhi=32
.var sprite_y=64
.var sprite_color=96
.var sprite_pointer=128
.var sprite_controller=160
.var sprite_anim=192
.var sprite_frame=224
.var sprite_delay=256
.var sprite_global_xlo=32*9
.var sprite_global_xhi=32*10
.var sprite_global_ylo=32*11
.var sprite_global_yhi=32*12
.var sprite_dxlo=32*13
.var sprite_dxhi=32*14
.var sprite_dylo=32*15
.var sprite_dyhi=32*16
.var sprite_yhi=32*17
.var sprite_order=32*18
.var sprite_clip=32*19       // rows hidden above the window (myvic2.s clip_sprites)
.var sprite_srcptr=32*20     // animation frame of a clipped sprite (debug/tests)
.var sprite_total_size=32*21
.var sidinit=$e000
.var sidplay=$e003


.disk [filename="mygame.d64", name="CONAN,ACCOUNTANT", id="2025!" ]
	{
	[name="CONAN,ACCOUNTANT", type="prg", segments="LOADER" ],
	[name="CB", type="prg", segments="CBLOADER,CBLOADERINIT" ],
	[name="01", type="prg", segments="SPLASHSCREEN,SPLASHBITMAP"],
	[name="02", type="prg", segments="SPLASHCOLOR"],
	[name="03", type="prg", sidFiles="Degalvanized.sid" ],
	[name="04", type="prg", segments="TILECHAR,TILECOL,TILETAG,MAIN,CHARSET,SPRITES,PATHING" ],
	[name="05", type="prg", segments="TABLES"],
	[name="06", type="prg", segments="MAP"],
	}

.segmentdef ZEROPAGE [start=$20]
.segmentdef LOADER [start=$0102]
.segmentdef SPRITES [start=spritebase]
.segmentdef CHARSET [start=charsetaddr]
.segmentdef MAP [start=$9000]
.segmentdef PATHING [startAfter="CHARSET"]
.segmentdef TILECHAR [startAfter="PATHING"]
.segmentdef TILECOL [startAfter="TILECHAR"]
.segmentdef TILETAG [startAfter="TILECOL"]
.segmentdef MAIN [startAfter="TILETAG"]
.segmentdef TABLES [start=$c000]
.segmentdef CBLOADER [start=$0c00]
.segmentdef CBLOADERINIT [startAfter="CBLOADER"]
.segmentdef SPLASHSCREEN [start=$9c00]
.segmentdef SPLASHCOLOR [start=$1000]
.segmentdef SPLASHBITMAP [start=$a000]

#import "config.s"
#import "loader.s"
#import "loaderinit.s"

#import "ultimate.s"
#import "sprites.s"
#import "myloader.s"
#import "myagsp.s"
#import "mydraw.s"
#import "mycontrol.s"
#import "myvic2.s"
#import "mylib.s"

        .segment TABLES
randperm: .byte 231, 229, 177, 253, 87, 152, 61, 165, 248, 149, 162, 163, 82, 103, 245, 101, 14, 227, 154, 188, 83, 217, 89, 171, 184, 173, 145, 207, 65, 222, 159, 43, 81, 236, 215, 233, 175, 90, 33, 164, 129, 84, 191, 247, 235, 232, 111, 119, 36, 12, 157, 230, 240, 150, 203, 225, 68, 27, 219, 112, 216, 244, 234, 183, 45, 47, 40, 220, 209, 86, 85, 67, 56, 98, 69, 126, 135, 214, 202, 3, 7, 70, 242, 137, 25, 146, 50, 213, 228, 106, 73, 74, 79, 210, 212, 15, 206, 44, 21, 221, 132, 121, 218, 99, 140, 250, 166, 104, 246, 64, 63, 194, 208, 0, 35, 197, 120, 136, 26, 57, 148, 241, 19, 100, 223, 51, 156, 115, 182, 185, 75, 97, 190, 127, 174, 169, 2, 243, 118, 199, 88, 71, 96, 200, 128, 31, 176, 72, 130, 94, 158, 55, 204, 186, 193, 147, 8, 114, 32, 237, 161, 54, 116, 107, 168, 123, 91, 1, 13, 196, 76, 189, 42, 16, 11, 155, 160, 41, 62, 254, 201, 141, 131, 52, 124, 144, 224, 58, 46, 125, 60, 78, 134, 139, 20, 252, 38, 187, 178, 138, 143, 28, 226, 18, 66, 108, 117, 49, 105, 5, 80, 167, 211, 151, 53, 133, 198, 179, 6, 92, 153, 170, 24, 205, 9, 39, 29, 59, 109, 102, 48, 113, 37, 34, 238, 172, 30, 180, 110, 10, 17, 4, 192, 239, 195, 142, 77, 249, 251, 122, 22, 93, 181, 23, 95
        .align 32
sprite_data_1: .fill 5*32,0
        .align 32
sprite_data_2: .fill sprite_order,0
sprite_data_2_order: .fill 32,i
sprite_data_2_clip: .fill 32,0
sprite_data_2_srcptr: .fill 32,0
bitset: .byte 1,2,4,8,16,32,64,128
bitclear: .byte 255-1,255-2,255-4,255-8,255-16,255-32,255-64,255-128

//f_main:	.text "01"

	.segment ZEROPAGE
	.zp {
row_map_ptr:	.word 0
ag_s:	.word 0     // ring slot (mydraw.s)
ag_mp:	.word 0     // map pointer
ag_pc:	.word 0     // tile char pointer
ag_pkc:	.word 0     // tile colour pointer
ag_ps:	.word 0     // screen pointer
ag_pk:	.word 0     // colour RAM pointer
temp:	.word 0
temp2:	.word 0
temp3:	.word 0
temp4:  .word 0
smooth_x: 	.word 0
smooth_y: 	.word 0
keyboard: .fill 8,0
player_dir: .byte 0
player_dir_nz: .byte 0
player_dx: .word 0
player_dy: .word 0
player_sword: .byte 0
player_anim_frame: .byte 0
player_anim_delay: .byte 0
sprite1_count: .byte 0
sprite2_count: .byte 0
sprite_logical_iterator: .byte 0
sprite_hw_iterator: .byte 0
control_index: .byte 0
rand_index: .byte 0
	}


.segment MAIN

main:
	jsr initvic2
	set8 sprite_data_2+sprite_global_xlo:#<10*8*32
	set8 sprite_data_2+sprite_global_xhi:#>10*8*32
	set8 sprite_data_2+sprite_global_ylo:#<245*8*32
	set8 sprite_data_2+sprite_global_yhi:#>245*8*32
	set8 rand_index:#0
	set8 sprite1_count:#0
	set8 sprite2_count:#0
	set8 player_dir_nz:#1
	ldy #0
	jsr sprite_alloc
	lda #0
	jsr sprite_init
	ldy #2
	jsr sprite_alloc
	lda #0
	jsr sprite_init
.var xx=3
.var yy=55
.var xxyy=(64*yy)+map
	ldx #xx
	ldy #yy
	set8 sprite_reader+1:#<xxyy
	set8 sprite_reader+2:#>xxyy
	jsr sprite_from_tile
	jsr control_player     // place the camera
	jsr exec_controllers
	jsr exec_animations
	jsr clip_sprites
	jsr ag_init            // draw the ring, start the raster IRQs
forever:
    jsr readkb
	jsr control_player
	jsr exec_controllers
	jsr exec_animations
	jsr clip_sprites       // sprites sliding in at the top edge
	jsr scroll_update      // draw newly exposed map edges
	jsr ag_commit_frame    // hand position + sprites to the IRQ, wait a frame
	jmp forever
//	jmp ($300)

