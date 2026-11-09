; repository version 194, built on Thu, 24 Nov 2022 10:56:24 +0100 for project "loader" using
; make PLATFORM=c64 prg INSTALL=1000 RESIDENT=0200 ZP=e0 PROJECT=

; configuration
config_ALLOW_2_MHZ_ON_C128      = 0
config_DECOMPRESSOR             = 12; ZX0
config_DIRTRACK                 = 18
config_DIRTRACK81               = 40
config_END_ADDRESS_API          = 0
config_FILENAME_MAXLENGTH       = 16
config_FILE_EXISTS_API          = 0
config_INTERNAL                 = 0
config_LOAD_COMPD_API           = 1
config_LOAD_RAW_API             = 1
config_LOAD_TO_API              = 0
config_LOAD_UNDER_D000_DFFF     = 0
config_LOAD_VIA_KERNAL_FALLBACK = 0
config_MEM_DECOMP_API           = 0
config_MEM_DECOMP_TO_API        = 0
config_NTSC_COMPATIBILITY       = 0
config_ONLY_1541_AND_COMPATIBLE = 0
config_PREFER_SPEED_OVER_SIZE   = 0
config_UNINSTALL_API            = 0

; status codes
status_OK                       = $00
status_DEVICE_INCOMPATIBLE      = $fb
status_TOO_MANY_DEVICES         = $fc
status_GENERIC_KERNAL_ERROR     = $fd
status_DEVICE_NOT_PRESENT       = $fe
status_FILE_NOT_FOUND           = $ff

; zeropage $e0-$f0
loader_zp_first                 = $e0
loadaddrlo                      = $e0
loadaddrhi                      = $e1
loader_zp_last                  = $ef

; install $1000-$2b53
install                         = $1000

; resident $0200-$0407
loadraw                         = $0200
loadcompd                       = $020e
