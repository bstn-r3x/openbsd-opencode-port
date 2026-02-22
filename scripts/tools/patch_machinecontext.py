#!/usr/bin/env python3
"""Patch MachineContext.h to add OpenBSD x86_64 support for register access."""

import sys

filepath = sys.argv[1]

f = open(filepath, "r")
content = f.read()
f.close()

replacements = [
    # 1. stackPointerImpl - sc_rsp
    (
        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RSP]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_SP]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_SP]);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RSP]);""",

        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RSP]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_SP]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_SP]);
#else
#error Unknown Architecture
#endif

#elif OS(OPENBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.sc_rsp);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RSP]);"""
    ),

    # 2. framePointerImpl - sc_rbp
    (
        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RBP]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_FP]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_FP]);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RBP]);""",

        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RBP]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_FP]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_FP]);
#else
#error Unknown Architecture
#endif

#elif OS(OPENBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.sc_rbp);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RBP]);"""
    ),

    # 3. instructionPointerImpl - sc_rip
    (
        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RIP]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_PC]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_PC]);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RIP]);""",

        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RIP]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_PC]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_PC]);
#else
#error Unknown Architecture
#endif

#elif OS(OPENBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.sc_rip);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RIP]);"""
    ),

    # 4. argumentPointer<1> - sc_rsi
    (
        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RSI]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_R1]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_X1]);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RSI]);""",

        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_RSI]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_R1]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_X1]);
#else
#error Unknown Architecture
#endif

#elif OS(OPENBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.sc_rsi);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_RSI]);"""
    ),

    # 5. wasmInstancePointer - sc_rbx (note: void* not void*&, and uintptr_t not uintptr_t&)
    (
        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.__gregs[_REG_RBX]);
#elif CPU(ARM)
    return reinterpret_cast<void*>((uintptr_t) machineContext.__gregs[_REG_R10]);
#elif CPU(ARM64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.__gregs[_REG_X19]);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.gregs[REG_RBX]);""",

        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.__gregs[_REG_RBX]);
#elif CPU(ARM)
    return reinterpret_cast<void*>((uintptr_t) machineContext.__gregs[_REG_R10]);
#elif CPU(ARM64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.__gregs[_REG_X19]);
#else
#error Unknown Architecture
#endif

#elif OS(OPENBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.sc_rbx);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*>((uintptr_t) machineContext.gregs[REG_RBX]);"""
    ),

    # 6. llintInstructionPointer - sc_r8
    (
        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_R8]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_R8]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_X4]);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_R8]);""",

        """#elif OS(NETBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_R8]);
#elif CPU(ARM)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_R8]);
#elif CPU(ARM64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.__gregs[_REG_X4]);
#else
#error Unknown Architecture
#endif

#elif OS(OPENBSD)

#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.sc_r8);
#else
#error Unknown Architecture
#endif

#elif OS(FUCHSIA) || OS(LINUX) || OS(HURD)

// The following sequence depends on glibc's sys/ucontext.h.
#if CPU(X86_64)
    return reinterpret_cast<void*&>((uintptr_t&) machineContext.gregs[REG_R8]);"""
    ),
]

for i, (old, new) in enumerate(replacements):
    if old not in content:
        print(f"WARNING: Replacement {i+1} pattern not found!")
    else:
        content = content.replace(old, new, 1)
        print(f"Replacement {i+1} applied successfully")

f = open(filepath, "w")
f.write(content)
f.close()
print("All done")
