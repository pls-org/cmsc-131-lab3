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
        enter   4,0                     ; [ebp-4] = token index i
        push    ebx
        push    esi
        push    edi

        cld                             ; repne scasb must scan forward

        ; Zero-initialize struct args *out before scanning tokens
        mov     ebx, [ebp+16]
        xor     eax, eax
        mov     [ebx], eax              ; out->flags = 0
        mov     [ebx+4], eax            ; out->pattern = NULL
        mov     [ebx+8], eax            ; out->path = NULL

        mov     dword [ebp-4], 1        ; start at argv[1] (skip program name)

.token_loop:
        mov     eax, [ebp-4]
        cmp     eax, [ebp+8]            ; signed check for full-int argc
        jge     .tokens_done

        mov     edx, [ebp+12]           ; argv
        mov     esi, [edx + eax*4]      ; esi = argv[i]

        ; A token starting with '-' followed by non-NUL is a flag group;
        ; a lone "-" is positional.
        cmp     byte [esi], '-'
        jne     .positional
        cmp     byte [esi+1], 0
        je      .positional

        inc     esi                     ; advance past leading '-'

.flag_loop:
        movzx   eax, byte [esi]         ; zero-extend so bytes > 127 return positive
        test    al, al
        jz      .next_token

        mov     edi, flag_chars
        mov     ecx, 5
        repne   scasb                   ; scan table for flag char in al
        jne     .return_exit            ; unknown flag: eax holds offending byte

        ; repne scasb decrements ecx on the hit as well, so index = 4 - ecx
        mov     edx, 4
        sub     edx, ecx
        mov     ecx, edx
        mov     edx, 1
        shl     edx, cl
        or      [ebx], edx              ; out->flags |= (1 << index)

        inc     esi
        jmp     .flag_loop

.positional:
        cmp     dword [ebx+4], 0
        jne     .check_path
        mov     [ebx+4], esi            ; first positional -> out->pattern
        jmp     .next_token

.check_path:
        cmp     dword [ebx+8], 0
        jne     .usage_error            ; third positional -> usage error
        mov     [ebx+8], esi            ; second positional -> out->path

.next_token:
        inc     dword [ebp-4]
        jmp     .token_loop

.tokens_done:
        cmp     dword [ebx+4], 0
        je      .usage_error
        cmp     dword [ebx+8], 0
        je      .usage_error

        xor     eax, eax                ; return 0 on success
        jmp     .return_exit

.usage_error:
        mov     eax, -1

.return_exit:
        pop     edi
        pop     esi
        pop     ebx
        leave
        ret
