std_C64.mif.hex: pref.hex std_C64.mif.bin.hex
	cat $^ > $@

std_C64.mif.bin.hex: std_C64.mif.bin
	xxd -p -c 1 $^ > $@

std_C64.mif.bin: vectors.o init.o
	ld65 -C ld.cfg $^ -o $@

%.o: %.s
	cl65 -t none -c -o $@ $^

.PHONY: clean
clean:
	rm -rf std_C64.mif.hex
	rm -rf std_C64.mif.bin
	rm -rf *.o
	rm -rf a.out

