clean_list += $(wildcard *.out)
clean_list += $(wildcard generated/*/*.lua)

init_list += .venv .dbcache

group_src += $(wildcard pkg/group/*.lua)

value_src += $(wildcard pkg/common/*.lua) $(wildcard pkg/value/*.lua)
value_src += $(foreach t,$(wildcard pkg/value/*.lua.yaml),$(t:pkg/%.yaml=generated/%))

segment_src += $(wildcard pkg/common/*.lua) $(wildcard pkg/segment/*.lua)
segment_src += $(foreach t,$(wildcard pkg/segment/*.lua.yaml),$(t:pkg/%.yaml=generated/%))

text_src += $(wildcard pkg/common/*.lua) $(wildcard pkg/text/*.lua)
text_src += $(foreach t,$(wildcard pkg/text/*.lua.yaml),$(t:pkg/%.yaml=generated/%))

bar_src += $(wildcard pkg/common/*.lua) $(wildcard pkg/bar/*.lua)
bar_src += $(foreach t,$(wildcard pkg/bar/*.lua.yaml),$(t:pkg/%.yaml=generated/%))

targets += out/value.lua out/segment.lua out/text.lua out/bar.lua out/group.lua

wa_targets += wa/Custom_Grow.lua
wa_targets += wa/nanShield_Bar_onInit.lua
wa_targets += wa/nanShield_Segment_onInit.lua
wa_targets += wa/nanShield_Text_onInit.lua
wa_targets += wa/nanShield_Value_onInit.lua

.PHONY: all clean test coverage generate

all: $(init_list) build

build: $(targets) $(wa_targets)

test:
	echo busted

clean:
	@- $(RM) -rf $(clean_list)

cleanall:
	@- $(RM) -rf $(clean_list) $(init_list) $(targets) $(wa_targets)
	
coverage: clean
	busted --coverage
	luacov

wa/Custom_Grow.lua: $(group_src)
	cat $^ > $@

wa/nanShield_Bar_onInit.lua: $(bar_src)
	cat $^ > $@

wa/nanShield_Segment_onInit.lua: $(segment_src)
	cat $^ > $@

wa/nanShield_Text_onInit.lua: $(text_src)
	cat $^ > $@

wa/nanShield_Value_onInit.lua: $(value_src)
	cat $^ > $@

out/segment.lua: $(segment_src)
	cat $^ > $@

out/value.lua: $(value_src)
	cat $^ > $@

out/text.lua: $(text_src)
	cat $^ > $@

out/bar.lua: $(bar_src)
	cat $^ > $@

out/group.lua: $(group_src)
	cat $^ > $@

generated/%.lua: pkg/%.lua.yaml
	( . .venv/bin/activate && \
	  wowdb-query -c $< -o $@ $(notdir $@))

.dbcache:
	mkdir .dbcache

.venv:
	( virtualenv .venv && \
	  . .venv/bin/activate && \
	  pip install git+ssh://git@github.com/schroeg/nan-wa-utils)


