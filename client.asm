global _start

%include "socklib.inc"
%include "filelib.inc"

%define fileNotFound  0x00
%define fileFound     0x01
%define respCodeSz    6
%define defaultBuffSz 4000

section .data
  usage: db "usage: ./client <ip> <file request path> <destination path>", 0xa, 0x0
  .len: equ $ - usage

section .bss
  ;; Network Vars
  sockfd:        resd 1 ;;integer variable to hold socket file desc

  ;; File Vars
  fStrPtr:       resq 1 ;;Pointer to file cmd arg
  newfStrPtr:    resq 1 ;;Pointer to new file cmd arg
  new_f_fd:      resd 1 ;;Newly created file, fd
  fsize:         resd 1 ;;Size of file in Bytes
  brecvd:        resd 1 ;;number of bytes recv'd

  ;; Mem Alloc Vars
  initAddr:      resq 1 ;;initial addr of prog break (data seg end)
  currAddr:      resq 1 ;;current addr of prog break

  ;; ip Vars
  ipPtr:         resq  1
  ipInt:         resd  1

section .text

string_length:
  xor     rax, rax
  .loop:
  cmp     byte [rdi+rax], 0
  je      .end
  inc     rax
  jmp     .loop
  .end:
  ret

;; Convert IP cmd arg to int
;; rsi -> pointer to the string to convert
;; ipInt var contains net byte order ip addr by end
ipString_To_Int:
  xor    rbx, rbx    ; clear rbx

.next_octet:

  movzx  eax, BYTE [rsi]
  inc    rsi
  sub    al, '0'    ;; convert from ASCII to number
  imul   ebx, 10    ;; unsigned multiply by 10
  add    ebx, eax   ;; ebx = ebx*10 + eax
  cmp    BYTE [rsi], '.'  ;; check for octet delim
  je     .update
  cmp    BYTE [rsi], 0  ;; check for end of str
  je     .update
  jmp    .next_octet

  .update:
  mov    eax, ebx     ;; mov result into eax
  mov    edi, [ipInt] ;; get ip var
  cmp    edi, 0       ;; if edi (ipInt) == 0, then no rotate
  je     .iter1
  ror    edi, 8       ;; rotate right by $r8d bits

  .iter1:
  or     BYTE dil, al ;; update ip var
  mov    DWORD [ipInt], edi
  cmp    BYTE [rsi], 0 ;; test for end of str
  je     .done
  inc    rsi  ;; inc rsi to mov past '.'
  jmp    ipString_To_Int

  .done:
  ror    edi, 8  ;; alst rotate right by $r8d bits
  mov    DWORD [ipInt], edi ;; final ip var update
  ret



_start:
debug:
  nop
  nop
  nop

;;Make sure enough args passed
;----------------------------------------------------------------------
  mov     rsi, [rsp] ;; argc
  cmp     rsi, 4
  jnz     printUsage

;;Get the server IP
;----------------------------------------------------------------------
  mov     rsi, [rsp+16] ;; *argv[1]
  mov     QWORD [ipPtr], rsi

;;Get the file requested
;----------------------------------------------------------------------
  mov     rsi, [rsp+24] ;; *argv[2]
  mov     QWORD [fStrPtr], rsi

;;Get the file destination
;----------------------------------------------------------------------
  mov     rsi, [rsp+32] ;; *argv[3]
  mov     QWORD [newfStrPtr], rsi

;;create socket
;----------------------------------------------------------------------
  call    csocket
  test    ax, ax
  js      err
  mov     [sockfd], ax

;; Convert String IP to Network int
;----------------------------------------------------------------------
  mov     rsi, [ipPtr]
  call    ipString_To_Int
  test    dil, dil
  js      err


;;connect to server
;----------------------------------------------------------------------
  mov     rdi, [sockfd]
  mov     rsi, 0xE110     ;; User supplied port
  mov     edx, DWORD [ipInt] ;; User supplied IP
  call    cconnect
  test    ax, ax
  js      err

;;Get legth of filename to send
;----------------------------------------------------------------------
  mov     rdi, [fStrPtr]
  call    string_length
  push    rax ;; push file length

