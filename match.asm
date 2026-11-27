; Subsystem Owner: Samantha F. Mok

; match.asm - line_matches, substring search with case folding and word
; boundaries. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it always returns 0 (no
; match), which makes rengrep print nothing. Your job is to replace that
; with the search described below.
;
; The contract, from driver.c:
;
;       int line_matches(char *line, int linelen,
;                        char *pat, int patlen,
;                        int fold, int whole)
;
; so on the stack after a cdecl call:
;       [ebp+8]  = line
;       [ebp+12] = linelen
;       [ebp+16] = pat
;       [ebp+20] = patlen
;       [ebp+24] = fold
;       [ebp+28] = whole
;
; Return 1 in eax if pat occurs in line, 0 otherwise.
;
; Requirements from the manual:
;
;   * Use the x86 string instructions for the inner comparison. repe cmpsb
;     at minimum. A mov/cmp loop does not satisfy the activity.
;   * fold: compare case-insensitively WITHOUT modifying the buffer. Fold
;     in a register at comparison time. This path cannot use repe cmpsb
;     (it compares raw bytes), so a folding loop for that path is expected.
;   * whole: a match counts only when the byte before the match and the
;     byte after it are both non-word characters or absent. A failed
;     word-boundary check does NOT end the search. Keep scanning.
;   * The search bound is linelen - patlen, not linelen. Compare it with a
;     signed jump. When patlen is larger than linelen the difference is
;     negative. An unsigned jump reads it as enormous, and the scan runs
;     off the line into memory the process does not own and faults. This
;     is the Block 5 lesson.
;   * An empty pattern matches at every position, as it does in grep. A
;     rep prefix with ecx = 0 executes nothing and leaves the flags as they
;     were, so set ZF yourself before repe cmpsb. A bottom-tested folding
;     loop needs its own guard.
;   * Set cld explicitly. The direction flag persists across calls and
;     assuming it is clear is how a routine that works alone breaks when
;     called after something else.
;   * Preserve ebx, esi, edi, and ebp. Return in eax.
;   * No calls into the C standard library.
;
; Word characters are A-Z, a-z, 0-9, and _.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _line_matches line_matches
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .text
        global  _line_matches

_line_matches:
        enter   0,0
        pusha                           ; save all registers; popa restores them

        cld                             ; make string instructions go forward

        ; Work out the last place the pattern could start: linelen - patlen.
        ; If the pattern is longer than the line this is negative, so there
        ; is nowhere to look. js is a SIGNED test, so a negative result stops
        ; here. (An unsigned test would read it as a huge number and scan
        ; past the end of the line.)
        
        mov     eax, [ebp+12]           ; eax = linelen
        sub     eax, [ebp+20]           ; eax = linelen - patlen
        js      .no_match               ; negative: pattern too long, no match

        xor     ebx, ebx                ; ebx = start = 0 (where we try next)

.scan:
        ; Stop when start is past the last valid position (signed compare).
        mov     eax, [ebp+12]           ; eax = linelen
        sub     eax, [ebp+20]           ; eax = last valid start
        cmp     ebx, eax
        jg      .no_match               ; tried every position, no match

        ; Point esi at the pattern and edi at the line, at this start.
        mov     esi, [ebp+16]           ; esi = pattern
        mov     edi, [ebp+8]
        add     edi, ebx                ; edi = line + start
        mov     ecx, [ebp+20]           ; ecx = number of bytes to compare

        cmp     dword [ebp+24], 0       ; is -i on?
        jne     .fold_compare           ; yes: use the case-folding loop

        ; ---- Normal compare (no -i): repe cmpsb ----
        test    ecx, ecx                ; empty pattern: sets ZF so it counts
                                        ; as equal (repe does nothing at ecx=0)
        repe    cmpsb                   ; compare bytes while they are equal
        jne     .next                   ; a byte differed: try the next start
        jmp     .candidate              ; all bytes equal: we have a match

        ; ---- Compare with -i: one byte at a time, lowercased in registers.
        ; The text in memory is never changed. ----
.fold_compare:
        test    ecx, ecx                ; empty pattern: nothing to compare,
        jz      .candidate              ; so it matches
.fold_loop:
        mov     al, [esi]               ; al = next pattern byte
        mov     dl, [edi]               ; dl = next line byte
        inc     esi
        inc     edi

        cmp     al, 'A'                 ; if al is 'A'..'Z', make it lowercase
        jb      .al_done
        cmp     al, 'Z'
        ja      .al_done
        add     al, 32                  ; 'a' - 'A' = 32
.al_done:
        cmp     dl, 'A'                 ; same for dl
        jb      .dl_done
        cmp     dl, 'Z'
        ja      .dl_done
        add     dl, 32
.dl_done:
        cmp     al, dl
        jne     .next                   ; bytes differ: try the next start
        dec     ecx                     ; one fewer byte left to compare
        jnz     .fold_loop              ; more bytes: keep going

.candidate:
        ; The text matches at this start. Without -w we are done.
        cmp     dword [ebp+28], 0       ; is -w on?
        je      .found                  ; no: it's a match

        ; -w: the match must not touch a word character on either side.
        ; Check the byte BEFORE the match (skip if match is at line start).
        test    ebx, ebx
        jz      .check_after            ; start is 0: nothing before it
        mov     esi, [ebp+8]
        mov     al, [esi+ebx-1]         ; al = byte before the match
        call    .is_word
        jc      .next                   ; word character: reject, keep looking

.check_after:
        ; Check the byte AFTER the match (skip if match is at line end).
        mov     edx, ebx
        add     edx, [ebp+20]           ; edx = start + patlen = byte after
        cmp     edx, [ebp+12]
        je      .found                  ; match ends at end of line: OK
        mov     esi, [ebp+8]
        mov     al, [esi+edx]           ; al = byte after the match
        call    .is_word
        jc      .next                   ; word character: reject, keep looking

.found:
        popa                            ; restore registers
        mov     eax, 1                  ; return 1 = match
        leave
        ret

.next:
        inc     ebx                     ; move to the next start position
        jmp     .scan                   ; (a rejected match does not end
                                        ; the search)

.no_match:
        popa                            ; restore registers
        mov     eax, 0                  ; return 0 = no match
        leave
        ret

; .is_word: is the byte in al a word character (A-Z, a-z, 0-9, _)?
; Returns the answer in the carry flag: CF = 1 yes, CF = 0 no.
; Uses dl as scratch.
.is_word:
        cmp     al, '_'
        je      .word_yes
        cmp     al, '0'
        jb      .word_no                ; below '0': not a word character
        cmp     al, '9'
        jbe     .word_yes               ; '0'..'9'
        mov     dl, al
        or      dl, 0x20                ; make letters lowercase to test once
        cmp     dl, 'a'
        jb      .word_no
        cmp     dl, 'z'
        ja      .word_no
.word_yes:
        stc                             ; CF = 1
        ret
.word_no:
        clc                             ; CF = 0
        ret