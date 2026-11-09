//-------------------------------------------------------------------------------
// Covert Bitops Loadersystem V3.x, configuration
//-------------------------------------------------------------------------------

        // Conditionals

.var USETURBOMODE    = 1             //Can set to zero if you are not going to use
                                //SCPU/C128 fast mode

//#define INCLUDESAVE              //Comment out to remove save routines

        // Zeropage config

.var zpBase          = $02           //Base for zeropage vars

.var fileOpen        = zpBase
.var loadTempReg     = zpBase+1
.var loadBufferPos   = zpBase+2
.var fastLoadEor     = zpBase+3      //Needed for NTSC version of 2-bit protocol
.var zpLenLo         = zpBase+4      //For depackers & save
.var zpSrcLo         = zpBase+5
.var zpSrcHi         = zpBase+6
.var zpBitsLo        = zpBase+7
.var zpBitsHi        = zpBase+8
.var zpBitBuf        = zpBase+9
.var zpDestLo        = zpBase+10
.var zpDestHi        = zpBase+11

        // Non-zeropage memory defines// loadBuffer can be relocated if needed, but
        // note that all of $0200-$02ff cannot be used by your program with Kernal 
        // loading

.var loadBuffer      = $0200
.var ELoadHelper     = $0200
.var StopIrq         = $02a7
