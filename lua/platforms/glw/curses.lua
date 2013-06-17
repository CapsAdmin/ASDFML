
if LINUX then
	ffi.cdef[[
		/* Type declarations. */
	
		typedef struct {
		  short	   y;			/* current pseudo-cursor */
		  short	   x;
		  short      _maxy;			/* max coordinates */
		  short      _maxx;
		  short      _begy;			/* origin on screen */
		  short      _begx;
		  short	   _flags;			/* window properties */
		} WINDOW;
	]]
end

if WINDOWS then
	ffi.cdef[[
		/* Type declarations. */
	
		typedef struct {
		  int	   y;			/* current pseudo-cursor */
		  int	   x;
		  int      _maxy;			/* max coordinates */
		  int      _maxx;
		  int      _begy;			/* origin on screen */
		  int      _begx;
		  int	   _flags;			/* window properties */
		  int	   _attrs;			/* attributes of written characters */
		  int      _tabsize;			/* tab character size */
		  bool	   _clear;			/* causes clear at next refresh */
		  bool	   _leave;			/* leaves cursor as it happens */
		  bool	   _scroll;			/* allows window scrolling */
		  bool	   _nodelay;			/* input character wait flag */
		  bool	   _keypad;			/* flags keypad key mode active */
		  int    **_line;			/* pointer to line pointer array */
		  int	  *_minchng;			/* First changed character in line */
		  int	  *_maxchng;			/* Last changed character in line */
		  int	   _regtop;			/* Top/bottom of scrolling region */
		  int	   _regbottom;
		} WINDOW;
	]]
end

ffi.cdef[[		
	WINDOW *initscr();
	void timeout(int delay);
	int wtimeout(WINDOW *win, int delay);
	void halfdelay(int delay);
	void cbreak();
	void nocbreak();
	void noecho();
	int getch();
	int wgetch(WINDOW *win);

	int idlok(WINDOW *win, bool bf);
	int leaveok(WINDOW *win, bool bf);
	int keypad(WINDOW *win, bool bf);
	int scrollok(WINDOW *win, bool bf);

	int nodelay(WINDOW *win, bool b);
	int notimeout(WINDOW *win, bool b);
	WINDOW *derwin(WINDOW*, int nlines, int ncols, int begin_y, int begin_x);
	int wrefresh(WINDOW *win);
	int refresh();
	int box(WINDOW *win, int, int);
	int werase(WINDOW *win);
	int wclear(WINDOW *win);
	int hline(const char *, int);
	int COLS;
	int LINES;
	const char *killchar();
	void keypad(WINDOW*, bool);
	const char *keyname(int c);
	int waddstr(WINDOW *win, const char *chstr);
	int wmove(WINDOW *win, int y, int x);
	int resize_term(int y, int x);
	int setscrreg(int top, int bot);
	
	void getyx(WINDOW *win, int y, int x);

	WINDOW* stdscr;
	int printw(const char* format, ...);
	int wprintw(WINDOW*, const char* format, ...);
	int mvprintw(int y, int x, const char* format, ...);
	int start_color();
]]

if _E.CURSES_INIT then return end

-- whyyyyyyyyy
if WINDOWS then
	os.execute("mode con:cols=140 lines=50")
end

local curses = ffi.load(jit.os == "Linux" and "ncurses" or "pdcurses")
local parent = curses.initscr()

local log_window = curses.derwin(parent, curses.LINES - 2, curses.COLS, 0, 0)
local line_window = curses.derwin(parent, 1, curses.COLS, curses.LINES - 1, 0)

local function gety()
	return line_window.y
end

local function getx()	
	return line_window.x
end

--curses.start_color()
curses.cbreak()
curses.noecho()

curses.nodelay(line_window, 1)
curses.keypad(line_window, 1)

curses.scrollok(log_window, 1)

curses.mvprintw(curses.LINES - 2, 0, string.rep("-", curses.COLS))
curses.refresh()

io.old_write = io.old_write or io.write

function io.write(a)
	curses.wprintw(log_window, a .. "\n")
	curses.wrefresh(log_window)
end

_E.CURSES_INIT = true

local function get_char()
	return curses.wgetch(line_window)
end

local function clear(str)
	local y, x = gety(), getx()
	
	curses.wclear(line_window)
	
	if str then
		curses.waddstr(line_window, str)
		curses.wmove(line_window, y, x)
	else
		curses.wmove(line_window, y, 0)
	end
	
	curses.wrefresh(line_window)
end

local function get_key_name(num)
	return curses.keyname(num)
end

local function move_cursor(x)
	curses.wmove(line_window, gety(), getx() + x)
	curses.wrefresh(line_window)
end

local function set_cursor_pos(x)
	curses.wmove(line_window, 0, x)
	curses.wrefresh(line_window)
end

local function load_history()
	return luadata.ReadFile("%DATA%/cmd_history.txt")
end

local function save_history(tbl)
	return luadata.WriteFile("%DATA%/cmd_history.txt", tbl)
end

local line = ""
local history = load_history()
local scroll = 0

