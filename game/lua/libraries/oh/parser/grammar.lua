local META = ... or oh.parser_meta

function META:ReadExpressions()
	local out = {}
	while true do
		table.insert(out, self:ReadExpression())

		if not self:IsValue(",") then
			break
		end

		self:NextToken()
	end

	return out
end

function META:ReadAssignment()
	local left = self:ReadExpressions()

	if self:ReadIfValue("=") then
		return {type = "assignment", left = left, right = self:ReadExpressions()}
	else
		return {type = "assignment", left = left}
	end
end

function META:ReadTable()
	local tree = {}
	tree.type = "table"
	tree.children = {}

	self:ReadExpectValue("{")

	while true do
		local token = self:GetToken()
		if not token then return tree end


		local ret = event.Call("OhReadTable", self, token)

		if ret then
			table.insert(tree.children, ret)
		elseif token.value == "}" then
			self:NextToken()
			return tree
		elseif self:IsValue("=", 1) then
			local index = self:GetToken()
			self:NextToken()
			self:NextToken()

			local data = {}
			data.type = "assignment"
			data.expressions = {self:ReadExpression()}
			data.indices = {index}

			table.insert(tree.children, data)
		elseif token.value == "[" then
			self:NextToken()
			local val = self:ReadExpression()
			self:ReadExpectValue("]")
			self:ReadExpectValue("=")

			local data = {}
			data.type = "assignment"
			data.expressions = {self:ReadExpression()}
			data.indices = {val}
			data.expression_key = true
			table.insert(tree.children, data)
		else
			local data = {}
			data.type = "value"
			data.value =  self:ReadExpression()
			table.insert(tree.children, data)
		end

		if self:IsValue("}") then
			self:Back()
		else
			self:CheckTokenValue(self:GetToken(), ",")
		end

		self:NextToken()
	end

	return tree
end

function META:ReadIndexExpression()
	local out = {}

	for _ = 1, self:GetLength() do
		local token = self:ReadToken()

		if not token then break end

		if token.type == "letter" and not oh.syntax.keywords[token.value] then
			if _ > 1 and (self:IsType("letter", -2) or self:IsValue("]", -2)) then
				self:Back()
				break
			end
			table.insert(out, {type = "index", operator = _ == 1 and {value = ""} or self:GetToken(-2), value = token})
		elseif token.value == "[" then
			table.insert(out, {type = "index_expression", value = self:ReadExpression()})
			self:ReadExpectValue("]")
		elseif token.value == "(" and not out[1] then
			self:NextToken()
			local val = self:ReadExpression()
			table.insert(out, {type = "call2", value = val})
		elseif token.value == "(" then
			self:Back()

			-- fix this branch
			if self:IsValue(")", 1) then
				table.insert(out, {type = "call", arguments = {}})
				self:NextToken()
				self:NextToken()
			else
				while self:ReadIsValue("(") do
					table.insert(out, {type = "call", arguments = self:ReadExpressions()})
					self:ReadExpectValue(")")
				end
				self:Back()
			end
			if self:IsType("letter") then
				break
			end
		elseif token.value == "{" then
			self:Back()
			table.insert(out, {type = "call", arguments = {self:ReadTable()}})
		elseif token.type == "string" then
			table.insert(out, {type = "call", arguments = {token}})
		elseif token.value == "." or token.value == ":" then

		else
			self:Back()
			break
		end
	end

	return out
end

function META:ReadExpression(priority)
	priority = priority or 0

	local val

	local token = self:GetToken()

	if not token then return end

	local ret = event.Call("OhReadExpression", self, token)

	if ret then
		val = ret
	elseif oh.syntax.IsUnaryOperator(token) then
		val = {type = "unary", value = self:ReadToken().value, argument = self:ReadExpression(0)}
	elseif self:ReadIfValue("(") then
		val = self:ReadExpression(0)
		self:ReadExpectValue(")")
		if self:IsValue(":") then
			local right = self:ReadIndexExpression()
			table.insert(right, 1, val)
			val = {type = "index_call_expression", value = right}
		end
	elseif oh.syntax.IsValue(token) then
		val = self:ReadToken()
	elseif token.value == ":" then
		val = {type = "index_call_expression", value = self:ReadIndexExpression()}
	elseif token.value == "{" then
		val = self:ReadTable()
	elseif token.value == "function" then
		self:NextToken()
		self:ReadExpectValue("(")
		local arguments = self:ReadExpressions()
		self:ReadExpectValue(")")
		local body = self:ReadBody("end")
		val = {type = "function", arguments = arguments, body = body}
	elseif token.type == "letter" and not oh.syntax.keywords[token.value] then
		val = {type = "index_call_expression", value = self:ReadIndexExpression()}
	elseif token.value == ";" then
		self:NextToken()
		return
	else
		return val
	end

	local token = self:GetToken()

	if not token then return val end

	while oh.syntax.operators[token.value] and oh.syntax.operators[token.value][1] > priority do
		local op = self:GetToken()
		if not op or not oh.syntax.operators[op.value] then return val end
		self:NextToken()
		val = {type = "operator", value = op.value, left = val, right = self:ReadExpression(oh.syntax.operators[op.value][2])}
	end

	return val
