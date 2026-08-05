; Build wrapper: ROSM_SAVE write-cache check as it was before the fix for
; upstream M2M issue #58. Expected to hang for two or more clean vdrives.
; See rosm_save_test.asm and rosm_save_test.py.

#define TESTMODE 1
#include "rosm_save_test.asm"
