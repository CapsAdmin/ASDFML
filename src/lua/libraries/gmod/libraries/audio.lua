do
	function gine.env.CreateSound(ent, path, filter)
		local self = audio.CreateSource("sound/" .. path)

		return gine.WrapObject(self, "CSoundPatch")
	end

	local META = gine.GetMetaTable("CSoundPatch")

	function META:SetSoundLevel()

	end

	function META:Stop()
		self.__obj:Stop()
	end

	function META:Play()
		self.__obj:Play()
	end

	function META:IsPlaying()
		return self.__obj:IsPlaying()
	end
end

function gine.env.surface.PlaySound(path)
	audio.CreateSource("sound/" .. path):Play()
end
