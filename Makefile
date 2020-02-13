all: alibum

SOURCES := \
    alibum.d \
    html.d \
    magickwand.d \

DCOMPILER := \
    dmd

DFLAGS := \
    -w \
    -inline \
    -L-L/usr/lib/x86_64-linux-gnu \

UNITTEST_FLAGS := \
    $(DFLAGS) \
    -unittest \
    -main \

alibum_tests: $(SOURCES) Makefile
	$(DCOMPILER) | grep 'D Compiler'
	$(DCOMPILER) $(SOURCES) $(UNITTEST_FLAGS) -of$@
	./$@

alibum: alibum_tests $(SOURCES) Makefile
	$(DCOMPILER) $(SOURCES) $(DFLAGS) -of$@
