@type opt :: :none | {:some, term()}
def get(:none, d) do
  d
end

def get({:some, v}, _) do
  v
end
