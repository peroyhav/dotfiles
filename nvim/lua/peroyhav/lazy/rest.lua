return {
	"rest-nvim/rest.nvim",
	dependencies = { "nvim-telescope/telescope.nvim" },
	config = function()
		local telescope = require("telescope")
		telescope.load_extension("rest")
		vim.keymap.set("n", "<leader>re", function()
			telescope.extensions.rest.select_env()
		end)
		vim.keymap.set("n", "<leader>rr", ":Rest run<CR>")

		-- require("rest-nvim").setup()
		-- vim.g.rest_nvim
	end,
}