;;Send filename
;; rdi -> fd
;; rsi -> buffer
;; rdx -> buffer size
;; on ret, rax will contain # of bytes sent || -1 if error
;----------------------------------------------------------------------
send:
  mov     rax, 1
  mov     rdi, [sockfd]
  mov     rsi, [fStrPtr]
  pop     rdx ;; pop file length (see prev call)
  syscall
  test    ax, ax
  js      err ;; if <0 branch

;; Allocate memory for buffer
;; after syscall rax will contain addr || -1 for error
;----------------------------------------------------------------------
allocMem:

.getCurrBrk:
  mov     rax, 12 ;; sys_brk
  mov     rdi, 0  ;; 0 returns current heap break addr
  syscall
  mov     [initAddr], rax ;; update vars
  mov     [currAddr], rax

  ;; For now just alloc 1.5 KB

  ;; TODO
  ;; Increase size and add check to see if full size is needed

.alloc:
  mov     rax, 12 ;; sys_brk
  mov     rdi, [currAddr]
  add     rdi, 1500 ;; allocate 1500 bytes
  syscall
  mov     [currAddr], rax

;; Recv file found or file doesnt exist
;; rax -> read syscall
;; rdi -> fd
;; rsi -> buffer
;; rdx -> buffer size
;; on ret, rax will contain # of bytes read || -1 if error
;----------------------------------------------------------------------
recv:
  mov     rax, 0
  mov     rdi, [sockfd]   ;; sock fd w/ connection to server
  mov     rsi, [initAddr] ;; pointer to buffer
  mov     rdx, respCodeSz ;; response code size
  syscall
  test    ax, ax
  js      err

checkCode:
  cmp     BYTE [rsi], fileFound ;; check response code
  je      found ;; file found == 0x1
  jne     notFound ;; file NOT found == 0x0



found:

.stripFileSize:
  mov     DWORD eax, [rsi+2] ;; get dword in buff containing file size
  mov     DWORD [fsize], eax ;; save file size

;; Create new file to write downloaded file
;; If file already exists will truncate file
.createFile:
  mov     rdi, [newfStrPtr] ;; get file name
  call    fopen_create  ;; create file
  test    ax, ax
  js      err
  mov     DWORD [new_f_fd], eax ;; save new file fd

;; Recv network data from server
.recv:
  mov     rax, 0
  mov     rdi, [sockfd]      ;; sock fd w/ connection to server
  mov     rsi, [initAddr]    ;; pointer to buffer
  mov     rdx, defaultBuffSz ;; buffer size
  syscall
  test    ax, ax
  js      err

  ;; save number of bytes recv'd and update counter
  push    rax ;; push number of bytes recv'd
  mov     DWORD edx, [brecvd]
  add     eax, edx
  mov     DWORD [brecvd], eax

.writeToFile:
  mov     rax, 1 ;; write
  mov     rdi, [new_f_fd]
  mov     rsi, [initAddr]
  pop     rdx ;; pop number of bytes recv'd
  syscall
  test    ax, ax
  js      err ;; if <0 branch

.checkDone:
  mov     eax, [brecvd]
  mov     edx, [fsize]
  cmp     edx, eax
  jg      found.recv ;; if fsize > brecvd; more bytes to recv
  je      done ;; if fsize == brecvd; file transfer complete
  jb      err ;; if fsize < brecvd; error occured, too much data


notFound:
  nop
  nop
  nop


done:
  xor    rax,rax

;;Teardown
;----------------------------------------------------------------------
err:
  push   rax ;; save exit val

.closeSock:;; close socket
  mov  rax, 3
  mov  rdi, [sockfd]
  syscall

.closeFile:;; close file
  mov  rax, 3
  mov  rdi, [new_f_fd]
  syscall

.freeMem: ;; free allocated memory
  mov  rax, 12
  mov  rdi, [initAddr]
  syscall

  pop    rdi ;; pop exit val
  jmp    exit

printUsage:

  mov    rax, 1
  mov    rdi, 1
  mov    rsi, usage
  mov    edx, usage.len
  syscall

  ;; rax _> exit syscall
  ;; rdi -> return value
  ;; on syscall exits and returns passed value
exit:
  mov    rax, 60
  syscall