end

function META:ReadBody(stop)
	if type(stop) == "string" then
		stop = {[stop] = true}
	end

	local out = {}

	for _ = 1, self:GetLength() do
		local token = self:ReadToken()

		if not token then break end

		if stop and stop[token.value] then
			return out
		end

		local ret = event.Call("OhReadBody", self, token)

		if ret then
			table.insert(out, ret)
		elseif token.value == "local" then
			if self:GetToken().value == "function" then
				self:NextToken()
				local data = {}
				data.type = "function"
				data.is_local = true
				data.expression = self:ReadExpression()
				data.body = self:ReadBody("end")
				table.insert(out, data)
			else
				local data = self:ReadAssignment()

				data.is_local = true
				table.insert(out, data)
			end
		elseif token.value == "return" then
			local data = {}
			data.type = "return"
			data.expressions = self:ReadExpressions()
			table.insert(out, data)
		elseif token.value == "break" then
			local data = {}
			data.type = "break"
			table.insert(out, data)
		elseif token.value == "do" then
			local data = {}
			data.type = "do"
			data.body = self:ReadBody("end")
			table.insert(out, data)
		elseif token.value == "if" then
			local data = {}
			data.type = "if"
			data.statements = {}
			self:Back() -- we want to read the if in the upcoming loop

			for _ = 1, self:GetLength() do
				local token = self:ReadToken()

				if token.value == "end" then
					break
				end

				if token.value == "else" then
					table.insert(data.statements, {
						body = self:ReadBody("end"),
						token = token,
					})
				else
					local expr = self:ReadExpression()

					table.print(expr)

					self:ReadExpectValue("then")
					table.insert(data.statements, {
						expr = expr,
						body = self:ReadBody({["else"] = true, ["elseif"] = true, ["end"] = true}, true),
						token = token,
					})
				end

				self:Back() -- we want to read the else/elseif/end in the next iteration
			end
			table.insert(out, data)
		elseif token.value == "while" then
			local data = {}
			data.type = "while"
			data.expr = self:ReadExpression()
			self:ReadExpectValue("do")
			data.body = self:ReadBody("end")
			table.insert(out, data)
		elseif token.value == "for" then
			local data = {}
			data.type = "for"

			if self:GetToken(1).value == "=" then
				data.iloop = true
				data.name = self:ReadExpression()
				self:ReadExpectValue("=")
				data.val = self:ReadExpression()
				self:ReadExpectValue(",")
				data.max = self:ReadExpression()

				if self:IsValue(",") then
					self:NextToken()
					data.incr = self:ReadExpression()
				end

				self:ReadExpectValue("do")

				data.body = self:ReadBody("end")
				table.insert(out, data)
			else
				local names = self:ReadExpressions()

				self:ReadExpectValue("in")

				data.iloop = false
				data.names = names
				data.expression = self:ReadExpression()
				self:ReadExpectValue("do")
				data.body = self:ReadBody("end")

				table.insert(out, data)
			end
		elseif token.value == "function" then
			local data = {}
			data.type = "function"
			data.arguments = {}
			data.is_local = false
			data.expression = self:ReadExpression()
			data.body = self:ReadBody("end")
			table.insert(out, data)
		elseif token.value == "(" then
			table.insert(out, {type = "call", value = assert(self:ReadExpression())})
			self:ReadExpectValue(")")
		elseif token.type == "letter" then
			self:Back() -- we want to include the current letter in the loop
			table.insert(out, self:ReadAssignment())
		elseif token.value == "goto" then
			self:NextToken()
			self:ReadExpectType("letter")
		elseif token.value == ";" then -- hmmm

		else
			self:Back()
			print(self:GetToken())
			table.insert(out, {type = "call", value = assert(self:ReadExpression())})
		end
	end

	return out
end

if RELOAD then
	oh.Test()
end