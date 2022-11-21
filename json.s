; asmjson
;
; Copyright 2022 Mikolaj Kuranowski
; SPDX-License-Identifier: MIT

BITS 64
DEFAULT REL

global json_parse
global json_dealloc

extern getc
extern ungetc
extern perror
extern abort
extern realloc
extern free
extern strtol
extern strtod

%define ERR_UNEXPECTED_CHAR -1
%define ERR_NUMBER_TOO_LONG -2
%define ERR_INVALID_NUMBER -3
%define ERR_INVALID_STRING -4

%define KIND_NULL 0
%define KIND_BOOL 1
%define KIND_INTEGER 2
%define KIND_DOUBLE 3
%define KIND_STRING 4
%define KIND_ARRAY 5
%define KIND_OBJECT 6

; json_array structure
%define json_array__size 16
%define json_array_arr 0
%define json_array_len 8

; json_object structure
%define json_object__size 16
%define json_object_arr 0
%define json_object_len 8

; json_value structure
%define json_value__size 24
%define json_value_kind 0
%define json_value_bool 8
%define json_value_int 8
%define json_value_double 8
%define json_value_string 8
%define json_value_array 8
%define json_value_array_arr 8
%define json_value_array_len 16
%define json_value_object 8
%define json_value_object_arr 8
%define json_value_object_len 16

; json_object_entry structure
%define json_object_entry__size 32
%define json_object_entry_value 0
%define json_object_entry_key 24

section .data
str_ungetc:	db "ungetc"


section .text

; =============================================
; Macro `bool is_whitespace(int ch)`
;
; Arguments:
; rax: ch
;
; Returns:
; rcx: ch is whitespace
;
; Clobbers:
; r11
%macro is_whitespace 0
	mov r11, 1
	mov rcx, 0
	cmp rax, 0x20  ; ' '
	cmove rcx, r11
	cmp rax, 0x0A  ; '\n'
	cmove rcx, r11
	cmp rax, 0x0D  ; '\r'
	cmove rcx, r11
	cmp rax, 0x09  ; '\t'
	cmove rcx, r11
%endmacro

; =============================================
; Macro `bool is_control(int ch)`
;
; Arguments:
; rax: ch
;
; Returns:
; rcx: ch is control (0x00~0x1F and 0x7F)
;
; Clobbers:
; r11
%macro is_control 0
	mov r11, 1
	mov rcx, 0
	cmp rax, 0x7F
	cmove rcx, r11
	cmp rax, 0x1F
	cmovle rcx, r11
%endmacro

; =============================================
; Macro `bool is_int(int ch)`
;
; Arguments:
; rax: ch
;
; Returns:
; rcx: ch is in ascii range [0-9] or '-'
;
; Clobbers:
; r11
%macro is_int 0
	mov r11, 0
	mov rcx, 1
	cmp rax, 0x30  ; 0
	cmovl rcx, r11
	cmp rax, 0x39  ; 9
	cmovg rcx, r11
	mov r11, 1
	cmp rax, 0x2D ; -
	cmove rcx, r11
%endmacro

; =============================================
; Macro `bool is_float(int ch)`
;
; Arguments:
; rax: ch
;
; Returns:
; rcx: ch is '.', '-', '+', 'e', or 'E'
;
; Clobbers:
; r11
%macro is_float 0
	mov r11, 1
	mov rcx, 0
	cmp rax, 0x2E  ; .
	cmove rcx, r11
	cmp rax, 0x2D  ; -
	cmove rcx, r11
	cmp rax, 0x2B  ; +
	cmove rcx, r11
	cmp rax, 0x65  ; e
	cmove rcx, r11
	cmp rax, 0x45  ; E
	cmove rcx, r11
%endmacro

; =============================================
; Macro `_Noreturn exit_perror(char* what)`
;
; Calls perror(what) and then abort()
%macro exit_perror 1
	mov rdi, %1
	call perror wrt ..plt
	call abort wrt ..plt
%endmacro

; =============================================
; Procedure `void skip_whitespace(FILE* stream)`
;
; Arguments:
; rdi: stream
;
; Only conforms to the x86_64 calling convention
skip_whitespace:
	push rdi

.loop:
	mov rdi, [rsp]
	call getc wrt ..plt

	is_whitespace
	cmp rcx, 0
	jne .loop

	; Last charachter was not whitespace - unget it
	push rax
	mov rdi, rax
	mov rsi, [rsp+8]
	call ungetc wrt ..plt

	; Compare whether ungetc returned the same thing as getc -
	; If no it means that ungetc failed
	cmp rax, [rsp]
	jne .fail
	lea rsp, [rsp+16]  ; `pop rdi` & `pop rax`
	ret

