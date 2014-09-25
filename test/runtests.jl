using CSP
using Base.Test

c1 = Channel(Int)
c2 = Channel(Int)

t1 = @async begin
    @test recv(c1) == 3
    send(c1, 4)

    sleep(0.5)
    send(c2, 1)
end

t2 = @async begin
    send(c1, 3)
    @test recv(c1) == 4

    # Blocked recv
    tic()
    @test recv(c2) == 1
    dt = toc()
    @test dt >= 0.5

end
sleep(1)

function throw(t::Task)
    if t.exception != nothing
        rethrow(t.exception)
    end
end

map(throw, [t1, t2])
