--[[
Luanite
    Copyright (C) 2025 tixonochek

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License version 3
    along with this program. If not, see https://www.gnu.org/licenses/.
]]

local luastatic_source = [==========[
#!/usr/bin/env lua

-- The C compiler used to compile and link the generated C source file.
local CC = os.getenv("CC") or "cc"
-- The nm used to determine whether a library is liblua or a Lua binary module.
local NM = os.getenv("NM") or "nm"

local function file_exists(name)
	local file = io.open(name, "r")
	if file then
		file:close()
		return true
	end
	return false
end

--[[
Run a shell command, wait for it to finish, and return a string containing stdout.
--]]
local function shellout(command)
	local file = io.popen(command)
	local stdout = file:read("*all")
	local ok = file:close()
	if ok then
		return stdout
	end
	return nil
end

--[[
Use execute() when stdout isn't needed instead of shellout() because io.popen() does
not return the status code in Lua 5.1.
--]]
local function execute(cmd)
	local ok = os.execute(cmd)
	return (ok == true or ok == 0)
end

--[[
Return a comma separated hex string suitable for a C array definition.
--]]
local function string_to_c_hex_literal(characters)
	local hex = {}
	for character in characters:gmatch(".") do
		table.insert(hex, ("0x%02x"):format(string.byte(character)))
	end
	return table.concat(hex, ", ")
end
assert(string_to_c_hex_literal("hello") == "0x68, 0x65, 0x6c, 0x6c, 0x6f")

--[[
Strip the directory from a filename.
--]]
local function basename(path)
	local name = path:gsub([[(.*[\/])(.*)]], "%2")
	return name
end
assert(basename("/path/to/file.lua") == "file.lua")
assert(basename([[C:\path\to\file.lua]]) == "file.lua")

local function is_source_file(extension)
	return
		-- Source file.
		extension == "lua" or
		-- Precompiled chunk.
		extension == "luac"
end

local function is_binary_library(extension)
	return
		-- Object file.
		extension == "o" or
		-- Static library.
		extension == "a" or
		-- Shared library.
		extension == "so" or
		-- Mach-O dynamic library.
		extension == "dylib"
end

-- Required Lua source files.
local lua_source_files = {}
-- Libraries for required Lua binary modules.
local module_library_files = {}
local module_link_libraries = {}
-- Libraries other than Lua binary modules, including liblua.
local dep_library_files = {}
-- Additional arguments are passed to the C compiler.
local other_arguments = {}
-- Get the operating system name.
local UNAME = (shellout("uname -s") or "Unknown"):match("%a+") or "Unknown"
local link_with_libdl = ""

--[[
Parse command line arguments. main.lua must be the first argument. Static libraries are
passed to the compiler in the order they appear and may be interspersed with arguments to
the compiler. Arguments to the compiler are passed to the compiler in the order they
appear.
--]]
for i, name in ipairs(arg) do
	local extension = name:match("%.(%a+)$")
	if i == 1 or (is_source_file(extension) or is_binary_library(extension)) then
		if not file_exists(name) then
			io.stderr:write("file does not exist: " .. name .. "\n")
			os.exit(1)
		end

		local info = {}
		info.path = name
		info.basename = basename(info.path)
		info.basename_noextension = info.basename:match("(.+)%.") or info.basename
		--[[
		Handle the common case of "./path/to/file.lua".
		This won't work in all cases.
		--]]
		info.dotpath = info.path:gsub("^%.%/", "")
		info.dotpath = info.dotpath:gsub("[\\/]", ".")
		info.dotpath_noextension = info.dotpath:match("(.+)%.") or info.dotpath
		info.dotpath_underscore = info.dotpath_noextension:gsub("[.-]", "_")

		if i == 1 or is_source_file(extension) then
			table.insert(lua_source_files, info)
		elseif is_binary_library(extension) then
			-- The library is either a Lua module or a library dependency.
			local nmout = shellout(NM .. " " .. info.path)
			if not nmout then
				io.stderr:write("nm not found\n")
				os.exit(1)
			end
			local is_module = false
			if nmout:find("T _?luaL_newstate") then
				if nmout:find("U _?dlopen") then
					if UNAME == "Linux" or UNAME == "SunOS" or UNAME == "Darwin" then
						--[[
						Link with libdl because liblua was built with support loading
						shared objects and the operating system depends on it.
						--]]
						link_with_libdl = "-ldl"
					end
				end
			else
				for luaopen in nmout:gmatch("[^dD] _?luaopen_([%a%p%d]+)") do
					local modinfo = {}
					modinfo.path = info.path
					modinfo.dotpath_underscore = luaopen
					modinfo.dotpath = modinfo.dotpath_underscore:gsub("_", ".")
					modinfo.dotpath_noextension = modinfo.dotpath
					is_module = true
					table.insert(module_library_files, modinfo)
				end
			end
			if is_module then
				table.insert(module_link_libraries, info.path)
			else
				table.insert(dep_library_files, info.path)
			end
		end
	else
		-- Forward the remaining arguments to the C compiler.
		table.insert(other_arguments, name)
	end
end

if #lua_source_files == 0 then
	local version = "0.0.12"
	print("luastatic " .. version)
	print([[
usage: luastatic main.lua[1] require.lua[2] liblua.a[3] library.a[4] -I/include/lua[5] [6]
  [1]: The entry point to the Lua program
  [2]: One or more required Lua source files
  [3]: The path to the Lua interpreter static library
  [4]: One or more static libraries for a required Lua binary module
  [5]: The path to the directory containing lua.h
  [6]: Additional arguments are passed to the C compiler]])
	os.exit(1)
end

-- The entry point to the Lua program.
local mainlua = lua_source_files[1]
--[[
Generate a C program containing the Lua source files that uses the Lua C API to
initialize any Lua libraries and run the program.
--]]
local outfilename = mainlua.basename_noextension .. ".luastatic.c"
local outfile = io.open(outfilename, "w+")
local function out(...)
	outfile:write(...)
end
local function outhex(str)
	outfile:write(string_to_c_hex_literal(str), ", ")
end

--[[
Embed Lua program source code.
--]]
local function out_lua_source(file)
	local f = io.open(file.path, "r")
	local prefix = f:read(4)
	if prefix then
		if prefix:match("\xef\xbb\xbf") then
			-- Strip the UTF-8 byte order mark.
			prefix = prefix:sub(4)
		end
		if prefix:match("#") then
			-- Strip the shebang.
			f:read("*line")
			prefix = "\n"
		end
		out(string_to_c_hex_literal(prefix), ", ")
	end
	while true do
		local strdata = f:read(4096)
		if strdata then
			out(string_to_c_hex_literal(strdata), ", ")
		else
			break
		end
	end
	f:close()
end

out([[
#ifdef __cplusplus
extern "C" {
#endif
#include <lauxlib.h>
#include <lua.h>
#include <lualib.h>
#ifdef __cplusplus
}
#endif
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#if LUA_VERSION_NUM == 501
	#define LUA_OK 0
#endif

/* Copied from lua.c */

static lua_State *globalL = NULL;

static void lstop (lua_State *L, lua_Debug *ar) {
	(void)ar;  /* unused arg. */
	lua_sethook(L, NULL, 0, 0);  /* reset hook */
	luaL_error(L, "interrupted!");
}

static void laction (int i) {
	signal(i, SIG_DFL); /* if another SIGINT happens, terminate process */
	lua_sethook(globalL, lstop, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
}

static void createargtable (lua_State *L, char **argv, int argc, int script) {
	int i, narg;
	if (script == argc) script = 0;  /* no script name? */
	narg = argc - (script + 1);  /* number of positive indices */
	lua_createtable(L, narg, script + 1);
	for (i = 0; i < argc; i++) {
		lua_pushstring(L, argv[i]);
		lua_rawseti(L, -2, i - script);
	}
	lua_setglobal(L, "arg");
}

static int msghandler (lua_State *L) {
	const char *msg = lua_tostring(L, 1);
	if (msg == NULL) {  /* is error object not a string? */
		if (luaL_callmeta(L, 1, "__tostring") &&  /* does it have a metamethod */
				lua_type(L, -1) == LUA_TSTRING)  /* that produces a string? */
			return 1;  /* that is the message */
		else
			msg = lua_pushfstring(L, "(error object is a %s value)", luaL_typename(L, 1));
	}
	/* Call debug.traceback() instead of luaL_traceback() for Lua 5.1 compatibility. */
	lua_getglobal(L, "debug");
	lua_getfield(L, -1, "traceback");
	/* debug */
	lua_remove(L, -2);
	lua_pushstring(L, msg);
	/* original msg */
	lua_remove(L, -3);
	lua_pushinteger(L, 2);  /* skip this function and traceback */
	lua_call(L, 2, 1); /* call debug.traceback */
	return 1;  /* return the traceback */
}

static int docall (lua_State *L, int narg, int nres) {
	int status;
	int base = lua_gettop(L) - narg;  /* function index */
	lua_pushcfunction(L, msghandler);  /* push message handler */
	lua_insert(L, base);  /* put it under function and args */
	globalL = L;  /* to be available to 'laction' */
	signal(SIGINT, laction);  /* set C-signal handler */
	status = lua_pcall(L, narg, nres, base);
	signal(SIGINT, SIG_DFL); /* reset C-signal handler */
	lua_remove(L, base);  /* remove message handler from the stack */
	return status;
}

#ifdef __cplusplus
extern "C" {
#endif
]])

for _, library in ipairs(module_library_files) do
	out(('	int luaopen_%s(lua_State *L);\n'):format(library.dotpath_underscore))
end

out([[
#ifdef __cplusplus
}
#endif


int main(int argc, char *argv[])
{
	lua_State *L = luaL_newstate();
	luaL_openlibs(L);
	createargtable(L, argv, argc, 0);

	static const unsigned char lua_loader_program[] = {
		]])

outhex([[
local args = {...}
local lua_bundle = args[1]

local function load_string(str, name)
	if _VERSION == "Lua 5.1" then
		return loadstring(str, name)
	else
		return load(str, name)
	end
end

local function lua_loader(name)
	local separator = package.config:sub(1, 1)
	name = name:gsub(separator, ".")
	local mod = lua_bundle[name] or lua_bundle[name .. ".init"]
	if mod then
		if type(mod) == "string" then
			local chunk, errstr = load_string(mod, name)
			if chunk then
				return chunk
			else
				error(
					("error loading module '%s' from luastatic bundle:\n\t%s"):format(name, errstr),
					0
				)
			end
		elseif type(mod) == "function" then
			return mod
		end
	else
		return ("\n\tno module '%s' in luastatic bundle"):format(name)
	end
end
table.insert(package.loaders or package.searchers, 2, lua_loader)

-- Lua 5.1 has unpack(). Lua 5.2+ has table.unpack().
local unpack = unpack or table.unpack
]])

outhex(([[
local func = lua_loader("%s")
if type(func) == "function" then
	-- Run the main Lua program.
	func(unpack(arg))
else
	error(func, 0)
end
]]):format(mainlua.dotpath_noextension))

out(([[

	};
	/*printf("%%.*s", (int)sizeof(lua_loader_program), lua_loader_program);*/
	if
	(
		luaL_loadbuffer(L, (const char*)lua_loader_program, sizeof(lua_loader_program), "%s")
		!= LUA_OK
	)
	{
		fprintf(stderr, "luaL_loadbuffer: %%s\n", lua_tostring(L, -1));
		lua_close(L);
		return 1;
	}
	
	/* lua_bundle */
	lua_newtable(L);
]]):format(mainlua.basename_noextension));

for i, file in ipairs(lua_source_files) do
	out(('	static const unsigned char lua_require_%i[] = {\n		'):format(i))
	out_lua_source(file);
	out("\n	};\n")
	out(([[
	lua_pushlstring(L, (const char*)lua_require_%i, sizeof(lua_require_%i));
]]):format(i, i))
	out(('	lua_setfield(L, -2, "%s");\n\n'):format(file.dotpath_noextension))
end

for _, library in ipairs(module_library_files) do
	out(('	lua_pushcfunction(L, luaopen_%s);\n'):format(library.dotpath_underscore))
	out(('	lua_setfield(L, -2, "%s");\n\n'):format(library.dotpath_noextension))
end

out([[
	if (docall(L, 1, LUA_MULTRET))
	{
		const char *errmsg = lua_tostring(L, 1);
		if (errmsg)
		{
			fprintf(stderr, "%s\n", errmsg);
		}
		lua_close(L);
		return 1;
	}
	lua_close(L);
	return 0;
}
]])

outfile:close()

if os.getenv("CC") == "" then
	-- Disable compiling and exit with a success code.
	os.exit(0)
end

if not execute(CC .. " --version 1>/dev/null 2>/dev/null") then
	io.stderr:write("C compiler not found.\n")
	os.exit(1)
end

-- http://lua-users.org/lists/lua-l/2009-05/msg00147.html
local rdynamic = "-rdynamic"
local binary_extension = ""
if shellout(CC .. " -dumpmachine"):match("mingw") then
	rdynamic = ""
	binary_extension = ".exe"
end

local compile_command = table.concat({
	CC,
	"-Os",
	outfilename,
	-- Link with Lua modules first to avoid linking errors.
	table.concat(module_link_libraries, " "),
	table.concat(dep_library_files, " "),
	rdynamic,
	"-lm",
	link_with_libdl,
	"-o " .. mainlua.basename_noextension .. binary_extension,
	table.concat(other_arguments, " "),
}, " ")
print(compile_command)
local ok = execute(compile_command)
if ok then
	os.exit(0)
else
	os.exit(1)
end
]==========]
local luanite_version = "1.0"

local function rm_dir(path)
    os.execute(('rm -rf "%s"'):format(path))
end

local function has_make()
    local ok, _, code = os.execute("command -v make >/dev/null 2>&1")
    return ok == true or code == 0
end

local function exec_ok(ret)
    if type(ret) == "boolean" then
        return ret
    elseif type(ret) == "number" then
        return ret == 0
    else
        return false
    end
end

local function has_command(cmd)
    -- returns true if command exists in PATH
    local ok = os.execute(('command -v %s >/dev/null 2>&1'):format(cmd))
    return exec_ok(ok)
end

local function has_cc()
    return has_command('cc') or has_command('gcc') or has_command('clang')
end

local function init_proj(dir)
    os.execute(('mkdir -p %s/app'):format(dir))
    os.execute(('mkdir -p %s/luanite'):format(dir))
    os.execute(('mkdir -p %s/bin'):format(dir))

    local config = io.open(('%s/luanite.project'):format(dir), 'w')
    if config then
        config:write([[name = "unspecified"
version = "1.0"
entry = "main"]])
        config:close()
        print('Added a config file.')
    else
        print(
        'Failed to add a config to the project. Please retry first and afterwards notify the developer of this error.')
        rm_dir(dir)
        os.exit(1)
    end

    if not has_make() then
        print(
            'Luanite requires "make" tool as a dependency for building Lua 5.4.6 from source upon creating a new luanite project. Please install it.')
        rm_dir(dir)
        os.exit(1)
    end

    if not has_cc() then
        print(
            'Luanite requires a C compiler (cc, gcc, or clang) to build Lua 5.4.6. Please install one.')
        rm_dir(dir)
        os.exit(1)
    end

    local tarball = 'lua-5.4.6.tar.gz'
    local tarball_path = ('%s/luanite/%s'):format(dir, tarball)
    local url = 'https://www.lua.org/ftp/lua-5.4.6.tar.gz'
    local dl_cmd = ('curl -L "%s" -o "%s"'):format(url, tarball_path)
    print('Downloading Lua 5.4.6...')
    local ret = os.execute(dl_cmd)
    if not exec_ok(ret) then
        print("Failed to download Lua 5.4.6 tarball. Please check your internet connection.")
        rm_dir(dir)
        os.exit(1)
    end

    print("Extracting Lua...")
    local extract_cmd = ('tar -xzf "%s" -C "%s/luanite/"'):format(tarball_path, dir)
    local extract_ok = os.execute(extract_cmd)
    if not exec_ok(extract_ok) then
        print('Failed to extract Lua 5.4.6 source archive via "tar" tool.')
        rm_dir(dir)
        os.exit(1)
    end

    os.remove(tarball_path)

    print("Building Lua...")
    local make_cmd = ('cd "%s/luanite/lua-5.4.6" && make linux > /dev/null 2>&1'):format(dir)
    local build_ok = os.execute(make_cmd)
    if not exec_ok(build_ok) then
        print("Failed to build Lua 5.4.6. Please retry first, if it still does not work please notify the developer.")
        rm_dir(dir)
        os.exit(1)
    end

    local ls_path = ('%s/luanite/luastatic.lua'):format(dir)
    local ls_file = io.open(ls_path, 'w')
    if ls_file then
        ls_file:write(luastatic_source)
        ls_file:close()
        print('Added luastatic to the project.')
    else
        print(
        'Failed to add luastatic to the project. Please retry first and afterwards notify the developer of this error.')
        rm_dir(dir)
        os.exit(1)
    end

    local main_path = ('%s/app/main.lua'):format(dir)
    local main_file = io.open(main_path, 'w')
    if main_file then
        main_file:write([[print('Hello, Luanite!')]])
        main_file:close()
        print('Added an entry point to the project.')
    else
        print(
        'Failed to add an entry point to the project. Please retry first and afterwards notify the developer of this error.')
        rm_dir(dir)
        os.exit(1)
    end

    print(('A new Luanite project has been initialized in "%s" successfully.'):format(dir))
end

local function is_luanite_root(dir)
    local function exists(path)
        local f = io.open(path, "r")
        if f then f:close() return true else return false end
    end

    local function is_dir(path)
        local p = io.popen('[ -d "' .. path .. '" ] && echo "dir" || echo "no"')
        local res = p:read("*l")
        p:close()
        return res == "dir"
    end

    return is_dir(dir .. "/app") and is_dir(dir .. "/bin") and is_dir(dir .. "/luanite") and exists(dir .. "/luanite.project")
end

local function parse_config(path)
    local conf = {}
    for line in io.lines(path) do
        local key, val = line:match('^(%w+)%s*=%s*"(.-)"$')
        if key and val then
            conf[key] = val
        end
    end

    if not conf['entry'] then
        conf['entry'] = 'main'
        print('WARNING: No "entry" key found in the luanite.project config. Automatically setting it to "main".')
    end

    if not conf['name'] then
        conf['name'] = 'unspecified'
        print('WARNING: No "name" key found in the luanite.project config. Automatically setting it to "unspecified".')
    end

    if not conf['version'] then
        conf['version'] = '1.0'
        print('WARNING: No "version" key found in the luanite.project config. Automatically setting it to "1.0".')
    end

    return conf
end

local function build_proj()
    local lroot = os.getenv("PWD") or (function()
        local pipe = io.popen("pwd")
        local result = pipe:read("*l")
        pipe:close()
        return result
    end)()

    if not has_cc() then
        print(
            'Luanite requires a C compiler (cc, gcc, or clang) to build a standalone executable. Please install one.')
        return false, lroot
    end

    if not is_luanite_root(lroot) then
        print("Not a valid Luanite project root directory.")
        return false, lroot
    end

    local conf_path = lroot .. "/luanite.project"
    local config = parse_config(conf_path)

    local proj_name = config.name or "unspecified"
    local entry = config.entry or "main"

    local app_dir = lroot .. "/app"
    local luanite_dir = lroot .. "/luanite"
    local bin_dir = lroot .. "/bin"

    local entry_file = entry .. ".lua"

    local p = io.popen('find "' .. app_dir .. '" -type f -name "*.lua"')
    local files = {}
    for file in p:lines() do
        local rel = file:sub(#app_dir + 2)
        table.insert(files, rel)
    end
    p:close()

    if #files == 0 then
        print("No Lua source files found in app/. Aborting.")
        return false, lroot
    end

    local lua_bin = luanite_dir .. "/lua-5.4.6/src/lua"
    local luastatic_lua = luanite_dir .. "/luastatic.lua"
    local liblua_a = luanite_dir .. "/lua-5.4.6/src/liblua.a"
    local include_path = luanite_dir .. "/lua-5.4.6/src"

    local cmd = {
        'cd "' .. app_dir .. '"',
        '&&',
        lua_bin,
        luastatic_lua,
        entry_file,
    }
    for _, f in ipairs(files) do
        if f ~= entry_file then
            table.insert(cmd, f)
        end
    end
    table.insert(cmd, liblua_a)
    table.insert(cmd, "-I" .. include_path)
    table.insert(cmd, "-o")
    table.insert(cmd, bin_dir .. "/" .. proj_name)

    local full_cmd = table.concat(cmd, " ") .. ' > /dev/null 2>&1'

    local ret = os.execute(full_cmd)
    if not exec_ok(ret) then
        print("Build failed. Please check your code and environment.")
        return false, lroot
    end

    os.execute(('rm -f "%s"/*.luastatic.c'):format(app_dir))

    print("Build succeeded! Executable created at " .. bin_dir .. "/" .. proj_name)
    return true, lroot
end

local callbacks = {
    uc = function()
        print('Undefined command. Use "luanite help" to see the list of available commands.')
    end,

    ['help'] = function()
        print(([[Luanite v%s
    luanite help - shows this message
    luanite version - shows Luanite's version
    luanite license - shows information regarding Luanite's license
    luanite init <Directory> - create a new Luanite project in the specified directory, works solely with empty directories
    luanite build - builds a standalone executable, needs to be ran at the root of a Luanite project
    luanite run - builds a standalone executable and runs it afterwards, needs to be ran at the root of a Luanite project]])
        :format(luanite_version))
    end,

    ['version'] = function()
        print(('Luanite version: %s'):format(luanite_version))
    end,

    ['license'] = function()
        print([[Luanite
    Copyright (C) 2025 tixonochek

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License version 3
    along with this program. If not, see https://www.gnu.org/licenses/.]])
    end,

    ['init'] = function()
        if not arg[2] then
            print('You need to specify a directory for this command to work.')
            os.exit(1)
        end
        local pdir = arg[2]

        local test = io.popen('test -d ' .. pdir .. ' && echo yes || echo no', 'r')
        local exists = test:read('*l') == 'yes'
        test:close()

        if exists then
            local ls = io.popen('ls -A ' .. pdir, 'r')
            local is_empty = ls:read('*a') == ''
            ls:close()

            if is_empty then
                init_proj(pdir)
            else
                print(
                    'The directory is not empty, which is necessary for the "luanite init" command to work and create a new project.')
                os.exit(1)
            end
        else
            local test_2 = io.popen('test -f "' .. pdir .. '" && echo yes || echo no', 'r')
            local is_file = test_2:read('*l') == 'yes'
            test_2:close()

            if is_file then
                print('The path you provided is a file, but a directory is necessary.')
                os.exit(1)
            else
                os.execute('mkdir -p "' .. pdir .. '"')
                init_proj(pdir)
            end
        end
    end,

    ['build'] = function ()
        local success, _ = build_proj()
        if not success then
            os.exit(1)
        end
    end,
    
    ['run'] = function ()
        local success, lroot = build_proj()
        if not success then
            os.exit(1)
        end
    
        local config = parse_config(lroot .. "/luanite.project")
        local proj_name = config.name or "unspecified"
        local bin_path = lroot .. "/bin/" .. proj_name
    
        print("Running the executable...\n")
        os.execute(bin_path)
    end
}

if #arg < 1 then
    print('Zero arguments have been provided. Use "luanite help" to see the list of available commands.')
    os.exit(1)
end

if callbacks[arg[1]] then
    callbacks[arg[1]]()
    os.exit(0)
else
    callbacks.uc()
    os.exit(1)
end
