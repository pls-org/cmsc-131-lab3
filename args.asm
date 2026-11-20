; * SUBSYTEM Owner: Percie Louise Y. Samaniego

; args.asm - parse_args, the command line to a flag set, a pattern, and a
; file name. Callable from C.
;
; This is your starting point: it assembles and links as-is, so the build
; works before you write any code. Right now it returns -1, which makes
; rengrep print its usage line for every command. Nothing else runs until
; this routine works, so write it first. It is the shortest of the four.
;
; The contract, from driver.c:
;
;       struct args *out            [ebp+16]
;       char **argv                 [ebp+12]
;       int argc                    [ebp+8]
;
;       int parse_args(int argc, char **argv, struct args *out)
;
;       struct args { int flags; char *pattern; char *path; };
;                     +0         +4             +8
;
;       FLAG_N = 1, FLAG_C = 2, FLAG_V = 4, FLAG_I = 8, FLAG_W = 16
;
; Fill out and return 0. Return -1 when the pattern or the file is missing,
; or when a third positional token appears. Return the offending character,
; as a positive number, on an unknown flag. The driver prints it.
;
; Requirements from the manual:
;
;   * A token whose first byte is '-' and whose second byte is not NUL is a
;     flag group, wherever it appears. -nvi is -n -v -i. "-" alone is not a
;     flag group.
;   * Every other token is positional. The first is the pattern, the second
;     is the file.
;   * Keep the flag characters in a table, in bit order, and find each one
;     with scasb. The bit is 1 shifted left by the table index. A chain of
;     cmp/je is the structure the rubric marks down.
;   * Set cld explicitly. scasb honours the direction flag.
;   * Preserve ebx, esi, edi, and ebp. Return in eax.
;   * No calls into the C standard library.
;

; Windows C puts a leading underscore on every exported name. Linux C does
; not. The Makefile passes -d ELF_TYPE on Linux. This block then respells
; the names below to match. asm_io.inc does the same for _asm_main in the
; bootcamp blocks. Leave this block alone.
%ifdef ELF_TYPE
  %define _parse_args parse_args
  section .note.GNU-stack noalloc noexec nowrite progbits
%endif

segment .data
flag_chars      db      'n', 'c', 'v', 'i', 'w'         ; bit 0 to bit 4

segment .text
        global  _parse_args

_parse_args:
        enter   4,0                     ; stack frame + 4B local [ebp-4] for loop index i
        push    ebx                     ; save callee-saved ebx, esi, and edi
        push    esi
        push    edi

        cld                             ; clear DF so repne scasb scans forward

        ; Zero-initialize struct args *out before scanning tokens
        mov     ebx, [ebp+16]           ; ebx = struct args *out
        xor     eax, eax                ; eax = 0
        mov     [ebx], eax              ; out->flags = 0
        mov     [ebx+4], eax            ; out->pattern = NULL
        mov     [ebx+8], eax            ; out->path = NULL

        mov     dword [ebp-4], 1        ; i = 1 (skip argv[0] program name)

.token_loop:
        mov     eax, [ebp-4]            ; eax = current token index i
        cmp     eax, [ebp+8]            ; compare i with argc (signed 32-bit int)
        jge     .tokens_done            ; exit loop when i >= argc

        mov     edx, [ebp+12]           ; edx = argv
        mov     esi, [edx + eax*4]      ; esi = argv[i] (current token string)

        ; A token starting with '-' followed by non-NUL is a flag group;
        ; a lone "-" is positional.
        cmp     byte [esi], '-'         ; does token start with '-'?
        jne     .positional             ; no -> treat as positional argument
        cmp     byte [esi+1], 0         ; is next byte NUL (lone "-")?
        je      .positional             ; yes -> treat lone "-" as positional

        inc     esi                     ; skip leading '-' to first flag char

.flag_loop:
        movzx   eax, byte [esi]         ; load flag byte (zero-extended for >127)
        test    al, al                  ; reached NUL terminator?
        jz      .next_token             ; yes -> done with this flag group

        mov     edi, flag_chars         ; edi = start of flag lookup table
        mov     ecx, 5                  ; ecx = table length (5 valid flags)
        repne   scasb                   ; scan table for al; ZF=1 on match
        jne     .return_exit            ; unknown flag -> return offending char in eax

        ; repne scasb decrements ecx on the hit as well, so index = 4 - ecx
        mov     edx, 4                  ; max table index (5 - 1)
        sub     edx, ecx                ; edx = matched flag index (0..4)
        mov     ecx, edx                ; cl = shift count for shl
        mov     edx, 1                  ; edx = base bit mask (1)
        shl     edx, cl                 ; edx = 1 << flag_index
        or      [ebx], edx              ; set flag bit in out->flags

        inc     esi                     ; advance to next flag char in token
        jmp     .flag_loop              ; repeat for next char in flag group

.positional:
        cmp     dword [ebx+4], 0        ; is out->pattern still NULL?
        jne     .check_path             ; no -> check out->path next
        mov     [ebx+4], esi            ; store first positional in out->pattern
        jmp     .next_token             ; advance to next argv token

.check_path:
        cmp     dword [ebx+8], 0        ; is out->path still NULL?
        jne     .usage_error            ; no -> 3rd positional is a usage error
        mov     [ebx+8], esi            ; store second positional in out->path

.next_token:
        inc     dword [ebp-4]           ; i++
        jmp     .token_loop             ; process next argv token

.tokens_done:
        cmp     dword [ebx+4], 0        ; is out->pattern missing?
        je      .usage_error            ; yes -> usage error
        cmp     dword [ebx+8], 0        ; is out->path missing?
        je      .usage_error            ; yes -> usage error

        xor     eax, eax                ; return 0 on success
        jmp     .return_exit            ; jump to function epilogue

.usage_error:
        mov     eax, -1                 ; return -1 on missing/extra operand

.return_exit:
        pop     edi                     ; restore callee-saved edi, esi, ebx
        pop     esi
        pop     ebx
        leave                           ; restore caller stack frame (ebp, esp)
        ret                             ; return to caller with status in eax
