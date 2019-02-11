local asm, META = ...

if not asm then asm = _G.asm end
if not META then META = asm.asm_meta end

local ffi = require("ffi")

asm.Reg64 = {
	"rax", "rcx", "rdx", "rbx",
	"rsp", "rbp", "rsi", "rdi",
	"r8", "r9", "r10", "r11",
	"r12", "r13", "r14","r15",
}
asm.Reg32 = {
	"eax", "ecx", "edx", "ebx",
	"esp", "ebp", "esi", "edi",
	"r8d", "r9d", "r10d", "r11d",
	"r12d", "r13d", "r14d", "r15d",
}
asm.Reg16 = {
	"ax", "cx", "dx", "bx",
	"sp", "bp", "si", "di",
	"r8w", "r9w", "r10w", "r11w",
	"r12w", "r13w", "r14w", "r15w",
}
asm.Reg8 = {
	"al", "cl", "dl","bl",
	"ah", "ch", "dh", "bh",
	"spl", "bpl", "sil", "dil",
	"r8b", "r9b", "r10b", "r11b",
	"r12b", "r13b", "r14b", "r15b",
}

local REX = {
	_ = 0b01000000, -- Fixed base bit pattern

	W = 0b00001000, -- 64bit mode

	R = 0b00000100, -- r8-r15
	X = 0b00000010, -- r8-r15
	B = 0b00000001, -- r8-r15
}

local REG = {
	0b000, -- (r/e)-ax / r08-(d/w/b)
	0b001, -- (r/e)-cx / r09-(d/w/b)
	0b010, -- (r/e)-dx / r10-(d/w/b)
	0b011, -- (r/e)-bx / r11-(d/w/b)
	0b100, -- (r/e)-sp / r12-(d/w/b)
	0b101, -- (r/e)-bp / r13-(d/w/b)
	0b110, -- (r/e)-si / r14-(d/w/b)
	0b111, -- (r/e)-di / r15-(d/w/b)
}

asm.KnownBits = {"64", "32", "16", "8"}

asm.RegToSize = {}
asm.RegLookup = {}
asm.r = asm.RegLookup

for _, bit in ipairs(asm.KnownBits) do
	for i, reg in ipairs(asm["Reg" .. bit]) do
		asm.RegToSize[reg] = bit
		asm.RegLookup[reg] = i - 1
	end
end

local function infer_reg(reg, bits)
	if type(reg) == "string" then
		bits = bits or asm.RegToSize[reg]
		reg = asm.r[reg]
	end

	bits = bits or "64"

	return reg, bits
end

local function infer_imm(num, bits)
	if type(num) == "cdata" then
		bits = tostring(ffi.sizeof(num)*8)
	elseif false then
		if num <= 0xFF then
			bits = "8"
		elseif num <= 0xFFFF then
			bits = "16"
		end
	end

	return num, bits or "32"
end

function META:WriteRex(i)
	if i >= 8 then
		self:WriteData(bit.bor(REX._, REX.W, REX.B))
	else
		self:WriteData(bit.bor(REX._, REX.W))
	end
end

do
	local lookup = {
		["64"] = ffi.typeof("uint64_t[1]"),
		["32"] = ffi.typeof("uint32_t[1]"),
		["16"] = ffi.typeof("uint16_t[1]"),
		["8"] = ffi.typeof("uint8_t[1]"),
	}

	function META:WriteNumber(num, bits)
		self:WriteData(lookup[bits](num))
	end
end

function META:MoveImm32Reg64(src, dst)
	self:MoveImmReg(src, dst, "32", "64")
end

function META:MoveImm64Reg64(src, dst)
	self:MoveImmReg(src, dst, "64", "64")
end

