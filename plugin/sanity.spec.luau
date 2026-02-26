return function()
	describe("sanity", function()
		it("should pass a basic assertion", function()
			expect(1 + 1).to.equal(2)
		end)

		it("should have access to game services", function()
			local ReplicatedStorage = game:GetService("ReplicatedStorage")
			expect(ReplicatedStorage).to.be.ok()
		end)
	end)
end