.fail:
	exit_perror str_ungetc

; =============================================
; Procedure `int peek_stream(FILE* stream)`
;
; Arguments:
; rdi: stream
;
; Returns:
; rax: next charachter that getc would return
;
; Only conforms to the x86_64 calling convention
peek_stream:
	push rdi
	call getc wrt ..plt
	push rax

	mov rdi, rax
	mov rsi, [rsp+8]
	call ungetc wrt ..plt

	cmp rax, [rsp]
	jne .fail

	lea rsp, [rsp+16]  ; `pop rdi` & `pop rax`
	ret

.fail:
	exit_perror str_ungetc

; =============================================
; Procedure `int parse_null(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_null:
	push rsi
	push rdi

	call getc wrt ..plt
	cmp rax, 0x6E  ; n
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x75  ; u
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x6C  ; l
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x6C  ; l
	jne .unexpected

	lea rsp, [rsp+8]  ; pop rdi
	pop rsi

	mov dword[rsi+json_value_kind], KIND_NULL
	mov rax, 0
	ret

.unexpected:
	mov rax, ERR_UNEXPECTED_CHAR
	ret

; =============================================
; Procedure `int parse_true(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_true:
	push rsi
	push rdi

	call getc wrt ..plt
	cmp rax, 0x74  ; t
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x72  ; r
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x75  ; u
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x65  ; e
	jne .unexpected

	lea rsp, [rsp+8]  ; pop rdi
	pop rsi

	mov dword[rsi+json_value_kind], KIND_BOOL
	mov byte[rsi+json_value_bool], 1
	mov rax, 0
	ret

.unexpected:
	mov rax, ERR_UNEXPECTED_CHAR
	ret


; =============================================
; Procedure `int parse_false(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_false:
	push rsi
	push rdi

	call getc wrt ..plt
	cmp rax, 0x66  ; f
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x61  ; a
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x6C  ; l
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x73  ; s
	jne .unexpected

	mov rdi, [rsp]
	call getc wrt ..plt
	cmp rax, 0x65  ; e
	jne .unexpected

	lea rsp, [rsp+8]  ; pop rdi
	pop rsi

	mov dword[rsi+json_value_kind], KIND_BOOL
	mov byte[rsi+json_value_bool], 0
	mov rax, 0
	ret

.unexpected:
	mov rax, ERR_UNEXPECTED_CHAR
	ret

; =============================================
; Procedure `int parse_string(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Locals:
; rbx: allocated string address
; r12: string length
; r13: string capacity
; r14: char to append to the buffer
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_string:
	enter 48, 0

	; Store callee-saved registers
	mov [rsp+40], rbx
	mov [rsp+32], r12
	mov [rsp+24], r13
	mov [rsp+16], r14
	; Store arguments
	mov [rsp+8], rsi
	mov [rsp], rdi

	; Clear string-building data
	mov rbx, 0
	mov r12, 0
	mov r13, 0

	; Assert that the stream starts with '"'
	call getc wrt ..plt
	cmp rax, 0x22  ; "
	jne .unexpected

	; Consume charachters
.loop:
	mov rdi, [rsp]
	call getc wrt ..plt

	; Break out of the loop once ending " is seen
	cmp rax, 0x22  ; "
	je .completed

	; Special processing for escaped chars
	cmp rax, 0x5C  ; backslash
	je .escaped

	; Control chars are not allowed
	is_control
	test rcx, rcx
	jnz .unexpected

	; Default to just append a char into string
	mov r14, rax
.append:
	cmp r12, r13
	jl .append_no_realloc

	; Calculate new capacity
	mov r11, 8  ; Initial capacity
	sal r13, 1
	cmovz r13, r11

	; Actually reallocate
	mov rdi, rbx
	mov rsi, r13
	call realloc wrt ..plt
	mov rbx, rax

.append_no_realloc:
	mov byte[rbx+r12], r14b
	inc r12
	jmp .loop

.escaped:
	; Get next char
	; FIXME: Handle \uXXXX escapes
	mov rdi, [rsp]
	call getc wrt ..plt
	mov r14, rax

	cmp rax, 0x22  ; "
	je .append

	cmp rax, 0x5C  ; backslash
	je .append

	cmp rax, 0x2F  ; /
	je .append

	mov r14, 0x08  ; \b
	cmp rax, 0x62  ; b
	je .append

	mov r14, 0x0C  ; \f
	cmp rax, 0x66  ; f
	je .append

	mov r14, 0x0A  ; \n
	cmp rax, 0x6E  ; n
	je .append

	mov r14, 0x0D  ; \r
	cmp rax, 0x72  ; r
	je .append

	mov r14, 0x09  ; \t
	cmp rax, 0x74  ; t
	je .append

.invalid_str:
	; Restore callee-saved registers
	mov rbx, [rsp+40]
	mov r12, [rsp+32]
	mov r13, [rsp+24]
	mov r14, [rsp+16]
	leave
	mov rax, ERR_INVALID_STRING
	ret

.completed:
	; Append a final null byte (unless the string is null)
	; See if a reallocation is required
	cmp r12, r13
	jl .null_byte_no_realloc

	; Calculate new capacity
	inc r13

	; Actually reallocate
	mov rdi, rbx
	mov rsi, r13
	call realloc wrt ..plt
	mov rbx, rax

.null_byte_no_realloc:
	mov byte[rbx+r12], 0
	inc r12

	; Save the string to passed json_value
	mov rsi, [rsp+8]
	mov dword[rsi+json_value_kind], KIND_STRING
	mov qword[rsi+json_value_string], rbx

	; Restore callee-saved registers
	mov rbx, [rsp+40]
	mov r12, [rsp+32]
	mov r13, [rsp+24]
	mov r14, [rsp+16]
	leave
	mov rax, 0
	ret

.unexpected:
	; Deallocate the string buffer
	test rbx, rbx
	jz .unexpected_ret

	mov rdi, rbx
	call free wrt ..plt

.unexpected_ret:
	; Restore callee-saved registers
	mov rbx, [rsp+40]
	mov r12, [rsp+32]
	mov r13, [rsp+24]
	mov r14, [rsp+16]
	leave
	mov rax, ERR_UNEXPECTED_CHAR
	ret

; =============================================
; Procedure `int parse_number(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Locals:
; [rsp+288]: value
; [rsp+280]: stream
; [rsp+272]: saved rbx
; [rsp+264]: saved r12
; [rsp+256]: `end` pointer, as returned by strtol/strtod
; [rsp]..[rsp+255]: buffer for chars
;
; rbx: length of saved chars
; r12: is_int flag
; r13: ?
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_number:
	enter 296, 0
	; Save calee-saved registers
	mov [rsp+288], rsi
	mov [rsp+280], rdi
	mov [rsp+272], rbx
	mov [rsp+264], r12
	; Initialize local variables
	mov rbx, 0
	mov r12, 1

.loop:
	; Peek at the current char
	mov rdi, [rsp+280]
	call peek_stream

	; If this char can be used in integer literals - append it
	is_int
	test rcx, rcx
	jnz .append

	; If this char can be used in float literals - append it,
	; and mark this number as non-integer
	is_float
	test rcx, rcx
	jz .end  ; Char non usable in number literals
	mov r12, 0  ; Mark this number as non-integer

.append:
	; Ensure no overflows
	cmp rbx, 256
	jae .overflow

	; Actually get the char
	mov rdi, [rsp+280]
	call getc wrt ..plt

	mov byte[rsp+rbx], al
	inc rbx
	jmp .loop
.end:
	; Append a null-terminator, ensuring no overflow occur
	cmp rbx, 256
	jae .overflow
	mov byte[rsp+rbx], 0

	; Check whether we deal with a float or an integer
	test r12, r12
	jz .as_float

.as_int:
	; Parse the integer using strtol
	mov rdi, rsp
	lea rsi, [rsp+256]
	mov rdx, 10
	call strtol wrt ..plt
	jmp .save

.as_float:
	; Parse the float using strtod
	mov rdi, rsp
	lea rsi, [rsp+256]
	call strtod wrt ..plt
	movq rax, xmm0

.save:
	; Check whether all of the number was parsed -
	; that is (end_from_strtoX - start) == str_len
	mov rcx, [rsp+256]
	sub rcx, rsp
	cmp rcx, rbx
	jne .invalid_number

	; Finally, update data in `value` struct
	mov rsi, [rsp+288]
	; Update the kind
	mov rcx, KIND_INTEGER
	mov rdx, KIND_DOUBLE
	test r12, r12
	cmovz rcx, rdx
	mov dword[rsi+json_value_kind], ecx
	; Update the value
	mov qword[rsi+json_value_int], rax

	; Return
	mov rax, 0
	; Restore calee-saved registers
	mov rbx, [rsp+272]
	mov r12, [rsp+264]
	leave
	ret

.overflow:
	mov rax, ERR_NUMBER_TOO_LONG
	; Restore calee-saved registers
	mov rbx, [rsp+272]
	mov r12, [rsp+264]
	leave
	ret

.invalid_number:
	mov rax, ERR_INVALID_NUMBER
	; Restore calee-saved registers
	mov rbx, [rsp+272]
	mov r12, [rsp+264]
	leave
	ret

; =============================================
; Procedure `int parse_array(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Locals:
; rbx: pointer to allocated array
; r12: array length
; r13: array capacity
; [rsp+40]: json_value only used when deallocating on failure
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_array:
	enter 64, 0
	mov [rsp+32], r13
	mov [rsp+24], r12
	mov [rsp+16], rbx
	mov [rsp+8], rsi
	mov [rsp], rdi

	; Initialize locals
	mov rbx, 0
	mov r12, 0
	mov r13, 0

	; Ensure the first charachter is a ']'
	call getc wrt ..plt
	cmp rax, 0x5B  ; [
	jne .unexpected

	; Skip whitespace
	mov rdi, [rsp]
	call skip_whitespace

	; Fast path for empty arrays
	mov rdi, [rsp]
	call peek_stream
	cmp rax, 0x5D  ; ]
	je .done

	; Consume elements of the array
.loop:
	; Grow the array
	cmp r12, r13
	jl .loop_parse
	mov rcx, 8  ; Initial capacity
	sal r13, 1
	cmovz r13, rcx

	; Change the capacity to bytes
	mov rax, r13
	mov rcx, json_value__size
	mul rcx

	; Realloc the array
	mov rdi, rbx
	mov rsi, rax
	call realloc wrt ..plt
	mov rbx, rax

.loop_parse:
	; Calculate the offset to current element
	mov rax, r12
	mov rcx, json_value__size
	mul rcx
	lea rsi, [rbx+rax]
	mov rdi, [rsp]  ; Parse an element
	call json_parse

	test rax, rax  ; Abort if parsing failed
	jnz .deallocate
	inc r12

	; json_parse skips whitespace after the element

	; Parse either a ',' (and continue looping); or a ']' and return the array
	mov rdi, [rsp]
	call getc wrt ..plt

	cmp rax, 0x2C  ; ,
	je .loop

	cmp rax, 0x5D  ; ]
	jne .unexpected

.done:
	mov rsi, [rsp+8]
	mov dword[rsi+json_value_kind], KIND_ARRAY
	mov qword[rsi+json_value_array_arr], rbx
	mov qword[rsi+json_value_array_len], r12

	mov rax, 0
	; Restore calee-saved registers
	mov r13, [rsp+32]
	mov r12, [rsp+24]
	mov rbx, [rsp+16]
	leave
	ret

.unexpected:
	mov rax, ERR_UNEXPECTED_CHAR

.deallocate:
	test rbx, rbx
	jz .ret

	; Deallocated whatever was parsed up to the error
	push rax
	lea rdi, [rsp+48]
	mov dword[rdi+json_value_kind], KIND_ARRAY
	mov qword[rdi+json_value_array_arr], rbx
	mov qword[rdi+json_value_array_len], r12
	call json_dealloc
	pop rax

.ret:
	; Restore calee-saved registers
	mov r13, [rsp+32]
	mov r12, [rsp+24]
	mov rbx, [rsp+16]
	leave
	ret

; =============================================
; Procedure `int parse_object(FILE* stream, struct json_value* value)`
;
; Arguments:
; rdi: stream
; rsi: value
;
; Locals:
; rbx: pointer to allocated array of key-value pairs
; r12: array length
; r13: array capacity
; r14: pointer to currently parsed entry
;
; [rsp]: dummy json_value object used to parse keys & deallocate parsed data on error
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
parse_object:
	enter 72, 0
	mov [rsp+64], r14
	mov [rsp+56], r13
	mov [rsp+48], r12
	mov [rsp+40], rbx
	mov [rsp+32], rsi
	mov [rsp+24], rdi

	; Initialize locals
	mov rbx, 0
	mov r12, 0
	mov r13, 0
	mov r14, 0

	; Ensure the first charachter is a '{'
	call getc wrt ..plt
	cmp rax, 0x7B  ; {
	jne .unexpected

	; Skip whitespace
	mov rdi, [rsp+24]
	call skip_whitespace

	; Fast path for empty objects
	mov rdi, [rsp+24]
	call peek_stream
	cmp rax, 0x7D  ; }
	je .done

	; Consume elements of the array
.loop:
	; Grow the array
	cmp r12, r13
	jl .loop_parse_key
	mov rcx, 8  ; Initial capacity
	sal r13, 1
	cmovz r13, rcx

	; Change the capacity to bytes
	mov rax, r13
	mov rcx, json_value__size
	mul rcx

	; Realloc the array
	mov rdi, rbx
	mov rsi, rax
	call realloc wrt ..plt
	mov rbx, rax

.loop_parse_key:
	; Calculate the offset to current element
	mov rax, r12
	mov rcx, json_object_entry__size
	mul rcx
	lea r14, [rbx+rax]

	; Zero-initialize the entry - so that nested elements can be deallocated on failure
	mov dword[r14+json_value_kind], KIND_NULL
	mov qword[r14+json_object_entry_key], 0

	; Parse the key
	mov rdi, [rsp+24]
	call skip_whitespace

	mov rdi, [rsp+24]
	mov rsi, rsp
	call parse_string
	test rax, rax
	jnz .deallocate

	; Set the key
	mov rsi, [rsp+json_value_string]
	mov qword[r14+json_object_entry_key], rsi

	; Allow space before ':'
	mov rdi, [rsp+24]
	call skip_whitespace

.loop_parse_value:
	; Parse the ':'
	mov rdi, [rsp+24]
	call getc wrt ..plt
	cmp rax, 0x3A  ; :
	jne .unexpected

	; Parse the value
	mov rdi, [rsp+24]
	lea rsi, [r14+json_object_entry_value]
	call json_parse
	test rax, rax
	jnz .deallocate
	inc r12

	; Parse either a ',' (and continue looping); or a '}' and return the array
	mov rdi, [rsp+24]
	call getc wrt ..plt

	cmp rax, 0x2C  ; ,
	je .loop

	cmp rax, 0x7D  ; }
	jne .unexpected

.done:
	mov rsi, [rsp+32]
	mov dword[rsi+json_value_kind], KIND_OBJECT
	mov qword[rsi+json_value_object_arr], rbx
	mov qword[rsi+json_value_object_len], r12

	mov rax, 0
	; Restore calee-saved registers
	mov r14, [rsp+64]
	mov r13, [rsp+56]
	mov r12, [rsp+48]
	mov rbx, [rsp+40]
	leave
	ret

.unexpected:
	mov rax, ERR_UNEXPECTED_CHAR

.deallocate:
	test rbx, rbx
	jz .ret

	push rax
	; Check whether we failed when parsing an entry, or after
	; If it's the first, then r12 needs to be incremented to properly deallocate the
	; not-yet-parsed entry.
	; To actually check the following comparison is requried:
	; r14 >= (rbx + r12*sizeof(json_object_entry))
	mov rax, r12
	mov rcx, json_object_entry__size
	mul rcx
	lea rax, [rax+rbx]
	lea r11, [r12+1]
	cmp r14, rax
	cmovae r12, r11

	; Deallocated whatever was parsed up to the error
	lea rdi, [rsp+8]
	mov dword[rdi+json_value_kind], KIND_OBJECT
	mov qword[rdi+json_value_object_arr], rbx
	mov qword[rdi+json_value_object_len], r12
	call json_dealloc
	pop rax

.ret:
	; Restore calee-saved registers
	mov r14, [rsp+64]
	mov r13, [rsp+56]
	mov r12, [rsp+48]
	mov rbx, [rsp+40]
	leave
	ret

; =============================================
; int json_parse(FILE* stream, struct json_value* value)
;
; Arguments:
; rdi: stream
; rsi: value
;
; Returns:
; rax: non-zero if parsing was not succesful
;
; Only conforms to the x86_64 calling convention
json_parse:
	push rsi
	push rdi

	call skip_whitespace

	mov rdi, [rsp]
	call peek_stream

	; Prepare arguments for a parse_XXX call
	mov rdi, [rsp]
	mov rsi, [rsp+8]

	; Switch on the peeked char
	cmp rax, 0x7B  ; {
	je .obj
	cmp rax, 0x5B  ; [
	je .arr
	cmp rax, 0x22  ; "
	je .str
	cmp rax, 0x74  ; t
	je .true
	cmp rax, 0x66  ; f
	je .false
	cmp rax, 0x6E  ; n
	je .null

	; Numbers can begin with '.', '-' or '0-9': ascii 45, 46, 48, 49, ..., 57
	sub rax, 45
	cmp rax, 2  ; Fail if it's a '/' (ascii 47)
	je .unexpected
	cmp rax, 12
	ja .unexpected

.number:
	call parse_number
	jmp .end

.obj:
	call parse_object
	jmp .end

.arr:
	call parse_array
	jmp .end

.str:
	call parse_string
	jmp .end

.true:
	call parse_true
	jmp .end

.false:
	call parse_false
	jmp .end

.null:
	call parse_null
	jmp .end

.unexpected:
	mov rax, ERR_UNEXPECTED_CHAR
	lea rsp, [rsp+16]  ; `pop rdi` & `pop rsi`
	ret

.end:
	push rax
	mov rdi, [rsp+8]
	call skip_whitespace
	pop rax
	lea rsp, [rsp+16]  ; `pop rdi` & `pop rsi`
	ret

; =============================================
; void json_dealloc(struct json_value* value)
;
; Arguments:
; rdi: value
;
; Locals:
; r12: pointer to the current deallocated array/object entry (iterator)
; r13: pointer past the end of deallocated array/object entry (.end() iterator)
; [rsp]: value
;
; Only conforms to the x86_64 calling convention
json_dealloc:
	enter 24, 0
	mov [rsp+16], r12
	mov [rsp+8], r13
	mov [rsp], rdi

	mov eax, dword[rdi+json_value_kind]

	cmp eax, KIND_OBJECT
	je .obj

	cmp eax, KIND_ARRAY
	je .arr

	cmp eax, KIND_STRING
	jne .done

.str:
	; Load the address of the string
	mov rdi, qword[rdi+json_value_string]
	test rdi, rdi
	jz .done  ; Don't do anything if the address is NULL
	call free wrt ..plt

	mov rdi, [rsp]
	mov qword[rdi+json_value_string], 0

	jmp .done

.arr:
	; Load the address of the array
	mov r12, qword[rdi+json_value_array_arr]
	test r12, r12
	jz .done  ; Don't do anything if the array is NULL

	; Calculate the position of the end of the array
	mov rax, qword[rdi+json_value_array_len]
	mov rcx, json_value__size
	mul rcx
	lea r13, [r12+rax]

	; Check if there are elements to deallocate
	cmp r12, r13
	jae .arr_free

.arr_loop:
	; Deallocate the element at [r12]
	mov rdi, r12
	call json_dealloc

	; Move to the next element
	lea r12, [r12+json_value__size]

	; Check if the end of array was reached
	cmp r12, r13
	jb .arr_loop

.arr_free:
	; Deallocate the array itself
	mov rdi, [rsp]
	mov rdi, [rdi+json_value_array_arr]
	call free wrt ..plt

	; Set the array pointer and length to zero
	mov rdi, [rsp]
	mov qword[rdi+json_value_array_arr], 0
	mov qword[rdi+json_value_array_len], 0
	jmp .done

.obj:
	; Load the address of the object
	mov r12, qword[rdi+json_value_object_arr]
	test r12, r12
	jz .done  ; Don't do anything if the object is NULL

	; Calculate the position of the end of the object
	mov rax, qword[rdi+json_value_object_len]
	mov rcx, json_object_entry__size
	mul rcx
	lea r13, [rax+r12]

	; Check if there are elements to deallocate
	cmp r12, r13
	jae .obj_free

.obj_loop:
	; Deallocate the value at [r12]
	mov rdi, r12
	call json_dealloc

	; Deallocate the key
	mov rdi, [r12+json_object_entry_key]
	test rdi, rdi
	jz .obj_check_next

	call free wrt ..plt

.obj_check_next:
	; Move to the next element
	lea r12, [r12+json_object_entry__size]

	; Check if the end of array was reached
	cmp r12, r13
	jb .obj_loop

.obj_free:
	; Deallocate the object itself
	mov rdi, [rsp]
	mov rdi, [rdi+json_value_object_arr]
	call free wrt ..plt

	; Set the array pointer and length to zero
	mov rdi, [rsp]
	mov qword[rdi+json_value_object_arr], 0
	mov qword[rdi+json_value_object_len], 0

.done:
	mov r12, [rsp+16]
	mov r13, [rsp+8]
	leave
	ret