function META:MoveRegMemReg(src, dst, src_offset, src_scale, src_scalefactor, src_bits, dst_bits, src_scale_bits)
	src, src_bits = infer_reg(src, src_bits)
	dst, dst_bits = infer_reg(dst, dst_bits)

	if src_scale then
		src_scale, src_scale_bits = infer_reg(src_scale, src_scale_bits)
	end

	local src_dst = bit.bor(0x0, bit.bor(bit.lshift(dst, 3), bit.band(src, 7)))

	local rex_flags = REX.BASE

	if dst_bits == "64" then
		rex_flags = bit.bor(rex_flags, REX.W)
	end

	if dst >= 8 then
		rex_flags = bit.bor(rex_flags, REX.R)
	end

	if src >= 8 then
		rex_flags = bit.bor(rex_flags, REX.B)
	end

	if dst_bits == "64" then
		self:WriteData(rex_flags)

		self:WriteData(0x8b)

		if src == 5 then
			src_dst = src_dst + 64
		elseif src == 13 then
			src_dst = src_dst + 64
		end

		if not src_scale and src_scalefactor then
			src_offset = src_offset or 0
		end

		if src_offset then
			src_dst = src_dst + 0x80
		end

		if src_scale then
			src_dst = src_dst + 0x04
		end

		self:WriteData(src_dst)

		if src_scale then
			local fixme

			if src_scalefactor == 1 then
				fixme = 0
			elseif src_scalefactor == 2 then
				fixme = 1
			elseif src_scalefactor == 4 then
				fixme = 2
			elseif src_scalefactor == 8 then
				fixme = 3
			else
				error("unsupported scale factor")
			end

			self:WriteData((64*fixme) + bit.bor(0x0, bit.bor(bit.lshift(src_scale, 3), bit.band(src, 7))))
		end

		if src_offset then
			self:WriteNumber(src_offset, "32")
		end



		if src == 12 then
			self:WriteData(0x24)
		elseif src == 13 then
			self:WriteData(0x00)
		end

		if src == 5 then
			self:WriteData(0x00)
		elseif src == 4 then
			self:WriteData(0x24)
		end
	elseif dst_bits == "32" then
		if src_bits == "32" then
			self:WriteData(0x67)
		end

		self:WriteData(rex_flags)

		if dst < 8 then

		else
			src_dst = src_dst - 64
		end

		if src == 5 then
			src_dst = src_dst + 64
		elseif src == 13 then
			src_dst = src_dst + 64
		end

		self:WriteData(0x8b, src_dst)

		if src == 12 then
			self:WriteData(0x24)
		elseif src == 13 then
			self:WriteData(0x00)
		end

		if src == 5 then
			self:WriteData(0x00)
		elseif src == 4 then
			self:WriteData(0x24)
		end
	end
end

function META:MoveMemReg(src, dst, src_bits, dst_bits)
	if src_bits == "64" then
		if dst ~= 0 then error("unsupported", 2) end
		self:WriteData(0x48, 0xa1)
	elseif src_bits == "32" then
		if dst_bits == "8" then
			if dst >= 12 then
				self:WriteData(0x44)
			elseif dst >= 8 then
				self:WriteData(0x40)
			end

			self:WriteData(0x8a)

			if dst >= 12 then
				dst = dst - 4
			elseif dst >= 8 then
				dst = dst - 12
			end
		else
			if dst_bits == "64" then
				if dst < 8 then
					self:WriteData(0x48)
				else
					self:WriteData(0x4c)
				end
			else
				if dst_bits == "16" then
					self:WriteData(0x66)
				end

				if dst >= 8 then
					self:WriteData(0x44)
				end
			end

			self:WriteData(0x8b)
		end

		self:WriteData(0x04 + bit.band(dst * 8, 63))
		self:WriteData(0x25)
	else
		error("unsupported", 2)
	end

	self:WriteNumber(src, src_bits)
end

function META:MoveImmReg2(src, dst)
	self:WriteInstruction({
		opcode = "\xb8",
		src = dst,
		imm = ffi.new("uint64_t", src),
	})
end


