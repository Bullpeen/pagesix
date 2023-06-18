--- Misc utils
-- @module utils.misc

function misc(app)

    function File_exists(path)
        local file = open(path, "rb") -- r read mode and b binary mode
        if not file then return nil end
    end

    function Misc:read_file(path)
        local file = open(path, "rb") -- r read mode and b binary mode
        if not file then return nil end

        local content = file:read "*a" -- *a or *all reads the whole file
        file:close()

        return content
    end

    function Generate_password()
        local upperCase = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
        local lowerCase = "abcdefghijklmnopqrstuvwxyz"
        local numbers = "0123456789"
        local symbols = "!@#$%&*+-,./<=>?^"

        local characterSet = upperCase .. lowerCase .. numbers .. symbols

        local keyLength = 32
        local output = ""

        for	i = 1, keyLength do
            local rand = math.random(#characterSet)
            output = output .. string.sub(characterSet, rand, rand)
        end
        return output
    end

    function Validate_email(input)
        if input:match(".+@.+%..+") then
            return true
        else
            return false, "%s is not a valid email"
        end
    end

    return app
end

return misc
