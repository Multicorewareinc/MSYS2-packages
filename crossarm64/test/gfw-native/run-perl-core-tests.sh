# Perl's own test suite on the ARM64 runtime, in the cross build tree.
# (build tree first in PATH: every process, whatever its cwd, then maps the
# same msys-perl5_42.dll copy; see the fork/ASLR issue. The build-tree DLL is
# also a hard link to the installed one, so both paths are one image section)
cd /home/HCKTest/MSYS2-packages/perl/src/perl-5.42.3/t || exit 1
export PATH=/home/HCKTest/MSYS2-packages/perl/src/perl-5.42.3:$PATH MSYS=winsymlinks:nativestrict LANG=C.UTF-8 TEST_JOBS=8 HARNESS_NOTTY=1 PERL_SKIP_TTY_TEST=1 HARNESS_TIMER=1
date
./perl.exe harness > /home/HCKTest/gfw-tests/t4/perl-core-tests5.log 2>&1
echo "harness rc=$?" >> /home/HCKTest/gfw-tests/t4/perl-core-tests5.log
date
