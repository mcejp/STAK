all: 01fill.bc 02colors.bc 03loop.bc 04input.bc 05lines.bc flower.bc wirefram.bc

clean:
	rm -f *.bc *.unit

%.unit: %.scm compile.hy constants.json transforms.hy
	hy compile.hy $< -o $@ #&& cat $@

%.bc: %.unit link.hy builtins.json
	hy link.hy $< -o $@ #&& xxd $@

.PHONY: all clean