function META:MoveImmReg(src, dst, src_bits, dst_bits)
	src, src_bits = infer_imm(src, src_bits)
	dst, dst_bits = infer_reg(dst, dst_bits)

	if dst_bits == "32" or dst_bits == "64" then
		self:WriteRex(dst)

		local offset = bit.band(dst, 7)

		if src_bits == "64" then
			self:WriteData(0xB8 + offset)
		elseif src_bits == "32" then
			self:WriteData(0xC7, 0xc0 + offset)
		end
	elseif dst_bits == "16" then
		self:WriteData(0x66)

		if dst >= 8 then
			self:WriteData(0x44)
		end

		self:WriteData(0x8B, 0x4 + bit.band(dst * 8, 63), 0x25)
		src_bits = "32"
	elseif dst_bits == "8" then
		if dst >= 12 then
			self:WriteData(0x44)
		elseif dst >= 8 then
			self:WriteData(0x40)
		end

		self:WriteData(0x8a)

		if dst >= 8 then
			dst = dst - 4
		end

		self:WriteData(0x4 + bit.band(dst * 8, 63))
		self:WriteData(0x25)

		src_bits = "32"
	end

	self:WriteNumber(src, src_bits)
end

function META:PushReg64(src)
	if src >= 8 then
		self:WriteData(0x41)
	end

	self:WriteData(0x50 + bit.band(src, 7))
end

function META:PopReg64(src)
	if src >= 8 then
		self:WriteData(0x41)
	end

	self:WriteData(0x58 + bit.band(src, 7))
end

local function increase_decrease(what, base)
	META[what .. "Reg64"] = function(self, src)
		self:WriteData(
			0x48 + (src >= 8 and 1 or 0),
			0xFF,
			base + bit.band(src, 7)
		)
	end

	META[what .. "Reg32"] = function(self, src)
		if src >= 8 then
			self:WriteData("\x41")
		end

		self:WriteData(0xFF, base + bit.band(src, 7))
	end

	META[what .. "Reg16"] = function(self, src)
		self:WriteData("\x66")

		if src >= 8 then
			self:WriteData("\x41")
		end

		self:WriteData(0xFF, base + bit.band(src, 7))
	end

	META[what .. "Reg8"] = function(self, src)
		if src < 8 then
			self:WriteData("\xFE")
			self:WriteData(base + src)
		elseif src < 12 then
			self:WriteData("\x40\xFE")
			self:WriteData(base + src - 4)
		else
			self:WriteData("\x41\xFE")
			self:WriteData(base + src - 12)
		end
	end
end

increase_decrease("Increment", 0xc0)
increase_decrease("Decrement", 0xc8)

local function generic_reg64_reg64(name, byte, swap)
	META[name] = function(self, dst, src)
		if swap then
			dst, src = src, dst
		end

		if dst < 8 then
			if src < 8 then
				self:WriteData("\x48")
			else
				self:WriteData("\x49")
			end
		else
			if src < 8 then
				self:WriteData("\x4c")
			else
				self:WriteData("\x4d")
			end
		end

		self:WriteData(byte)

		self:WriteData(bit.bor(0xc0, bit.bor(bit.lshift(dst, 3), bit.band(src, 7))))
	end
end

generic_reg64_reg64("SubtractReg64Reg64", "\x29")
generic_reg64_reg64("AddReg64Reg64", "\x01")
generic_reg64_reg64("IntegerMultiplyReg64Reg64", "\x0f\xaf", true)
generic_reg64_reg64("MoveReg64Reg64", "\x89")

function META:DivideReg64(src) self:WriteData(0x48 + src < 8 and 0 or 1, 0xF7, 0xF0 + bit.band(i, 7)) end
function META:MultiplyReg64(src) self:WriteData(0x48 + src < 8 and 0 or 1, 0xF7, 0xE0 + bit.band(i, 7)) end

