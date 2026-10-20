; ============================================================================
; Д/З: a1 + a2 * a3
;   a1 — из файла "input.txt"
;   a2 — из аргумента командной строки
;   a3 — из консоли (stdin)
; Стандарт: System V ABI
; ============================================================================

section .data
    ; --- Сообщения (с переводом строки на конце) ---
    msg_dec      db "DEC: ", 0
    msg_hex      db "HEX: 0x", 0
    msg_bin      db "BIN: 0b", 0
    msg_nl       db 10, 0

    msg_err_arg  db "Error: a2 (argument) required!", 10, 0
    msg_err_ovf  db "Error: Overflow!", 10, 0
    msg_err_inv  db "Error: Invalid number!", 10, 0

    filename     db "input.txt", 0

    ; --- Буферы ---
    file_buf     times 32 db 0
    stdin_buf    times 32 db 0
    dec_buf      times 20 db 0
    hex_buf      times 20 db 0
    bin_buf      times 20 db 0

section .bss
    a1           resq 1
    a2           resq 1
    a3           resq 1
    result       resq 1

section .text
    global _start

_start:
    ; ---- 1. a1 из файла ----
    lea rdi, [filename]
    call read_file          ; возвращает rax = число, rdx = флаг ошибки
    test rdx, rdx
    jnz .err_inv
    mov [a1], rax

    ; ---- 2. a2 из аргументов ----
    mov rdi, [rsp + 16]     ; argv[1]
    test rdi, rdi
    jz .err_arg             ; нет аргумента — ошибка

    call str_len            ; rcx = длина строки
    mov rsi, rcx            ; rsi = длина
    call str_to_word        ; rax = число, rdx = флаг ошибки
    test rdx, rdx
    jnz .err_inv
    mov [a2], rax

    ; ---- 3. a3 из консоли ----
    mov rax, 0              ; sys_read
    xor rdi, rdi            ; stdin
    lea rsi, [stdin_buf]
    mov rdx, 32
    syscall
    
    mov rcx, rax            ; rcx = реально прочитанная длина
    lea rdi, [stdin_buf]
    mov rsi, rcx            ; rsi = длина
    call str_to_word
    test rdx, rdx
    jnz .err_inv
    mov [a3], rax

    ; ---- 4. a1 + a2 * a3 ----
    mov rax, [a2]
    mov rbx, [a3]
    mul rbx                 ; rdx:rax = a2 * a3

    test rdx, rdx
    jnz .err_ovf            ; переполнение (результат > 64 бит)

    add rax, [a1]
    jc .err_ovf             ; переполнение при сложении

    cmp rax, 65535          ; проверка, что влезает в 16 бит
    ja .err_ovf

    mov [result], rax

    ; ---- 5. Вывод результата ----
    ; DEC
    lea rdi, [msg_dec]
    call print_str
    mov rax, [result]
    call word_to_dec
    lea rdi, [dec_buf]
    call print_str
    lea rdi, [msg_nl]
    call print_str

    ; HEX
    lea rdi, [msg_hex]
    call print_str
    mov rax, [result]
    call word_to_hex
    lea rdi, [hex_buf]
    call print_str
    lea rdi, [msg_nl]
    call print_str

    ; BIN
    lea rdi, [msg_bin]
    call print_str
    mov rax, [result]
    call word_to_bin
    lea rdi, [bin_buf]
    call print_str
    lea rdi, [msg_nl]
    call print_str

    ; ---- Успешный выход ----
    mov rax, 60
    xor rdi, rdi
    syscall

; ============================================================
; Обработчики ошибок
; ============================================================
.err_arg:
    lea rdi, [msg_err_arg]
    call print_str
    jmp .exit_fail

.err_ovf:
    lea rdi, [msg_err_ovf]
    call print_str
    jmp .exit_fail

.err_inv:
    lea rdi, [msg_err_inv]
    call print_str

.exit_fail:
    mov rax, 60
    mov rdi, 1              ; код возврата 1 (ошибка)
    syscall

; ============================================================
; print_str: печать строки (заканчивается на 0)
; Вход: rdi = адрес строки
; ============================================================
print_str:
    push rsi
    push rdx
    push rax
    push rdi
    mov rsi, rdi
    xor rdx, rdx
.len:
    cmp byte [rsi + rdx], 0
    je  .write
    inc rdx
    jmp .len
.write:
    mov rax, 1              ; sys_write
    mov rdi, 1              ; stdout
    syscall
    pop rdi
    pop rax
    pop rdx
    pop rsi
    ret

