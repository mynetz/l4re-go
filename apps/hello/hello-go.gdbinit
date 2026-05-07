# GDB helper for debugging apps/hello (hello-go) under QEMU's gdbstub.
#
# Used by `task apps:hello:gdb`. Loaded after the hello-go ELF symbols
# but BEFORE `target remote`, so we use pending breakpoints.
#
# QEMU's gdbstub exposes the entire VM (bootstrap, Fiasco, sigma0, moe,
# ned, then the hello-go task), so most of the breakpoints below will
# only become active once the L4Re loader has mapped the hello-go ELF
# into a fresh task at base 0x10010000.
#
# Symbols (current build):
#   0x100768a0  cpuinit                       (ELF entry point, set by -E cpuinit)
#   0x100751a0  runtime.rt0_amd64_tamago      (cpuinit JMP target)
#   0x100752a0  runtime.settls.abi0           (calls runtime/goos.SetTLSUser)
#   0x100769a0  setTLSUser                    (overlay's set_fs_base IPC)
#   0x10045740  runtime.osinit
#   0x1004a520  runtime.schedinit
#   0x1004c620  runtime.mstart0
#   0x10073c20  runtime.mstart.abi0
#   0x100493c0  runtime.main
#   0x100769e0  main.main
#   0x10076820  runtime/goos.Printk
#   0x10073fa0  runtime.abort.abi0            (runtime panic / TLS test failure)
#   0x10045920  runtime.exit
#
# Tip: type 'hello-help' inside gdb for a quick recap.

set confirm off
set pagination off
set print pretty on
set disassembly-flavor intel

# Don't let pending-breakpoint prompts block scripted runs.
set breakpoint pending on

# All breakpoints below are pending until the loader maps the ELF.
break *0x100768a0
commands
  silent
  printf "\n[gdb] cpuinit reached @ 0x%lx (rsp=0x%lx)\n", $rip, $rsp
end

break *0x100751a0
commands
  silent
  printf "[gdb] runtime.rt0_amd64_tamago reached\n"
end

break *0x100752a0
commands
  silent
  printf "[gdb] runtime.settls.abi0 entered\n"
end

break *0x100769a0
commands
  silent
  printf "[gdb] setTLSUser entered (about to issue set_fs_base IPC)\n"
end

break *0x10045740
commands
  silent
  printf "[gdb] runtime.osinit entered\n"
end

break *0x1004a520
commands
  silent
  printf "[gdb] runtime.schedinit entered\n"
end

break *0x1004c620
commands
  silent
  printf "[gdb] runtime.mstart0 entered\n"
end

break *0x100493c0
commands
  silent
  printf "[gdb] runtime.main entered\n"
end

break *0x100769e0
commands
  silent
  printf "[gdb] main.main reached -- Go user code is running!\n"
end

break *0x10045920
commands
  silent
  printf "[gdb] runtime.exit reached\n"
end

break *0x10073fa0
commands
  silent
  printf "[gdb] runtime.abort.abi0 reached -- runtime is panicking\n"
end

# Useful user-defined helpers.
define hello-help
  printf "Hello-go gdb cheat sheet\n"
  printf "  c            -- continue execution from QEMU's reset state\n"
  printf "  bt           -- backtrace at current stop\n"
  printf "  info reg     -- dump CPU registers\n"
  printf "  hello-where  -- decode current rip against known symbols\n"
  printf "  hello-pc-loop-check  -- sample rip a few times to detect a tight loop\n"
end

# Sample rip a few times -- useful for detecting a busy-wait hang.
# Type 'hello-pc-loop-check' after an interrupt (Ctrl-C) when the
# task appears stalled.
define hello-pc-loop-check
  printf "Sampling rip (run during a hang to detect a busy loop):\n"
  set $i = 0
  while $i < 10
    printf "  sample %d: rip=0x%lx  ", $i, $rip
    info symbol $rip
    stepi
    set $i = $i + 1
  end
end

define hello-where
  printf "rip=0x%lx  ", $rip
  info symbol $rip
end

printf "\nhello-go gdbinit loaded. Type 'hello-help' for tips.\n"
printf "Now connecting to QEMU gdbstub...\n\n"
