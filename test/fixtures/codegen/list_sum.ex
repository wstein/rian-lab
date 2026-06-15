def sum([]) do
  0
end

def sum([h | t]) do
  h + sum(t)
end
