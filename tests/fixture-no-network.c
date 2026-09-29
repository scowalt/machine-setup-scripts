/* Version 1: Linux-only fail-closed outbound containment for inert fixtures.
 * This is NOT a filesystem/process sandbox. No network namespace is assumed.
 * Compile with the system C compiler; run from a sanitized, temporary environment.
 */
#define _GNU_SOURCE
#include <errno.h>
#include <fcntl.h>
#include <linux/audit.h>
#include <linux/filter.h>
#include <linux/seccomp.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>
#include <sys/prctl.h>
#include <sys/resource.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#if defined(__x86_64__)
#define FIXTURE_ARCH AUDIT_ARCH_X86_64
#elif defined(__aarch64__)
#define FIXTURE_ARCH AUDIT_ARCH_AARCH64
#else
#error Unsupported fixture architecture; do not run without containment.
#endif

#define DENY(n) BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, (n), 0, 1), \
    BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ERRNO | EPERM)

static int fail(const char *reason) {
    fprintf(stderr, "fixture sandbox refused: %s\n", reason);
    return 125;
}

/* Inspect standard descriptors and close EVERYTHING else before untrusted code.
 * Inheritable network sockets cannot survive via exec or a nonstandard FD.
 */
static int close_inherited_fds(void) {
    int unsafe = 0;
    for (int fd = 0; fd < 3; fd++) {
        struct stat info;
        if (fstat(fd, &info) == -1) {
            if (errno == EBADF) continue;
            close(fd);
            unsafe = 1;
        } else if (S_ISSOCK(info.st_mode)) {
            close(fd);
            unsafe = 1;
        }
    }
    /* Never print even a refusal diagnostic onto an inherited network socket. */
    if (unsafe) { close(STDERR_FILENO); return -1; }
#ifdef SYS_close_range
    if (syscall(SYS_close_range, 3U, ~0U, 0U) == 0) return 0;
    if (errno != ENOSYS) return -1;
#endif
    struct rlimit limit;
    if (getrlimit(RLIMIT_NOFILE, &limit) || limit.rlim_max == RLIM_INFINITY ||
        limit.rlim_max > 1048576) return -1;
    for (int fd = 3; (rlim_t)fd < limit.rlim_max; fd++) {
        if (close(fd) == -1 && errno != EBADF) return -1;
    }
    return 0;
}

static int contain(void) {
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, arch)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, FIXTURE_ARCH, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS, offsetof(struct seccomp_data, nr)),
#if defined(__x86_64__)
        /* x32 shares the audit architecture but uses different syscall numbers. */
        BPF_JUMP(BPF_JMP | BPF_JSET | BPF_K, 0x40000000U, 0, 1),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL_PROCESS),
#endif
        DENY(SYS_socket), DENY(SYS_connect), DENY(SYS_bind), DENY(SYS_listen),
        DENY(SYS_accept), DENY(SYS_accept4), DENY(SYS_sendto), DENY(SYS_sendmsg),
        DENY(SYS_sendmmsg),
#ifdef SYS_socketcall
        DENY(SYS_socketcall),
#endif
#ifdef SYS_io_uring_setup
        DENY(SYS_io_uring_setup), DENY(SYS_io_uring_enter), DENY(SYS_io_uring_register),
#endif
#ifdef SYS_pidfd_getfd
        DENY(SYS_pidfd_getfd),
#endif
        DENY(SYS_ptrace), DENY(SYS_process_vm_writev), DENY(SYS_setns),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog program = { .len = sizeof(filter) / sizeof(filter[0]), .filter = filter };
    if (prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0)) return -1;
    return prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &program);
}

/* No connect target, DNS, bind, listener or packet: socket construction only. */
static int assert_socket_denied(void) {
    const int families[] = { AF_INET, AF_INET6 };
    for (unsigned i = 0; i < sizeof(families) / sizeof(families[0]); i++) {
        int fd = socket(families[i], SOCK_STREAM, 0);
        if (fd >= 0) { close(fd); return fail("socket creation was not denied"); }
        if (errno != EPERM) return fail("unexpected socket denial reason");
    }
    puts("PASS: AF_INET and AF_INET6 socket creation denied with EPERM; no target used");
    return 0;
}

int main(int argc, char **argv) {
    /* Even argument/probe refusal paths must not retain a socket-backed stderr. */
    if (close_inherited_fds()) return 125;
    /* This probe is deliberately separate: descendants must demonstrate the
     * inherited parent filter, not install a fresh filter and hide a gap. */
    if (argc == 2 && strcmp(argv[1], "--assert-inherited-denial") == 0)
        return assert_socket_denied();
    if (argc < 2) return fail("expected --self-test or -- command");
    if (strcmp(argv[1], "--self-test") != 0 && strcmp(argv[1], "--") != 0)
        return fail("unknown argument");
    if (strcmp(argv[1], "--") == 0 && argc < 3) return fail("missing command");
    if (contain()) return fail("FD validation or seccomp installation failed");
    if (strcmp(argv[1], "--self-test") == 0) return assert_socket_denied();
    execvp(argv[2], argv + 2);
    return fail("child execution failed");
}
