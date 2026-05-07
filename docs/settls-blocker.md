# What `settls` is for, and why Fiasco breaks it

This note explains, in detail, why iteration 2b's QEMU run faults inside
the Go runtime's TLS bring-up before `main.main` ever runs, why this
problem does not affect tamago's existing `user/linux` target, and what
the resolution looks like.

It is grounded in the sources cached at
`~/.cache/tamago-go/tamago-go1.26.2/` (the toolchain
`task tamago:ensure` materialises) and in
`sources/l4re/pkg/l4re-core/l4sys/include/` (after `task sources:sync`).

## 1. Why Go needs a per-thread "register" at all

The Go runtime tracks two things for every running OS thread:

- **`g`** — the current goroutine.
- **`m`** — the OS thread (the "machine") executing it.

These pointers must be reachable in O(1) from any function the runtime
emits, including assembly stubs, signal handlers, and stack-overflow
probes. That requires *thread-local storage*: a per-thread slot the
runtime can read with a single instruction without touching memory it
doesn't own.

On amd64, the canonical Linux convention is to put TLS at a fixed offset
in the `%fs` segment. Userspace code reads it as `%fs:<offset>`. The
kernel sets the per-thread `FS_BASE` MSR; on a context switch, the
kernel saves/restores that MSR per thread; the user-space code never has
to think about it.

Go on amd64 follows the SysV TLS convention with one twist: it stores
`g` at `%fs:-8` (Go calls this the "ELF -8(FS) convention" in
`sys_tamago_amd64.s` lines 165, 173). That single TLS slot is the
entire mechanism — `m` is reached as `g.m`, `p` as `g.m.p`, and so on.
Every Go program emits the equivalent of `MOVQ %fs:-8, BX` everywhere
it needs the current goroutine, transparently to user code.

So the runtime has **one job at startup**: arrange for `%fs:-8` to be a
valid load that yields a pointer to the running thread's `m.tls[0]`
slot. The act of setting `FS_BASE` to that address is what
`runtime·settls` exists to do.

## 2. `runtime·rt0_amd64_tamago`'s self-test

Reading
`~/.cache/tamago-go/tamago-go1.26.2/src/runtime/sys_tamago_amd64.s`
lines 17-56:

```asm
TEXT runtime·rt0_amd64_tamago(SB),NOSPLIT|NOFRAME|TOPFRAME,$0
    // ...g0 stack setup, CPUID feature detection...

    LEAQ    runtime·m0+m_tls(SB), DI       // DI = &m0.tls[0]
    CALL    runtime·settls(SB)              // ask "the OS" to make %fs:-8 == DI

    // store through it, to make sure it works
    get_tls(BX)                             // BX = MOVQ TLS, BX  (assembler magic for %fs:<TLS>)
    MOVQ    $0x123, g(BX)                   // write 0x123 to the TLS-relative g slot
    MOVQ    runtime·m0+m_tls(SB), AX        // read m0.tls[0] directly (NOT through %fs)
    CMPQ    AX, $0x123                      // do they match?
    JEQ     ok
    CALL    runtime·abort(SB)               // crash if not
ok:
    // ...rest of runtime startup...
```

The post-call test is non-negotiable. The runtime writes a sentinel
through the FS-relative path and reads it back through a direct
symbol-relative path. If `FS_BASE` was not installed correctly, the two
pointers refer to different memory and the comparison fails, so
`runtime.abort` is called.

In our crash log, the failure is one step earlier — the
`MOVQ $0x123, g(BX)` itself page-faults because `FS_BASE` is still 0
(the default), so `%fs:-8` becomes virtual address
`0xfffffffffffffff8`, which is not mapped in our task. We never reach
the comparison.

## 3. What `runtime·settls(DI)` actually does

`sys_tamago_amd64.s` lines 159-181:

```asm
TEXT runtime·settls(SB),NOSPLIT,$32
    MOVW    CS, AX
    ANDW    $3, AX            // CS & 3 = current privilege level (CPL)
    CMPQ    AX, $0
    JNE     application       // if CPL != 0, take the userspace path

    // --- ring-0 path ---
    ADDQ    $8, DI              // bias by 8 (Go uses %fs:-8 for g)
    MOVQ    DI, AX
    MOVQ    $IA32_MSR_FS_BASE, CX  // 0xC0000100
    MOVQ    $0x0, DX
    WRMSR                       // write 64-bit MSR: FS_BASE = AX (DI+8)
    RET

application:
    // --- userspace path ---
    ADDQ    $8, DI              // bias by 8
    MOVQ    DI, SI              // arg2 = base
    MOVQ    $0x1002, DI         // arg1 = ARCH_SET_FS
    MOVQ    $SYS_arch_prctl, AX // syscall number = 158 (Linux's arch_prctl)
    SYSCALL                     // ask "the OS" to set FS_BASE to base
    CMPQ    AX, $0xfffffffffffff001
    JLS     2(PC)               // if syscall returned an error, crash
    MOVL    $0xf1, 0xf1         // intentional fault -> abort
    RET
```

