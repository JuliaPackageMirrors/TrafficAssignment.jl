# Frank-Wolfe Methods
# CFW and BFW in Mitradijieva and Lindberg (2013)

# required packages: Graphs, Optim

include("misc.jl")


function ta_frank_wolfe(ta_data; method="BFW", max_iter_no=2000, step="exact", log="off", tol=1e-3)

    setup_time = time()

    if log=="on"
        println("-------------------------------------")
        println("Network Name: $(ta_data.network_name)")
        println("Method: $method")
        println("Line Search Step: $step")
        println("Maximum Interation Number: $max_iter_no")
        println("Tolerance for AEC: $tol")
    end


    # unpacking data from ta_data
    network_name = ta_data.network_name

    number_of_zones = ta_data.number_of_zones
    number_of_nodes = ta_data.number_of_nodes
    first_thru_node = ta_data.first_thru_node
    number_of_links = ta_data.number_of_links

    start_node = ta_data.start_node
    end_node = ta_data.end_node
    capacity = ta_data.capacity
    link_length = ta_data.link_length

    free_flow_time = ta_data.free_flow_time
    B = ta_data.B
    power = ta_data.power
    speed_limit = ta_data.speed_limit
    toll = ta_data.toll
    link_type = ta_data.link_type
    number_of_zones = ta_data.number_of_zones
    total_od_flow = ta_data.total_od_flow
    travel_demand = ta_data.travel_demand
    od_pairs = ta_data.od_pairs

    toll_factor = ta_data.toll_factor
    distance_factor = ta_data.distance_factor

    best_objective = ta_data.best_objective




    # preparing a graph
    graph = create_graph(start_node, end_node)
    link_dic = sparse(start_node, end_node, 1:number_of_links)

    # initializing weight matrix, will be reused.
    weights = fill(Inf, (number_of_nodes, number_of_nodes))

    setup_time = time() - setup_time

    if log=="on"
        println("Setup time = $setup_time seconds")
    end






    function BPR(x)
        # travel_time = free_flow_time .* ( 1.0 + B .* (x./capacity).^power )
        # generalized_cost = travel_time + toll_factor * toll + distance_factor * link_length
        # return generalized_cost
        bpr = similar(x)
        for i=1:length(bpr)
            bpr[i] = free_flow_time[i] * ( 1.0 + B[i] * (x[i]/capacity[i])^power[i] ) + toll_factor * toll[i] + distance_factor * link_length[i]
        end
        return bpr

        # return free_flow_time .* ( 1.0 + B .* (x./capacity).^power ) + toll_factor * toll + distance_factor * link_length
    end

    function objective(x)
        sum = 0

        for i=1:length(x)
            sum += free_flow_time[i] * ( x[i] + B[i]* ( x[i]^(power[i]+1)) / (capacity[i]^power[i]) / (power[i]+1))
        end

        return sum
        # return sum( free_flow_time .* ( x + B.* ( x.^(power+1)) ./ (capacity.^power) ./ (power+1)) )
    end

    function gradient(x)
        return BPR(x)
    end

    function hessian(x)
        no_arc = Base.length(start_node)

        h = zeros(no_arc,no_arc)
        h_diag = hessian_diag(x)

        for i=1:no_arc
            h[i,i] = h_diag[i]
        end

        return h

        #Link travel time = free flow time * ( 1 + B * (flow/capacity)^Power ).
    end

    function hessian_diag(x)
        h_diag = Array(Float64, size(x))
        for i=1:length(x)
            if power[i] >= 1.0
                h_diag[i] = free_flow_time[i] * B[i] * power[i] * (x[i]^(power[i]-1)) / (capacity[i]^power[i])
            else
                h_diag[i] = 0 # Some cases, power is zero.
            end
        end
        # h_diag = free_flow_time .* B .* power .* (x.^(power-1)) ./ (capacity.^power)

        return h_diag
        #Link travel time = free flow time * ( 1 + B * (flow/capacity)^Power ).
    end

    spp_total = 0
    vvv_total = 0

    function all_or_nothing_single(travel_time)
        state = []
        path = []
        x = zeros(size(start_node))

        for r=1:size(travel_demand)[1]
            # for each origin node r, find shortest paths to all destination nodes
            spp = time()
            state = dijkstra_shortest_paths(graph, travel_time, r)
            spp_total = spp_total + time() - spp

            vvv = time()
            for s=1:size(travel_demand)[2]
                # for each destination node s, find the shortest-path vector
                # and load travel demand
                x = x + travel_demand[r,s] * get_vector(state, r, s, link_dic)
            end
            vvv_total = vvv_total + time() - vvv
            # println("vvv=$vvv")
        end

        return x
    end


    # # parallel computing version
    function all_or_nothing_parallel(travel_time)
        state = []
        path = []
        v = []
        vv = zeros(size(start_node))
        x = zeros(size(start_node))

        x = x + @parallel (+) for r=1:size(travel_demand)[1]
            # for each origin node r, find shortest paths to all destination nodes
            # if there is any travel demand starting from node r.
            vv = zeros(size(start_node))

            if sum(travel_demand, 2)[r] > 0.0
                state = dijkstra_shortest_paths(graph, travel_time, r)

                for s=1:size(travel_demand)[2]
                    # for each destination node s, find the shortest-path vector
                    # v = get_vector(state, r, s, start_node, end_node)

                    if travel_demand[r,s] > 0.0
                        v = get_vector(state, r, s, link_dic)

                        # load travel demand
                        vv = vv + v * travel_demand[r,s]
                    end
                end

            end

            vv
        end

        return x
    end


    function all_or_nothing(travel_time)
        if nprocs() > 1 # if multiple CPU processes are available
            all_or_nothing_parallel(travel_time)
        else
            all_or_nothing_single(travel_time)
            # when nprocs()==1, using @parallel just adds unnecessary setup time. I guess.
        end
    end



    function all_or_nothing!(_weights, travel_time)
        # This method uses Floyd-Warshall
        x = zeros(size(start_node))

        spp = time()

        # Updating weights. Inf will remain Inf.
        for i=1:number_of_links
            _weights[start_node[i], end_node[i]] = travel_time[i]
        end

        dists = copy(_weights)

        nexts = fill(-1, (number_of_nodes, number_of_nodes))
        floyd_warshall!(dists, nexts)
        spp_total = spp_total + time() - spp

        vvv = time()
        for r=1:size(travel_demand)[1]
            for s=1:size(travel_demand)[2]
                if travel_demand[r,s] > 0.0
                    x = x + travel_demand[r,s] * get_vector(nexts, r, s, link_dic)
                end
            end
        end
        vvv_total = vvv_total + time() - vvv

        return x
    end






    iteration_time = time()


    # Finding a starting feasible solution
    travel_time = BPR(zeros(number_of_links))
    x0 = all_or_nothing(travel_time)
    # x0 = all_or_nothing!(weights, travel_time)

    # Initializing variables
    xk = x0
    tauk = 0
    yk_FW = x0
    sk_CFW = yk_FW
    Hk_diag = []

    dk_FW = []
    dk_bar = []
    dk_CFW = []
    dk = []

    alphak = 0
    Nk = 0
    Dk = 0

    tauk = 0
    is_first_iteration = false
    is_second_iteration = false

    sk_BFW = yk_FW
    sk_BFW_old = yk_FW

    dk_bbar = []
    muk = []
    nuk = []
    beta0 = 0
    beta1 = 0
    beat2 = 0


    function fk(tau)
        value = objective(xk+tau*dk)
        return value
    end

    function lower_bound_k(x, xk)
        value = objective(xk) + dot( BPR(xk), ( x - xk) )
    end


    for k=1:max_iter_no
        # Finding yk
        travel_time = BPR(xk)
        yk_FW = all_or_nothing(travel_time)
        # yk_FW = all_or_nothing!(weights, travel_time)

        # Basic Frank-Wolfe Direction
        dk_FW = yk_FW - xk
        Hk_diag = hessian_diag(xk) # Hk_diag is a diagonal vector of matrix Hk

        # Finding a feasible direction
        if method == "FW" # Original Frank-Wolfe
            dk = dk_FW
        elseif method == "CFW" # Conjugate Direction F-W
            if k==1 || tauk > 0.999999 # If tauk=1, then start the process all over again.
                sk_CFW = yk_FW
                dk_CFW = sk_CFW - xk
            else
                dk_bar = sk_CFW - xk # sk_CFW from the previous iteration k-1

                Nk = dot( dk_bar, Hk_diag .* dk_FW )
                Dk = dot( dk_bar, Hk_diag .* (dk_FW - dk_bar) )

                delta = 0.0001 # What value should I use?
                alphak = 0
                if Dk !=0 && 0 <= Nk/Dk <= 1-delta
                    alphak = Nk/Dk
                elseif Dk !=0 && Nk/Dk > 1-delta
                    alphak = 1-delta
                else
                    alphak = 0
                end

                # Generating new sk_CFW and dk_CFW
                sk_CFW = alphak * sk_CFW + (1-alphak) * yk_FW
                dk_CFW = sk_CFW - xk
            end

            # Feasible Direction to Use for CFW
            dk = dk_CFW
        elseif method == "BFW" # Bi-Conjugate Direction F-W

            if tauk > 0.999999
                is_first_iteration = true
                is_second_iteration = true
            end

            if k==1 || is_first_iteration       # First Iteration is like FW
                # println("here")
                sk_BFW_old = yk_FW
                dk_BFW = dk_FW
                is_first_iteration = false
            elseif k==2 || is_second_iteration  # Second Iteration is like CFW
                # println("there")
                dk_bar = sk_BFW_old - xk # sk_BFW_old from the previous iteration 1

                Nk = dot( dk_bar, Hk_diag .* dk_FW )
                Dk = dot( dk_bar, Hk_diag .* (dk_FW - dk_bar) )

                delta = 0.0001 # What value should I use?
                alphak = 0
                if Dk !=0 && 0 <= Nk/Dk <= 1-delta
                    alphak = Nk/Dk
                elseif Dk !=0 && Nk/Dk > 1-delta
                    alphak = 1-delta
                else
                    alphak = 0
                end

                # Generating new sk_BFW and dk_BFW
                sk_BFW = alphak * sk_BFW_old + (1-alphak) * yk_FW
                dk_BFW = sk_BFW - xk

                is_second_iteration = false
            else
                # println("over there $tauk")
                # sk_BFW, tauk is from iteration k-1
                # sk_BFW_old is from iteration k-2

                dk_bar  = sk_BFW - xk
                dk_bbar = tauk * sk_BFW - xk + (1-tauk) * sk_BFW_old

                muk = - dot( dk_bbar, Hk_diag .* dk_FW ) / dot( dk_bbar, Hk_diag .* (sk_BFW_old - sk_BFW) )
                nuk = - dot( dk_bar, Hk_diag .* dk_FW ) / dot( dk_bar, Hk_diag .* dk_bar) + muk*tauk/(1-tauk)

                muk = max(0, muk)
                nuk = max(0, nuk)

                # println(sk_BFW_old-sk_BFW)

                beta0 = 1 / ( 1 + muk + nuk )
                beta1 = nuk * beta0
                beta2 = muk * beta0

                # dk_BFW = beta0 * dk_FW + beta1 * (sk_BFW - xk) + beta2 * (sk_BFW_old - xk)

                sk_BFW_new = beta0 * yk_FW + beta1 * sk_BFW + beta2 * sk_BFW_old
                dk_BFW = sk_BFW_new - xk

                sk_BFW_old = sk_BFW
                sk_BFW = sk_BFW_new

            end

            # Feasible Direction to Use for BFW
            dk = dk_BFW
        else
            error("The type of Frank-Wolfe method is specified incorrectly. Use FW, CFW, or BFW.")
        end
        # dk is now identified.


        if step=="exact"
            # Line Search from xk in the direction dk
            optk = optimize(fk, 0.0, 1.0, method = :golden_section)
            tauk = optk.minimum
        elseif step=="newton"
            # Newton step
            tauk = - dot( gradient(xk), dk ) / dot( dk, Hk_diag.*dk )
            tauk = max(0, min(1, tauk))
            @assert 0<= tauk <= 1
        end


        # Average Excess Cost
        average_excess_cost = ( dot(xk, travel_time) - dot(yk_FW, travel_time) ) / sum(travel_demand)
        if log=="on"
            println("k=$k,\ttauk=$tauk,\tobjective=$(objective(xk)),\taec=$average_excess_cost")
        end

        # rel_gap = ( objective(xk) - best_objective ) / best_objective

        # Convergence Test
        if average_excess_cost < tol
        # if rel_gap < tol
            break
        end

        # Update x
        new_x = xk + tauk*dk
        xk = new_x

        @assert minimum(xk) >= 0

    end



    iteration_time = time() - iteration_time

    if log=="on"
        println("Iteration time = $iteration_time seconds")
    end


    println("spp_total=$spp_total, vvv_total=$vvv_total")
    return xk, travel_time, objective(xk)

end





#
