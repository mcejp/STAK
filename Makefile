all: test1.bc test2.bc test3.bc test-input.bc test-lines.bc test-triangle.bc test-wireframe.bc

%.unit: %.scm compile.hy constants.json
	hy compile.hy $< -o $@ && cat $@

%.bc: %.unit link.hy builtins.json
	hy link.hy $< -o $@ #&& xxd $@
