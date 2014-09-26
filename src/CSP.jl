module CSP

import Base: Condition, open, close, send, recv, map,
             reduce, filter, merge, select

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

function send(c::Channel, val)
    if !isopen(c)
        throw(ChannelClosedError())
    end

    if length(c.buffer) < c.bufsize
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

function select(chans)
    out = Channel(Selected)
    for c in chans
	@async send(out, recv(c))
    end
    out
end

function map(f::Base.Callable, inp::Channel)
    v = recv(inp)
    out = Channel(typeof(v))
    send(out, v)
    @async while true
        send(out, f(recv(inp)))
    end
    out
end

function reduce{T}(f::Base.Callable, v0::T, inp::Channel)
    out = Channel(T)
    store = v0
    @async while true
        send(out, f(store, recv(inp)))
    end
    out
end

function filter{T}(pred::Function, inp::Channel{T})
    out = Channel(T)
    @async while true
        v = recv(inp)
        if pred(v)
            send(out, v)
	end
    end
    out
end

merge(chans...) =
   map(x -> x[2], select(chans))

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