Two paths, one for each "environment" tamago expects to run in:

- **Ring 0** — bare-metal tamago. The CPU is yours. WRMSR is
  privileged, but you have privileges. You write `IA32_FS_BASE`
  directly. Done.
- **Ring 3** — userspace tamago. WRMSR would trap with #GP. So you ask
  the supervising kernel to do it for you. The mechanism is **the host
  kernel's syscall ABI for setting FS_BASE.**

That ABI is OS-specific. On Linux it's `arch_prctl(ARCH_SET_FS, base)`,
which is a single syscall: number 158, first arg is the operation code
(`ARCH_SET_FS = 0x1002`), second arg is the address. The kernel writes
`IA32_FS_BASE` for the calling thread on the user's behalf and saves it
across context switches.

`tamago-go` hardcodes that exact Linux ABI in the assembly because, in
upstream tamago, the only userspace target ever envisioned is Linux
(`user/linux`).

## 4. Why this works perfectly for `tamago/user/linux`

`user/linux` runs as a regular Linux process. The host `linux/amd64`
kernel implements `syscall arch_prctl` natively. When `runtime·settls`
issues:

```
RAX = 158
RDI = 0x1002
RSI = base
SYSCALL
```

the Linux kernel:

1. Recognises `RAX = 158` as `arch_prctl`.
2. Reads `RDI = 0x1002` as `ARCH_SET_FS`.
3. Reads `RSI = base` as the new FS base.
4. Stores it in the calling thread's `task_struct->thread.fsbase`.
5. Loads `IA32_FS_BASE` MSR from that field.
6. Returns 0.

Subsequently, every `%fs`-relative load the Go program emits hits the
right memory. `arch_prctl(ARCH_SET_FS)` is a real, documented Linux
ABI; the upstream `tamago-go` developers picked it because it is the
only userspace mechanism Linux historically offered (before `WRFSBASE`
was unblocked for userspace by `CR4.FSGSBASE`, which is recent and not
always enabled).

Now zoom out: tamago has **two ways** to do TLS setup, picked by
privilege level.

| Environment | Privilege | Path taken | Mechanism | Why it works |
|---|---|---|---|---|
| `user/linux` (Linux process) | ring 3 | `application:` | `syscall RAX=158` → Linux's `arch_prctl(ARCH_SET_FS)` | Linux kernel implements it. |
| Bare metal (Cloud Hypervisor, microvm, USB armory, …) | ring 0 | `WRMSR` path | `WRMSR IA32_FS_BASE` | Tamago owns the CPU; MSR write is legal. |
| `go-boot` / UEFI | ring 0 (Boot Services) | `WRMSR` path | same | UEFI Boot Services run at ring 0. |

In every existing tamago target, *one of the two paths in `settls` is a
working answer*. The author never needed a third path because
Linux-userspace and bare-metal-ring-0 between them cover every shipped
tamago platform.

## 5. Why Fiasco / L4Re breaks both paths

Native L4Re tasks run at **ring 3** (userspace from the CPU's view; the
supervising kernel is Fiasco, not Linux). So:

- The **WRMSR path** is unreachable. `CS & 3 == 3`, the test branches
  to `application:`.
- The **`syscall arch_prctl` path** is reachable but its instruction
  does not mean what tamago thinks it means.

The collision: the `SYSCALL` instruction itself is just a
hardware-defined "fast call from ring 3 to ring 0" gate. What it does
is **defined by the kernel that loaded the IA32_LSTAR / IA32_STAR
MSRs**, i.e., by whoever set up the syscall entry vector for this CPU.
On a Linux kernel it's the Linux syscall dispatcher. On Fiasco it's
Fiasco's L4 IPC entry, with a completely different register convention:

