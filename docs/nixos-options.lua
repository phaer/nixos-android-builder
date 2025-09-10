function Para(el)
  local text = pandoc.utils.stringify(el)
  if text == "{{nixos-options}}" then
    local cmd = "nix build .#optionDocs --print-out-paths --no-link"
    local pipe = io.popen(cmd)
    if not pipe then
        io.stderr:write("cannot execute " .. cmd .. "\n")
        return el
    end
    local fname = pipe:read("*l")  -- first line of output
    pipe:close()

    if not fname then
      io.stderr:write("command produced no output: " .. cmd .. "\n")
      return el
    end

    local f = io.open(fname, "r")
    if not f then
      io.stderr:write("cannot open file: " .. fname .. "\n")
      return el
    end
    local md = f:read("*a")
    f:close()

    -- parse file contents as markdown
    local blocks = pandoc.read(md, "markdown").blocks
    return blocks
  end
end