; ============================================================
; read_file: чтение файла и конвертация
; Вход: rdi = имя файла
; Выход: rax = число, rdx = флаг ошибки (1 - ошибка)
; ============================================================
read_file:
    push rbx
    push rdi
    push rsi
    push rdx

    mov rax, 2              ; sys_open
    xor rsi, rsi            ; O_RDONLY
    xor rdx, rdx
    syscall
    test rax, rax
    js .fail
    mov rbx, rax            ; rbx = fd

    mov rax, 0              ; sys_read
    mov rdi, rbx
    lea rsi, [file_buf]
    mov rdx, 32
    syscall
    mov rcx, rax            ; rcx = реальная длина

    mov rax, 3              ; sys_close
    mov rdi, rbx
    syscall

    ; Обрезаем \n, если он есть в конце
    test rcx, rcx
    jz .fail
    cmp byte [file_buf + rcx - 1], 10
    jne .no_trim
    dec rcx
.no_trim:

    lea rdi, [file_buf]
    mov rsi, rcx            ; rsi = длина
    call str_to_word
    jmp .done

.fail:
    mov rdx, 1              ; флаг ошибки
.done:
    pop rdx
    pop rsi
    pop rdi
    pop rbx
    ret

; ============================================================
; str_len: вычисление длины строки
; Вход: rdi = адрес строки
; Выход: rcx = длина
; ============================================================
str_len:
    xor rcx, rcx
.loop:
    cmp byte [rdi + rcx], 0
    je  .done
    inc rcx
    jmp .loop
.done:
    ret

; ============================================================
; str_to_word: строка -> число
; Вход: rdi = адрес, rsi = длина
; Выход: rax = число, rdx = флаг ошибки (1 - ошибка)
; ============================================================
str_to_word:
    push rbx
    xor eax, eax            ; результат
    xor rbx, rbx            ; индекс
    xor r9d, r9d            ; счетчик цифр

.loop:
    cmp rbx, rsi
    jge .done

    movzx ecx, byte [rdi + rbx]
    cmp ecx, '0'
    jb  .done               ; не цифра -> конец (например \n)
    cmp ecx, '9'
    ja  .done               ; не цифра

    sub ecx, '0'
    imul rax, rax, 10
    add rax, rcx
    cmp rax, 65535
    ja  .fail               ; переполнение

    inc r9                  ; счетчик цифр
    inc rbx
    jmp .loop

.done:
    test r9, r9
    jz  .fail               ; ни одной цифры
    xor edx, edx            ; ошибки нет
    pop rbx
    ret

.fail:
    mov edx, 1              ; флаг ошибки
    pop rbx
    ret

; ============================================================
; word_to_dec: число -> строка DEC
; Вход: rax = число, rdi = куда писать
; ============================================================
word_to_dec:
    push rax
    push rbx
    push rdx
    push rsi
    mov r8, rdi             ; r8 = указатель на dec_buf
    lea rsi, [r8 + 19]
    mov byte [rsi], 0
    mov bx, 10
.loop:
    dec rsi
    xor dx, dx
    div bx
    add dl, '0'
    mov [rsi], dl
    test ax, ax
    jnz .loop
.copy:
    mov al, [rsi]
    mov [r8], al
    inc rsi
    inc r8
    test al, al
    jnz .copy
    pop rsi
    pop rdx
    pop rbx
    pop rax
    ret

; ============================================================
; word_to_hex: число -> строка HEX
; Вход: rax = число, rdi = куда писать
; ============================================================
word_to_hex:
    push rax
    push rbx
    push rdx
    push rsi
    mov r8, rdi
    lea rsi, [r8 + 19]
    mov byte [rsi], 0
    mov bx, 16
.loop:
    dec rsi
    xor dx, dx
    div bx
    cmp dl, 10
    jb  .digit
    add dl, 'A' - 10
    jmp .store
.digit:
    add dl, '0'
.store:
    mov [rsi], dl
    test ax, ax
    jnz .loop
.copy:
    mov al, [rsi]
    mov [r8], al
    inc rsi
    inc r8
    test al, al
    jnz .copy
    pop rsi
    pop rdx
    pop rbx
    pop rax
    ret

; ============================================================
; word_to_bin: число -> строка BIN
; Вход: rax = число, rdi = куда писать
; ============================================================
word_to_bin:
    push rax
    push rbx
    push rcx
    push rsi
    mov r8, rdi
    lea rsi, [r8 + 16]
    mov byte [rsi], 0
    
    mov bx, ax
    mov cx, 16
.loop:
    shl bx, 1
    mov al, '0'
    adc al, 0
    dec rsi
    mov [rsi], al
    dec cx
    jnz .loop
    
.copy:
    mov al, [rsi]
    mov [r8], al
    inc rsi
    inc r8
    test al, al
    jnz .copy
    pop rsi
    pop rcx
    pop rbx
    pop rax
    ret