| Register | Linux's meaning at `SYSCALL` | Fiasco's meaning at `SYSCALL` |
|---|---|---|
| RAX | syscall number | message tag (`l4_msgtag_t.raw`) |
| RDI | arg 1 | (clobbered by SYSCALL itself) |
| RSI | arg 2 | sender label / received label |
| RDX | arg 3 | destination cap \| flags |
| R10 | arg 4 | (caller-saved) |
| R8  | arg 5 | timeout |
| R9  | arg 6 | — |

When `tamago-go`'s `application:` branch fires on Fiasco:

```
RAX = 158        → Fiasco reads this as msgtag.raw
                   = label 0, words = 158 & 0x3f = 30, items = 2, flags = 0
RDI = 0x1002     → meaningless to Fiasco; CX-clobbered anyway
RSI = base       → reinterpreted as sender-label bits
RDX = ?          → undefined input; reinterpreted as cap | flags
SYSCALL          → Fiasco performs an L4 IPC with this garbage
```

Fiasco does not crash on this — it dutifully attempts to deliver an IPC
to whatever cap `RDX` happens to contain, with whatever message-register
state happens to be in the UTCB. Most likely the IPC fails with an
error label (some receiver doesn't exist), Fiasco returns to the caller
with a non-zero return tag in RAX, and `runtime·settls` returns to
`runtime·rt0_amd64_tamago`. The
`CMPQ AX, $0xfffffffffffff001 / JLS 2(PC)` check happens to pass
because the value in RAX isn't in Linux's "errno" range, so we *don't*
crash inside `settls`.

But we have not set `FS_BASE`. The MSR is whatever Fiasco initialised
it to when the task started — namely 0. So when control returns to
`rt0_amd64_tamago` line 51 and tries `MOVQ $0x123, g(BX)`, the address
is `0 + (-8)` interpreted as a 64-bit unsigned displacement, i.e.
`0xfffffffffffffff8`, which faults.

That is exactly what we see in the crash log: `pfa = 0xfffffffffffffff8`,
`fs_base = 0`, `rip` inside `runtime·rt0_amd64_tamago` right after the
`settls` call.

## 6. The crux

The reason this conflicts with our OS-userspace and not Linux's:

- **TLS setup is OS-specific** — and the OS's syscall ABI is the
  medium that conveys the request.
- `tamago-go` hardcodes one specific OS's syscall ABI (Linux's
  `arch_prctl`) into `runtime·settls`'s userspace path.
- `tamago/user/linux` works because the Linux kernel does in fact
  serve that ABI.
- Fiasco-on-L4Re also serves a userspace `SYSCALL` instruction, but
  its meaning is "issue an L4 IPC" — a completely different ABI.
- The `SYSCALL` instruction issued by `tamago-go`'s `runtime·settls`
  therefore goes through Fiasco's L4 IPC path, which doesn't set
  FS_BASE, doesn't return an error tamago recognises as failure, and
  silently leaves FS_BASE at 0.
- The very next thing the runtime does is a `%fs`-relative store,
  which page-faults because FS_BASE is 0.

It is **not** that Fiasco has some bug; it is that `tamago-go`'s
`application:` branch encodes the wrong calling convention for our
supervising kernel. That branch is, by construction, OS-specific code,
and was written for exactly one OS.

L4Re's equivalent of "set FS_BASE for this thread" is a real, documented
operation: an L4 IPC to the thread capability, opcode
`L4_THREAD_AMD64_SET_SEGMENT_BASE_OP = 0x12`, segment selector
`L4_AMD64_SEGMENT_FS = 0`, base in `MR[1]`, against
`l4re_env_t.main_thread`. See
`sources/l4re/pkg/l4re-core/l4sys/include/ARCH-amd64/segment.h:202-208`.
A fork of `tamago-go` that replaces the `application:` branch with that
IPC sequence will work; the rest of the Go runtime is OS-agnostic from
there on.

## 7. Why "just override `runtime·settls` from our overlay" doesn't work

Same physical reason that "just call our own routine instead of
`_rt0_tamago_start`" doesn't work:

- Defining a second `TEXT runtime·settls(SB)` in our overlay produces a
  duplicate-symbol link error (verified:
  `link: duplicated definition of symbol runtime.settls`).
- Computing `&runtime.m0 + m_tls + 8` from our overlay's asm and
  pre-installing FS_BASE before calling `_rt0_tamago_start` requires
  referring to `runtime.m0` from a non-runtime package, which the
  linker rejects (`link: invalid reference to runtime.m0`, enforced by
  `cmd/link/internal/loader/loader.go` `checkLinkname` line 2542).
