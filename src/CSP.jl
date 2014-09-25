module CSP

import Base: Condition, open, close, send, recv, map,
             reduce, filter, merge, select

export Channel, Transport, ChannelClosedError, open, close, send, recv

type ChannelClosedError <: Exception
end

type Channel{T}
    isopen::Bool
    ready_recv::Condition
    ready_send::Condition
    bufsize::Int
    buffer::Vector{T}
end

Channel(T::Type=Any, bufsize=0) =
    Channel{T}(true, Condition(), Condition(), bufsize, T[])

open(c::Channel) = c.isopen = true
close(c::Channel) = c.isopen = false
isopen(c::Channel) = c.isopen

function send(c::Channel, val)
    # notify a blocked recv
    if !isopen(c)
        throw(ChannelClosedError())
    end
    if c.bufsize == 0
        # Beware: Races possible when actually multithreaded!
        push!(c.buffer, val)
        wait(c.ready_recv)
    elseif length(c.buffer) < c.bufsize
        push!(c.buffer, val)
    else
        if !isempty(c.ready_recv.waitq)
            push!(c.buffer, val)
        else
            # block until someone wants to read
            push!(c.buffer, val)
            wait(c.ready_send)
        end
    end
    notify(c.ready_recv, all=false)
end

function recv(c::Channel)
    # Read out if there is something in the buffer

    if length(c.buffer) > 0
        try
            v = shift!(c.buffer)
            # tell others that you have freed a buffer slot
            notify(c.ready_send, all=false)
            return v
        catch
            # Continue and wait if cannot shift!
        end
    end

    # Or block till there is something
    if length(c.buffer) == 0 && !isopen(c)
        warn("waiting to receive from a closed channel!")
    end

    if !isempty(c.ready_send.waitq)
        v = shift!(c.buffer)
        # tell others that you have freed a buffer slot
        notify(c.ready_send, all=false)
        return v
    else
        wait(c.ready_recv)
        return shift!(c.buffer)
    end
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