function META:MoveReg8Reg64(dst, src)
	local shift = src

	if shift >= 8 then
		shift = shift - 8

		if src >= 12 then
			error("NYI")
		else
			if dst < 8 then
				self:WriteData(string.char(0x41, 0x8a, (8*dst) + shift))
			elseif dst < 12 then
				self:WriteData(string.char(0x41, 0x8a, (8*dst) + shift - 32))
			else
				self:WriteData(string.char(0x45, 0x8a, (8*dst) + shift - 96))
			end
		end
	else
		if dst < 8 then
			self:WriteData(string.char(0x8a, (8*dst) + shift ))
		elseif dst < 12 then
			self:WriteData(string.char(0x40, 0x8a, (8*dst)  + shift - 32 ))
		else
			self:WriteData(string.char(0x44, 0x8a, (8*dst)  + shift - 96))
		end
	end
end

function META:MoveReg64Reg8(dst, src)
	local shift = src

	if shift >= 8 then
		shift = shift - 8

		if src >= 12 then
			error("NYI")
		else
			if dst < 8 then
				self:WriteData(string.char(0x41, 0x8a, (8*dst) + shift))
			elseif dst < 12 then
				self:WriteData(string.char(0x41, 0x8a, (8*dst) + shift - 32))
			else
				self:WriteData(string.char(0x45, 0x8a, (8*dst) + shift - 96))
			end
		end
	else
		if dst < 8 then
			self:WriteData(string.char(0x8a, (8*dst) + shift ))
		elseif dst < 12 then
			self:WriteData(string.char(0x40, 0x8a, (8*dst)  + shift - 32 ))
		else
			self:WriteData(string.char(0x44, 0x8a, (8*dst)  + shift - 96))
		end
	end
end

function META:MoveReg64ToMem64(src, dst)
	if src ~= 0 then error("not supported", 2) end
	self:WriteData("\x48\xa3")
	self:WriteData(ffi.new("uint64_t[1]", dst))
end

function META:MoveReg32ToMem64(src, dst)
	if src ~= 0 then error("not supported", 2) end
	self:WriteData("\xa3")
	self:WriteData(ffi.new("uint64_t[1]", dst))
end

function META:MoveReg16ToMem64(src, dst)
	if src ~= 0 then error("not supported", 2) end
	self:WriteData("\x66\xa3")
	self:WriteData(ffi.new("uint64_t[1]", dst))
end

function META:MoveReg8ToMem64(src, dst)
	if src ~= 0 then error("not supported", 2) end
	self:WriteData("\xa2")
	self:WriteData(ffi.new("uint64_t[1]", dst))
end

