;;
;;   syscall wrappers
;;
%ifndef FILELIB.INC
  %define FILELIB.INC

    ;;
    %define F_OK      0

    ;     modes
    ;O_RDONLY - read-only
    ;O_WRONLY - wirte-only
    ;O_RDWR   - read and write
    %define O_RDONLY  0
    %define O_WRONLY  1
    %define O_RDWR    2

    ;SEEK_SET - set file offset to offset
    ;SEEK_CUR - set file offset to current plus offset
    ;SEEK_END - set file offset to EOF plus offset
    %define SEEK_SET 0
    %define SEEK_CUR 1
    %define SEEK_END 2

    ;;   flags
    ;O_CREAT  - create file if file doesnt exists
    ;O_TRUNC  - truncate file
    ;O_APPEND - append to file
    %define O_CREAT  100o
    %define O_TRUNC  1000o
    %define O_APPEND 2000o

    ;; params:
    ;; rdi -> filename/filepath
    ;; on ret, rax will contain fd || -1 if error
    fopen:
      mov rax, 2
      ;;rdi-> passed param
      mov rsi, O_RDWR
      mov rdx, 0666o
      syscall
      ret

    ;; params:
    ;; rdi -> filename/filepath
    ;; on ret, rax will contain fd || -1 if error
    fopen_create:
      mov rax, 2
      ;;rdi-> passed param
      mov rsi, O_CREAT | O_TRUNC | O_WRONLY
      mov rdx, 0666o
      syscall
      ret
      ;; sys_access
      ;; uses F_OK mode to retrieve wether or not file exists
      ;; rdi -> char* of file
      ;; on ret, rax will return 0 if succesful and file exists || -1 if file does not exist
    fileaccess:
      mov rax, 21
      ;;rdi-> passed param
      mov rsi, F_OK
      syscall
      ret

    ;; struct stat -> 144 bytes
    ;; rdi-> char* filename
    ;; on ret will return size of file in bytes || -1 on error
    filesize:
      push   rbp      ;;save rbp
      mov    rbp, rsp ;;save stack pointer
      mov    rax, 4   ;;sys_stat
      ;;rdi-> passed param
      sub    rsp, 144 ;;allocate memory on stack for struct stat
      mov    rsi, rsp ;;rsi now points to alloc mem for struct stat
      syscall
      test   ax, ax
      js     .err
      mov    QWORD rax, [rsp+48] ;; save stat->st_size
      .err:
      leave  ;; leave will: mov rsp, rbp & pop rbp
      ret

%endif
