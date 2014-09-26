using CSP
using Base.Test

c1 = Channel(Int)
c2 = Channel(Int)

t1 = @async begin
    sleep(0.5)
    for i=6:10
        @test recv(c1) == i
    end
    for i=1:5
        send(c1, i)
    end

    # time million writes
    println("sending a million integers")
    tic()
    for i = 1:1000000
        send(c2, i)
    end
    toc()
end

t2 = @async begin
    for i=6:10
        send(c1, i)
    end
    for i=1:5
        @test recv(c1) == i
    end

    for i = 1:1000000
        recv(c2)
    end
end

wait(t1)
wait(t2)
