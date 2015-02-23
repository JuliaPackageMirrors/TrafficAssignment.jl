
using Graphs, Base.Test

# write your own tests here
include("load_network.jl")

ta_data = load_ta_network("Sioux Falls")
# ta_data = load_ta_network("Anaheim")
# ta_data = load_ta_network("Barcelona")
# ta_data = load_ta_network("Chicago Sketch")
# ta_data = load_ta_network("Winnipeg")


include("misc.jl")

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
    dists = weights


    function BPR(x)
        # travel_time = free_flow_time .* ( 1.0 + B .* (x./capacity).^power )
        # generalized_cost = travel_time + toll_factor * toll + distance_factor * link_length
        # return generalized_cost
        return free_flow_time .* ( 1.0 + B .* (x./capacity).^power ) + toll_factor * toll + distance_factor * link_length
    end

    function all_or_nothing_single(travel_time)
        state = []
        path = []
        x = zeros(size(start_node))
        vector = Dict()

        for r=1:size(travel_demand)[1]
            state = dijkstra_shortest_paths(graph, travel_time, r)
            for s=1:size(travel_demand)[2]
                x = x + travel_demand[r,s] * get_vector(state, r, s, link_dic)
                vector[(r,s)] = get_vector(state, r, s, link_dic)
            end
        end

        return x, vector
    end
    function all_or_nothing!(_weights, travel_time)
        x = zeros(size(start_node))
        # Updating weights. Inf will remain Inf.
        for i=1:number_of_links
            _weights[start_node[i], end_node[i]] = travel_time[i]
        end
        dists = copy(_weights)
        vector = Dict()
        # println(_weights)

        nexts = fill(-1, (number_of_nodes, number_of_nodes))
        floyd_warshall!(dists, nexts)

        # println(_weights)
        # println(dists)
        # println(nexts)

        for r=1:size(travel_demand)[1]
            for s=1:size(travel_demand)[2]
                # if travel_demand[r,s] > 0.0
                    x = x + travel_demand[r,s] * get_vector(nexts, r, s, link_dic)
                    vector[(r,s)] = get_vector(nexts, r, s, link_dic)
                # end
            end
        end

        return x, vector
    end


    travel_time = BPR(zeros(number_of_links))
    x0, v0 = all_or_nothing_single(travel_time)
    x1, v1 = all_or_nothing!(weights, travel_time)

    # @test x0==x1
    println( [x0 x1] )
    println(sum(x0))
    println(sum(x1))


    for rs in keys(v0)
        println(rs)
        if v0[rs] != v1[rs]
            # println(start_node)
            # println(end_node)
            # println(v0[rs])
            # println(v1[rs])

            println([start_node end_node v0[rs] v1[rs]])
            break
        end
    end
