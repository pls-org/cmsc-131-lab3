; * SUBSYTEM Owner: Percie Louise Y. Samaniego
;
; fmt.asm - int_to_dec, integer to decimal text. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it writes nothing and returns
; 0, which makes line numbers print empty. Your job is to replace that with
; the conversion described below.
;
; The contract, from driver.c:
;
;       char *out                   [ebp+12]
;       int n                       [ebp+8]
;
;       int int_to_dec(int n, char *out)
;
; Write the decimal text of n into out, return the number of bytes written.
; No leading zeros except for n == 0, which is "0". No sign. No terminator.
; The caller provides a buffer at least 16 bytes.
;
; Requirements from the manual:
;
;   * Divide by ten repeatedly, collecting remainders, which come out
;     backwards.
;   * The stack does the reversal. Push each remainder, then pop them into
;     the output in order.
;   * The loop must be bottom-tested so that zero emits one digit. A
;     top-tested loop emits nothing for n == 0, which is the classic bug.
;   * Clear edx before every div. The div writes its remainder there.
;   * Preserve ebx, esi, edi, and ebp. Return the byte count in eax.
;   * No calls into the C standard library.
;
; The manual's loop:
;
;       mov ebx, 10
;       xor ecx, ecx              ; digit count
;   digit_loop:
;       mov edx, 0                ; clear before div, as always
;       div ebx                   ; eax = quotient, edx = remainder
;       add dl, '0'               ; remainder to ASCII
;       push edx                  ; stack reverses them for us
;       inc ecx
;       cmp eax, 0
;       jne digit_loop
;       ; now pop ecx digits into edi in the right order
;
; The driver never passes a negative. It does pass 0, for -c on a file
; with no matching line, and int_to_dec must print that as one digit.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _int_to_dec int_to_dec
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _int_to_dec

_int_to_dec:
        enter   0,0
        push    ebx                     ; preserve callee-saved ebx, esi, edi
        push    esi
        push    edi

        cld                             ; advance forward when writing with stosb
        mov     eax, [ebp+8]            ; eax = n (number to convert)
        mov     edi, [ebp+12]           ; edi = out (destination buffer)
                                        ; at this point given by lab manual
        mov     ebx, 10                 ; divisor for base-10 extraction
        xor     ecx, ecx                ; digit count = 0

.digit_loop:
        xor     edx, edx                ; clear edx before div (holds remainder)
        div     ebx                     ; eax = quotient, edx = remainder (last digit)
        add     dl, '0'                 ; convert digit to ASCII character
        push    edx                     ; push digit onto stack to reverse its order
        inc     ecx                     ; count++
        test    eax, eax                ; stop when quotient is 0 (handles n == 0)
        jne     .digit_loop

        mov     esi, ecx                ; save digit count to return later

.pop_loop:
        pop     eax                     ; pop digits back in left-to-right order
        stosb                           ; store al into [edi] and advance edi
        loop    .pop_loop               ; repeat for all ecx digits

        mov     eax, esi                ; return total bytes written

        pop     edi                     ; restore saved registers
        pop     esi
        pop     ebx
        leave
        ret