function META:MoveReg64ToMem32(src, dst)
	if src < 8 then
		self:WriteData(string.char(0x48, 0x89, 0x04 + (8*src), 0x25))
	else
		self:WriteData(string.char(0x4c, 0x89, 0x04 + (8*(src-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", dst))
end

function META:MoveReg32ToMem32(src, dst)
	if src < 8 then
		self:WriteData(string.char(0x89, 0x04 + (8*src), 0x25), 0x25)
	else
		self:WriteData(string.char(0x44, 0x89, 0x04 + (8*(src-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", dst))
end

function META:MoveReg16ToMem32(src, dst)
	if src < 8 then
		self:WriteData(string.char(0x66, 0x89, 0x04 + (8*src), 0x25))
	else
		self:WriteData(string.char(0x66, 0x44, 0x89, 0x04 + (8*(src-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", dst))
end

function META:MoveReg8ToMem32(src, dst)
	if src < 8 then
		self:WriteData(string.char(0x88, 0x04 + (8*src), 0x25))
	elseif src < 12 then
		self:WriteData(string.char(0x40, 0x88, 0x04 + (8*(src)) - 32, 0x25 ))
	else
		self:WriteData(string.char(0x44, 0x88, 0x04 + (8*(src)) - 32 - 64, 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", dst))
end

function META:MoveMem32Reg64(src, dst)
	if dst < 8 then
		self:WriteData(string.char(0x48, 0x8b, 0x04 + (8*dst), 0x25))
	else
		self:WriteData(string.char(0x4c, 0x8b, 0x04 + (8*(dst-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", src))
end
function META:MoveMem32Reg32(src, dst)
	if dst < 8 then
		self:WriteData(string.char(0x8b, 0x04 + (8*dst), 0x25))
	else
		self:WriteData(string.char(0x44, 0x8b, 0x04 + (8*(dst-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", src))
end
function META:MoveMem32Reg16(src, dst)
	if dst < 8 then
		self:WriteData(string.char(0x66, 0x8b, 0x04 + (8*dst), 0x25))
	else
		self:WriteData(string.char(0x66, 0x44, 0x8b, 0x04 + (8*(dst-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", src))
end
function META:MoveMem32Reg8(src, dst)
	if dst < 8 then
		self:WriteData(string.char(0x8a, 0x04 + (8*dst), 0x25))
	elseif dst < 12 then
		self:WriteData(string.char(0x40, 0x8a, (8*dst) - 28, 0x25))
	else
		self:WriteData(string.char(0x44, 0x8a, (8*dst) - 92, 0x25))
	end

	self:WriteData(ffi.new("uint32_t[1]", src))
end

function META:CompareImm8Reg8(dst, src)
	if src == 0 then
		self:WriteData("\x3c")
	elseif index < 8 then
		self:WriteData(string.char(0x80, 0xf9 + src - 1))
	elseif index < 12 then
		self:WriteData(string.char(0x40, 0x80, 0xf9 + src - 4 - 1))
	else
		self:WriteData(string.char(0x41, 0x80, 0xf9 + src - 12 - 1))
	end

	self:WriteData(ffi.new("uint8_t[1]", dst))
end

function META:CompareImm32Reg64(dst, src)
	if src < 8 then
		self:WriteData(string.char(0x48, 0x3b, 0x04 + (8*src), 0x25))
	else
		self:WriteData(string.char(0x4c, 0x3b, 0x04 + (8*(src-8)), 0x25 ))
	end

	self:WriteData(ffi.new("uint32_t[1]", dst))
end

function META:CompareImm8Reg64(dst, src)
	self:WriteRex(src)
	self:WriteData(0x83, 0xf8 + bit.band(src, 7))
	self:WriteData(ffi.new("uint8_t[1]", dst))
end

function META:Syscall()
	self:WriteData("\x0f\x05")
end

function META:Return()
	self:WriteData("\xc3")
end

function META:JumpNotEqualImm8(dst)
	dst = dst - self.Position - 2

	self:WriteData("\x75")
	self:WriteData(ffi.new("int8_t[1]", dst))
end

function META:JumpEqualImm8(dst)
	dst = dst - self.Position - 2

	self:WriteData("\x74")
	self:WriteData(ffi.new("int8_t[1]", dst))
end

function META:MoveMemReg64Reg64(src, dst)
	local index = bit.bor(0x0, bit.bor(bit.lshift(dst, 3), src%8))

	-- to be identical to gcc these had to be for some reason
	if src == 5 and dst == 0 then
		self:WriteData(string.char(0x48, 0x8b, 0x45))
	elseif src == 12 and dst == 0 then
		-- (r12) rax: 49 8b 04 24
		self:WriteData(string.char(0x49, 0x8b, 0x04, 0x24))
	elseif src == 13 and dst == 0 then
		-- mov 0x0(r13) rax: 49 8b 45 00
		self:WriteData(string.char(0x49, 0x8b, 0x45, 0x00))
	else
		if src < 8 then
			self:WriteData(string.char(0x48, 0x8b, index))
		else
			self:WriteData(string.char(0x49, 0x8b, index))
		end
	end

	-- to be identical to gcc these had to be for some reason

	-- mov (rsp) rax: 48 8b 04 24
	if src == 4 and dst == 0 then
		self:WriteData("\x24")
	end

	-- mov 0x0(rbp) rax: 48 8b 45 00
	if src == 5 and dst == 0 then
		self:WriteData("\x00")
	end
end

if RELOAD then
	runfile("test.lua")
end
