# CSP.jl

An implementation of [Communicating Sequential Processes](http://enwp.org/Communicating_Sequential_Processes) in Julia. CSP lets you express concurrency in terms of sequential-looking processes (currently, tasks) which synchronize by messaging each other.

# Usage

```julia
# Install
Pkg.clone("git://github.com/shashi/CSP.jl")

# Include
using CSP

# Create a channel
c = Channel(Int) # A channel that can hold integers
                 # Takes optional second arg: number of messages to buffer

@async  ...
        send(c, <int>) # block till someone wants to receive
        ...

@async  ...
        recv(c) # blocks till someone sends something
        ...

select(channels) # returns a channel of (updated_channel, value) pairs
merge(channels)  # A merged channel stream

# These three functions return other channels
map(f, ::Channel)
reduce(f, v0, ::Channel)
filter(f, ::Channel)
```