local function insert_char(char)
	if #line == 0 then
		line = line .. char
	elseif subpos == #line then
		line = line .. char
	else
		line = line:sub(1, getx()) .. char .. line:sub(getx() + 1)
	end

	clear(line)

	move_cursor(1)
end

local current_table = _G
local table_scroll = 0
local in_function

local translate = 
{
	[32] = "KEY_SPACE",
	[9] = "KEY_TAB",
	[10] = "KEY_ENTER",
	[8] = "KEY_BACKSPACE",
	[127] = "KEY_BACKSPACE",
}

event.AddListener("OnUpdate", "curses", function()
	local byte = get_char()
	
	if byte < 0 then return end
	
	local key = translate[byte] or ffi.string(get_key_name(byte))
	if not key:find("KEY_") then key = nil end
			
	if key then					
		key = ffi.string(key)
		
		if event.Call("OnConsoleKeyPressed", key) == false then return end
		
		if key == "KEY_UP" then
			scroll = scroll - 1
			line = history[scroll%#history+1] or line
			set_cursor_pos(#line)
		elseif key == "KEY_DOWN" then
			scroll = scroll + 1
			line = history[scroll%#history+1] or line
			set_cursor_pos(#line)
		end

		if key == "KEY_LEFT" then
			 move_cursor(-1)
		elseif key == "KEY_RIGHT" then
			 move_cursor(1)
		end

		if key == "KEY_HOME" then
			set_cursor_pos(0)
		elseif key == "KEY_END" then
			set_cursor_pos(#line)
		end

		-- space
		if key == "KEY_SPACE" then
			insert_char(" ")
		end

		-- tab
		if key == "KEY_TAB" then
			local start, stop, last_word = line:find("([_%a%d]-)$")
			if last_word then
				local pattern = "^" .. last_word
								
				if (not line:find("%(") or not line:find("%)")) and not line:find("logn") then
					in_function = false
				end
								
				if not in_function then
					current_table = line:explode(".")
											
					local tbl = _G
					
					for k,v in pairs(current_table) do
						if type(tbl[v]) == "table" then
							tbl = tbl[v]
						else
							break
						end
					end
					
					current_table = tbl or _G						
				end
				
				if in_function then
					local start = line:match("(.+%.)")
					if start then
						local tbl = {}
						
						for k,v in pairs(current_table) do
							table.insert(tbl, {k=k,v=v})
						end
						
						if #tbl > 0 then
							table.sort(tbl, function(a, b) return a.k > b.k end)
							table_scroll = table_scroll + 1
							
							local data = tbl[table_scroll%#tbl + 1]
							
							if type(data.v) == "function" then
								line = start .. data.k .. "()"
								set_cursor_pos(#line)
								move_cursor(-1)
								in_function = true
							else
								line = "logn(" .. start .. data.k .. ")"
								set_cursor_pos(#line)
								move_cursor(-1)
							end
						end
					end
				else						
					for k,v in pairs(current_table) do
						k = tostring(k)
						
						if k:find(pattern) then
							line = line:sub(0, start-1) .. k
							if type(v) == "table" then 
								current_table = v 
								line = line .. "."
								set_cursor_pos(#line)
							elseif type(v) == "function" then
								line = line .. "()"
								set_cursor_pos(#line)
								move_cursor(-1)
								in_function = true
							else
								line = "logn(" .. line .. ")"
							end
							break
						end
					end
				end
			end
		end

		-- backspace
		if key == "KEY_BACKSPACE" then
			if getx() > 0 then
				local char = line:sub(1, getx())
				
				if char == "." then
					current_table = previous_table
				end
				
				line = line:sub(1, getx() - 1) .. line:sub(getx() + 1)
				move_cursor(-1)
			else
				clear()
			end
		elseif key == "KEY_DC" then
			if getx() > 0 then
				line = line:sub(1, getx()) .. line:sub(getx() + 2)
			else
				clear()
			end
		end

		-- enter
		if key == "KEY_ENTER" then
			clear()

			if line ~= "" then
				if event.Call("OnLineEntered", line) ~= false then
					log(line, "\n")
					
					local res, err = console.RunString(line)

					if not res then
						log(err, "\n")
					end
				end
				
				for key, str in pairs(history) do
					if str == line then
						table.remove(history, key)
					end
				end
				
				table.insert(history, line)
				save_history(history)

				scroll = 0
				current_table = _G
				in_function = false
				line = ""
				clear()
			end
		end

		clear(line)
	elseif byte < 256 then
		local char = string.char(byte)
		
		if event.Call("OnConsoleCharPressed", char) == false then return end
		
		insert_char(char)
	end
end)

do -- curses keys
	local trigger = input.SetupInputEvent("ConsoleKey")

	event.AddListener("OnConsoleKeyPressed", "input", function(key)
		local ret = trigger(key, true)
		
		-- :(
		timer.Simple(0, function() trigger(key, false) end)
		
		return ret
	end)

	local trigger = input.SetupInputEvent("ConsoleChar")

	event.AddListener("OnConsoleCharPressed", "input", function(char)
		local ret = trigger(char, true)
		
		-- :(
		timer.Simple(0, function() trigger(char, false) end)
		
		return ret
	end)
end
