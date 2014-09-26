module CSP

import Base: Condition, open, close, send, recv, map,
             eltype, join_eltype, reduce, filter, merge, select

export Channel, Transport, ChannelClosedError, open, close, send, recv

type ChannelClosedError <: Exception
end

type Channel{T}
    isopen::Bool
    recv_blocker::Condition
    send_blocker::Condition
    bufsize::Int
    buffer::Vector{T}
end

Channel(T::Type=Any, bufsize=0) =
    Channel{T}(true, Condition(), Condition(), bufsize, T[])

open(c::Channel) = c.isopen = true
close(c::Channel) = c.isopen = false
isopen(c::Channel) = c.isopen
bufsize(c::Channel) = c.bufsize
eltype{T}(c::Channel{T}) = T

function send(c::Channel, val)
    if !isopen(c)
        throw(ChannelClosedError())
    end

    if length(c.buffer) < bufsize(c)
        push!(c.buffer, val)
        notify(c.recv_blocker, all=false)
    else
        if !isempty(c.recv_blocker.waitq)
            # if procs are already waiting to recv
            push!(c.buffer, val)
	    notify(c.recv_blocker, all=false)
        else
            # otherwise, block until someone wants to recv
            push!(c.buffer, val)
            wait(c.send_blocker)
	    notify(c.recv_blocker, all=false)
        end
    end
end

function recv(c::Channel)
    # Read out if there is something in the buffer
    if length(c.buffer) > 0
        try
            v = shift!(c.buffer)
            # tell others that you have freed a buffer slot
            notify(c.send_blocker, all=false)
            return v
        catch
            # Continue and wait if cannot shift!
        end
    end
    # Or block till there is something
    if !isopen(c)
        warn("waiting to receive from a closed channel!")
    end

    wait(c.recv_blocker)
    v = shift!(c.buffer)
    notify(c.send_blocker, all=false)
    return v
end

typealias Selected{T} (Channel{T}, T)

function select(chans; bufsize=0)
    out = Channel(Selected, bufsize)
    for c in chans
	@async send(out, recv(c))
    end
    out
end

function map(f::Base.Callable, inp::Channel; typ=eltype(inp), bufsize=bufsize(inp))
    send(out, v)
    @async while true
        out = Channel(typ, bufsize=bufsize)
        send(out, f(recv(inp)))
    end
    out
end

function reduce{T}(f::Base.Callable, v0::T, inp::Channel; bufsize=bufsize(inp))
    out = Channel(T, bufsize)
    store = v0
    @async while true
        send(out, f(store, recv(inp)))
    end
    out
end

function filter{T}(pred::Function, inp::Channel{T}; bufsize=bufsize(inp))
    out = Channel(T, bufsize)
    @async while true
        v = recv(inp)
        if pred(v)
            send(out, v)
	end
    end
    out
end

merge(
        chans...;
        typ=reduce(join_eltype, map(eltype, chans)),
        bufsize=max(map(bufsize, chans)...)
    ) =
    map(x -> x[2], select(chans), typ=typ, bufsize=bufsize)

abstract Transport

function pipe(t::Transport, c::Channel=Channel())
    @async while true
        send(c, recv(t)) # Assumes recv blocks
    end
end

function pipe(c1::Channel, c2::Channel)
    @async while true
        send(c1, recv(c2)) # Assumes recv blocks
    end
end

function pipe(c::Channel, t::Transport)
    @async while true
        send(t, recv(c))
    end
end

(>>>)(a::Union(Channel, Transport), b::Union(Channel, Transport)) = pipe(a, b)

end # module
