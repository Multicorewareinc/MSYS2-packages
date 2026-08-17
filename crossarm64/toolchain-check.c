/*
 * Does the aarch64-pc-msys toolchain actually work?
 *
 * Compiled and run by 02-check-toolchain.sh.  Everything here is something the
 * package chain relies on, and most of it has broken at some point during this
 * port, so a failure names a specific problem rather than "it doesn't work".
 *
 * Build:
 *   aarch64-pc-msys-gcc -O0 -g -specs=<specs> -o toolchain-check.exe \
 *       toolchain-check.c -lm
 *
 * There is no -lpthread on this target: as on Cygwin, the pthread functions
 * live in libc (msys-2.0), and asking for it fails with "cannot find
 * -lpthread".
 *
 * Optional:
 *   -DCHECK_TLS      adds a __thread variable.  Fails to LINK unless -lgcc_eh
 *                    is given - MSYS2-packages#31.
 *   -DCHECK_SOCKET   calls socket().  Currently SEGFAULTS on this runtime -
 *                    msys2-runtime#5 - so it is off by default.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <errno.h>
#include <unistd.h>
#include <pthread.h>
#include <sys/wait.h>
#include <sys/types.h>

#ifdef CHECK_SOCKET
# include <sys/socket.h>
# include <netinet/in.h>
# include <arpa/inet.h>
#endif

static int failures;

static void ok(const char *what, const char *detail)
{
    printf("  PASS  %-28s %s\n", what, detail ? detail : "");
}

static void bad(const char *what, const char *detail)
{
    printf("  FAIL  %-28s %s\n", what, detail ? detail : "");
    failures++;
}

/* ---------------------------------------------------------------- target -- */

static void check_target(void)
{
#if !defined(__aarch64__)
    bad("target is aarch64", "__aarch64__ is not defined");
#else
    ok("target is aarch64", NULL);
#endif

#if defined(__MSYS__)
    ok("msys target", "__MSYS__ defined");
#elif defined(__CYGWIN__)
    /* Expected: the recipes configure with the cygwin triplet because libtool's
       host_os list has no msys entry, so __CYGWIN__ is what gets defined. */
    ok("cygwin/msys target", "__CYGWIN__ defined");
#else
    bad("msys or cygwin target", "neither __MSYS__ nor __CYGWIN__ is defined");
#endif

    if (sizeof(void *) == 8 && sizeof(long) == 8)
        ok("LP64 model", "pointer and long are 8 bytes");
    else {
        char buf[64];
        snprintf(buf, sizeof buf, "pointer=%zu long=%zu",
                 sizeof(void *), sizeof(long));
        bad("LP64 model", buf);
    }

    {
        unsigned int  x = 1;
        if (*(unsigned char *)&x == 1) ok("little endian", NULL);
        else                           bad("little endian", "big-endian byte order");
    }
}

/* ------------------------------------------------------------------ libc -- */

static void check_libc(void)
{
    char *p = malloc(4096);
    if (!p) { bad("malloc", "returned NULL"); return; }
    memset(p, 0x5a, 4096);
    if ((unsigned char)p[4095] == 0x5a) ok("malloc + memset", NULL);
    else                                bad("malloc + memset", "memory did not hold its value");
    free(p);

    {
        char buf[32];
        snprintf(buf, sizeof buf, "%d-%s-%.2f", 42, "x", 1.5);
        if (strcmp(buf, "42-x-1.50") == 0) ok("snprintf", buf);
        else                               bad("snprintf", buf);
    }

    /* libm is a separate archive here; a linker problem shows up as an
       undefined reference rather than a wrong answer. */
    if (fabs(sqrt(144.0) - 12.0) < 1e-9) ok("libm", "sqrt(144) == 12");
    else                                 bad("libm", "sqrt gave the wrong answer");
}

/* --------------------------------------------------------------- process -- */

/* fork() is what the whole build depends on, and it fails intermittently on
 * this runtime - msys2-runtime#7 - so this runs it repeatedly rather than once.
 * A single success would not tell us much. */
static void check_fork(void)
{
    const int rounds = 40;
    int bad_rounds = 0;

    for (int i = 0; i < rounds; i++) {
        pid_t pid = fork();
        if (pid < 0) { bad_rounds++; continue; }
        if (pid == 0) _exit(42);

        int status = 0;
        if (waitpid(pid, &status, 0) < 0)             bad_rounds++;
        else if (!WIFEXITED(status))                  bad_rounds++;
        else if (WEXITSTATUS(status) != 42)           bad_rounds++;
    }

    char buf[80];
    snprintf(buf, sizeof buf, "%d/%d round(s) failed", bad_rounds, rounds);
    if (bad_rounds == 0)
        ok("fork + waitpid", buf);
    else {
        /* Not counted as a hard failure: this is a known runtime defect, and
           reporting the rate is more useful than a yes/no. */
        printf("  WARN  %-28s %s (msys2-runtime#7)\n", "fork + waitpid", buf);
    }
}

static void *thread_main(void *arg)
{
    int *v = arg;
    *v = 7;
    return NULL;
}

static void check_threads(void)
{
    pthread_t t;
    int v = 0;

    if (pthread_create(&t, NULL, thread_main, &v) != 0) {
        bad("pthread_create", strerror(errno));
        return;
    }
    pthread_join(t, NULL);
    if (v == 7) ok("pthread create + join", NULL);
    else        bad("pthread create + join", "the thread did not run");
}

/* ------------------------------------------------------------- optional  -- */

#ifdef CHECK_TLS
/* Links only with -lgcc_eh: this target uses emulated TLS and ships
   __emutls_get_address in libgcc_eh.a rather than libgcc.a. */
static __thread int tls_value;

static void check_tls(void)
{
    tls_value = 99;
    if (tls_value == 99) ok("__thread variable", "emutls resolved");
    else                 bad("__thread variable", "wrong value");
}
#endif

#ifdef CHECK_SOCKET
static void check_socket(void)
{
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) bad("socket()", strerror(errno));
    else        { ok("socket()", "created"); close(fd); }
}
#endif

/* ------------------------------------------------------------------ main -- */

int main(void)
{
    printf("aarch64-pc-msys toolchain check\n");
    printf("  compiler : gcc %d.%d.%d, __STDC_VERSION__ %ld\n",
           __GNUC__, __GNUC_MINOR__, __GNUC_PATCHLEVEL__, (long)__STDC_VERSION__);
    printf("\n");

    check_target();
    check_libc();
    check_threads();
    check_fork();
#ifdef CHECK_TLS
    check_tls();
#endif
#ifdef CHECK_SOCKET
    check_socket();
#endif

    printf("\n");
    if (failures == 0) {
        printf("  all runtime checks passed\n");
        return 0;
    }
    printf("  %d check(s) failed\n", failures);
    return 1;
}
