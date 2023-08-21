all: test1.bc test2.bc test3.bc test-input.bc test-lines.bc test-triangle.bc test-wireframe.bc

%.unit: %.scm compile.hy
	hy compile.hy $< -o $@ && cat $@

%.bc: %.unit link.hy
	hy link.hy $< -o $@ && xxd $@
