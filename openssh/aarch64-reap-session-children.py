"""Make sshd's server loop independent of SIGCHLD on aarch64-pc-cygwin.

Symptom: sshd intermittently never observes the session child exiting.  The
command runs and its output is delivered, but exit-status is never sent and the
client hangs.  On a fresh sshd, 14 consecutive connections gave
H.HHHHH.HHHHxx (H = hung, x = no longer accepting once hung sessions pile up),
while the stock x86_64 sshd on the same machine is 10/10 clean.  poll, ppoll
with a signal mask, and fork+exec+SIGCHLD all behave correctly in isolation, so
the root cause is still open; this only stops it from being fatal.

Approach: poll the sessions we own with waitpid(pid, WNOHANG) on every pass of
the loop, and cap the ppoll timeout so an idle connection still gets there.

Deliberately NOT a blanket waitpid(-1): that also reaps the privsep child, and
the monitor then reports "mm_reap: child exited with status 255" and tears the
whole daemon down.  Only pids held in the session table are waited on.
"""
import io

T = chr(9)
NL = chr(10)


def read(p):
    return io.open(p, encoding="utf-8", newline="").read()


def write(p, s):
    io.open(p, "w", encoding="utf-8", newline="").write(s)


# 1. session.c -- add the helper next to the other session table walkers
s = read("session.c")
anchor = "void" + NL + "session_destroy_all("
assert anchor in s, "session.c: session_destroy_all not found"
helper = (
    "/* aarch64-pc-cygwin: reap session children without relying on SIGCHLD."
    + NL
    + " * Waits only on pids in the session table, so the privsep child is"
    + NL
    + " * left for the monitor to reap. */"
    + NL
    + "void"
    + NL
    + "session_poll_children(struct ssh *ssh)"
    + NL
    + "{"
    + NL
    + T + "int i, status;"
    + NL
    + T + "pid_t pid;"
    + NL
    + T + "Session *s;"
    + NL
    + NL
    + T + "for (i = 0; i < sessions_nalloc; i++) {"
    + NL
    + T * 2 + "s = &sessions[i];"
    + NL
    + T * 2 + "if (!s->used || s->pid <= 0)"
    + NL
    + T * 3 + "continue;"
    + NL
    + T * 2 + "pid = waitpid(s->pid, &status, WNOHANG);"
    + NL
    + T * 2 + "if (pid == s->pid)"
    + NL
    + T * 3 + "session_exit_message(ssh, s, status);"
    + NL
    + T + "}"
    + NL
    + "}"
    + NL
    + NL
)
write("session.c", s.replace(anchor, helper + anchor, 1))

# 2. session.h -- declare it
h = read("session.h")
decl = "void" + T + " session_destroy_all(struct ssh *, void (*)(Session *));"
assert decl in h, "session.h: session_destroy_all declaration not found"
write("session.h", h.replace(
    decl, "void" + T + " session_poll_children(struct ssh *);" + NL + decl, 1))

# 3. serverloop.c -- call it every pass, and never sleep forever
c = read("serverloop.c")
old = (
    T + "if (child_terminated) {" + NL
    + T * 2 + 'debug("Received SIGCHLD.");' + NL
    + T * 2 + "while ((pid = waitpid(-1, &status, WNOHANG)) > 0 ||" + NL
    + T * 2 + "    (pid == -1 && errno == EINTR))" + NL
    + T * 3 + "if (pid > 0)" + NL
    + T * 4 + "session_close_by_pid(ssh, pid, status);" + NL
    + T * 2 + "child_terminated = 0;" + NL
    + T + "}"
)
assert old in c, "serverloop.c: collect_children body not found"
new = (
    old + NL
    + T + "/* aarch64-pc-cygwin: SIGCHLD is unreliable here, so also poll the"
    + NL
    + T + " * sessions we own.  Cheap: one WNOHANG waitpid per live session. */"
    + NL
    + T + "session_poll_children(ssh);"
)
c = c.replace(old, new, 1)

anchor2 = (
    T + "if (child_terminated && ssh_packet_not_very_much_data_to_write(ssh))"
    + NL
    + T * 2 + "ptimeout_deadline_ms(&timeout, 100);"
)
assert anchor2 in c, "serverloop.c: ppoll timeout anchor not found"
c = c.replace(anchor2, anchor2 + NL + NL
              + T + "/* aarch64-pc-cygwin: never block indefinitely, so a session whose"
              + NL
              + T + " * SIGCHLD was lost is still reaped within a second. */"
              + NL
              + T + "ptimeout_deadline_ms(&timeout, 1000);", 1)
write("serverloop.c", c)

print("  aarch64: session_poll_children() added; loop polls it and caps its timeout")
