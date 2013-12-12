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
