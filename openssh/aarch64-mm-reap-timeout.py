"""Stop a stuck privsep child from hanging the session for ever (aarch64).

Measured on aarch64-pc-cygwin: with back-to-back connections, roughly one
session in ten finishes logically -- the server logs

    Received disconnect from 127.0.0.1 port N:11: disconnected by user
    Disconnected from user mcw 127.0.0.1 port N

-- but the unprivileged post-auth child never exits.  mm_reap() then sits in

    while (waitpid(pmonitor->m_pid, &status, 0) == -1)

for ever, exit-status is never sent, and the client hangs until it is killed.
The listener itself stays healthy and keeps accepting, so the daemon looks fine
while individual sessions wedge.

Proof of the mechanism: killing *only* the privsep child makes the monitor
return from waitpid immediately and the waiting client completes.

This bounds that wait.  The monitor polls with WNOHANG; if the child has not
exited after MM_REAP_WAIT_MS it is sent SIGTERM, then SIGKILL, and the wait
continues -- so a wedged child costs a few seconds instead of the session.

This is containment, not a cure: the reason the child fails to exit is still
open (msys2-runtime, issue #51).  Native i686/x86_64 are untouched; the whole
change is inside #ifdef __aarch64__.
"""
import io
import sys

PATH = "monitor_wrap.c"

OLD = """	if (!mm_is_monitor())
		return;
	while (waitpid(pmonitor->m_pid, &status, 0) == -1) {
		if (errno == EINTR)
			continue;
		pmonitor->m_pid = -1;
		fatal_f("waitpid: %s", strerror(errno));
	}"""

NEW = """	if (!mm_is_monitor())
		return;
#ifdef __aarch64__
	/* aarch64-pc-cygwin: the post-auth child intermittently fails to exit
	 * after the session has finished, which leaves this wait blocking for
	 * ever and hangs the client.  Bound it: poll, then terminate.  See
	 * openssh/aarch64-mm-reap-timeout.py. */
	{
		int waited_ms = 0, signalled = 0;
		pid_t r;

		for (;;) {
			r = waitpid(pmonitor->m_pid, &status, WNOHANG);
			if (r > 0)
				break;
			if (r == -1) {
				if (errno == EINTR)
					continue;
				pmonitor->m_pid = -1;
				fatal_f("waitpid: %s", strerror(errno));
			}
			/* r == 0: still running */
			if (waited_ms >= MM_REAP_WAIT_MS && signalled == 0) {
				error_f("privsep child %ld did not exit, "
				    "sending SIGTERM", (long)pmonitor->m_pid);
				kill(pmonitor->m_pid, SIGTERM);
				signalled = 1;
			} else if (waited_ms >= MM_REAP_WAIT_MS +
			    MM_REAP_KILL_MS && signalled == 1) {
				error_f("privsep child %ld still alive, "
				    "sending SIGKILL", (long)pmonitor->m_pid);
				kill(pmonitor->m_pid, SIGKILL);
				signalled = 2;
			}
			usleep(10000);
			waited_ms += 10;
		}
	}
#else
	while (waitpid(pmonitor->m_pid, &status, 0) == -1) {
		if (errno == EINTR)
			continue;
		pmonitor->m_pid = -1;
		fatal_f("waitpid: %s", strerror(errno));
	}
#endif"""

DEFS = """
#ifdef __aarch64__
/* How long mm_reap() waits for the privsep child before forcing it down. */
# define MM_REAP_WAIT_MS 3000
# define MM_REAP_KILL_MS 2000
#endif
"""


def main():
    text = io.open(PATH, encoding="utf-8", newline="").read()
    if "MM_REAP_WAIT_MS" in text:
        sys.stderr.write("mm_reap timeout: already applied\n")
        return 0
    if OLD not in text:
        sys.stderr.write("mm_reap timeout: anchor not found in %s\n" % PATH)
        return 1
    text = text.replace(OLD, NEW, 1)

    # put the limits just before mm_reap's definition
    marker = "static void\nmm_reap(void)"
    if marker not in text:
        sys.stderr.write("mm_reap timeout: mm_reap definition not found\n")
        return 1
    text = text.replace(marker, DEFS + "\n" + marker, 1)

    io.open(PATH, "w", encoding="utf-8", newline="").write(text)
    sys.stderr.write("mm_reap timeout: applied to %s\n" % PATH)
    return 0


if __name__ == "__main__":
    sys.exit(main())