- Using `runtime/goos`'s extension hooks (`Hwinit0`, `Hwinit1`, etc.)
  doesn't help because all of them are called *after* `runtime·settls`
  in `runtime·rt0_amd64_tamago`.
- Variable initialisers (`init()` functions, `var x = ...`) run later
  still — during `runtime.schedinit`.

Every way to redirect TLS setup that lives in user-package code is
either too late (after the broken settls runs) or rejected by the
linker (cross-package references to runtime internals). The TLS setup
is an early, foundational runtime operation; its implementation is
*required* to live inside the Go runtime itself.

## 8. The shape of the fix

Two equivalent ways:

**(a) Hardcode L4Re's `set_fs_base` IPC into `runtime·settls`'s
`application:` branch on a fork of tamago-go.**

The patch is local to `src/runtime/sys_tamago_amd64.s` in `tamago-go`.
It replaces ~9 lines (the `arch_prctl` syscall sequence) with ~12 lines
that build the L4 IPC message and issue the syscall with the L4
register convention. The L4Re main-thread cap is read from
`l4re_env_t.main_thread` via a small global the cpuinit stub populates
before `rt0_amd64_tamago` runs — that global lives in the runtime
package (so it can be referenced from `runtime·settls` without
cross-package gymnastics), and is exposed to our overlay's cpuinit via
a `//go:linkname` push.

**(b) Add a `runtime/goos` overlay hook for the userspace path**, with
the default being today's `arch_prctl` syscall, and have the L4Re
overlay replace it with the L4 IPC. This is a slightly bigger
toolchain patch (modifies `goos/stub.go` and the userspace
`goos/linux_user.go` / `goos/l4re_user.go` set), but is more aesthetic
since it leaves room for other userspace OSes to plug in too.

Either way, the patched toolchain has to be picked up by `cmd/tamago`
instead of the upstream one — done by changing one URL in our
submodule's `cmd/tamago/main.go`, or by setting `TAMAGO=/path/to/forked-go`
and bypassing `cmd/tamago` entirely.

That's the iteration 2c in the roadmap. The fork repo and
`tamago1.26.2-l4re` branch are already created; the patch itself is the
work item.

## TL;DR

`runtime·settls` is the very first OS-specific touchpoint the Go
runtime makes; on userspace tamago it speaks specifically Linux's ABI;
Fiasco isn't Linux; that one routine has to be replaced for any
non-Linux userspace target.

## Resolution (iteration 2c)

The toolchain-side fork was implemented at
[`mynetz/tamago-go`](https://github.com/mynetz/tamago-go) on branch
`tamago1.26.2-l4re`. The patch follows the design described in §8(b) of
this note: a new optional hook
`runtime/goos.SetTLSUser(base uintptr)` factored out of
`runtime.settls`'s `application:` branch, with the default body in
`runtime/goos/linux_user_amd64.s` performing the existing
`arch_prctl(ARCH_SET_FS)` syscall. Custom GOOSPKG-substituted
`runtime/goos` overlays replace the body to issue whatever set-FS
mechanism their supervising kernel exposes.

Concrete diff in tamago-go:

- `src/runtime/sys_tamago_amd64.s`: `application:` branch becomes
  `ADDQ $8, DI; CALL runtime/goos.SetTLSUser; RET`.
- `src/runtime/goos/linux_user_settls_amd64.go` (new): forward declares
  `func SetTLSUser(base uintptr)` for tamago/amd64 builds.
- `src/runtime/goos/linux_user_amd64.s`: adds `TEXT ·SetTLSUser(SB)` body
  doing the original arch_prctl syscall.
- `src/runtime/goos/stub.go`: adds the godoc-visible stub
  `func SetTLSUser(base uintptr) {}` for non-tamago builds.

Verified: a `GOOS=tamago GOARCH=amd64` `fmt.Println` program built with
the patched toolchain still runs correctly under Linux userspace using
the default arch_prctl path. The L4Re-side
[`mynetz/tamago`](https://github.com/mynetz/tamago) submodule on branch
`l4re-native` provides a `runtime/goos.SetTLSUser` body that issues an
L4 IPC `set_fs_base` against `l4re_env_t.main_thread`.

The TLS bring-up itself now succeeds on L4Re: the runtime's TLS
self-test in `runtime.rt0_amd64_tamago` passes, no FATAL is reported by
l4re_itas. A separate, unrelated stall remains in the post-TLS runtime
startup before `main.main` runs; that is outside the scope of this
note. See `docs/roadmap.md` iteration 2c for current status.
