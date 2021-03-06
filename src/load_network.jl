# Sioux Falls network data
# http://www.bgu.ac.il/~bargera/tntp/

#Link travel time = free flow time * ( 1 + B * (flow/capacity)^Power ).
#Link generalized cost = Link travel time + toll_factor * toll + distance_factor * distance

# Traffic Assignment Data structure
type TA_Data
    network_name::ASCIIString

    number_of_zones::Int64
    number_of_nodes::Int64
    first_thru_node::Int64
    number_of_links::Int64

    start_node::Array{Int64,1}
    end_node::Array{Int64,1}
    capacity::Array{Float64,1}
    link_length::Array{Float64,1}
    free_flow_time::Array{Float64,1}
    B::Array{Float64,1}
    power::Array{Float64,1}
    speed_limit::Array{Float64,1}
    toll::Array{Float64,1}
    link_type::Array{Int64,1}

    total_od_flow::Float64

    travel_demand::Array{Float64,2}
    od_pairs::Array{Tuple{Int64,Int64},1}

    toll_factor::Float64
    distance_factor::Float64

    best_objective::Float64
end

function load_ta_network(network_name="Sioux Falls")

    toll_factor = 0.0
    distance_factor = 0.0

    if network_name == "Sioux Falls"
        network_data_file = "SiouxFalls_net.txt"
        trip_table_file = "SiouxFalls_trips.txt"
        best_objective = 4.231335287107440e6 #42.31335287107440
    elseif network_name == "Barcelona"
        network_data_file = "Barcelona_net.txt"
        trip_table_file = "Barcelona_trips.txt"
        best_objective = 1.0
    elseif network_name =="Chicago Sketch"
        network_data_file = "ChicagoSketch_net.txt"
        trip_table_file = "ChicagoSketch_trips.txt"
        best_objective = 1.0
        toll_factor = 0.02
        distance_factor = 0.04
    elseif network_name == "Anaheim"
        network_data_file = "Anaheim_net.txt"
        trip_table_file = "Anaheim_trips.txt"
        best_objective = 1.0
    elseif network_name == "Winnipeg"
        network_data_file = "Winnipeg_net.txt"
        trip_table_file = "Winnipeg_trips.txt"
        best_objective = 1.0
    end

    network_data_file = joinpath(dirname(@__FILE__), "..", "data", network_data_file)
    trip_table_file = joinpath(dirname(@__FILE__), "..", "data", trip_table_file)




    ##################################################
    # Network Data
    ##################################################


    number_of_zones = 0
    number_of_links = 0
    number_of_nodes = 0
    first_thru_node = 0

    n = open(network_data_file, "r")

    while (line=readline(n)) != ""
        if contains(line, "<NUMBER OF ZONES>")
            number_of_zones = parse(Int, line[ search(line, '>')+1 : end-1 ] )
        elseif contains(line, "<NUMBER OF NODES>")
            number_of_nodes = parse(Int, line[ search(line, '>')+1 : end-1 ] )
        elseif contains(line, "<FIRST THRU NODE>")
            first_thru_node = parse(Int, line[ search(line, '>')+1 : end-1 ] )
        elseif contains(line, "<NUMBER OF LINKS>")
            number_of_links = parse(Int, line[ search(line, '>')+1 : end-1 ] )
        elseif contains(line, "<END OF METADATA>")
            break
        end
    end

    @assert number_of_links > 0

    start_node = Array(Int, number_of_links)
    end_node = Array(Int, number_of_links)
    capacity = zeros(number_of_links)
    link_length = zeros(number_of_links)
    free_flow_time = zeros(number_of_links)
    B = zeros(number_of_links)
    power = zeros(number_of_links)
    speed_limit = zeros(number_of_links)
    toll = zeros(number_of_links)
    link_type = Array(Int, number_of_links)

    idx = 1
    while (line=readline(n)) != ""
        if contains(line, "~")
            continue
        end

        if contains(line, ";")
            line = strip(line, '\n')
            line = strip(line, ';')

            numbers = split(line)

            start_node[idx] = parse(Int, numbers[1])
            end_node[idx] = parse(Int, numbers[2])
            capacity[idx] = parse(Float64, numbers[3])
            link_length[idx] = parse(Float64, numbers[4])
            free_flow_time[idx] = parse(Float64, numbers[5])
            B[idx] = parse(Float64, numbers[6])
            power[idx] = parse(Float64, numbers[7])
            speed_limit[idx] = parse(Float64, numbers[8])
            toll[idx] = parse(Float64, numbers[9])
            link_type[idx] = parse(Int, numbers[10])

            idx = idx + 1
        end
    end

    ##################################################
    # Trip Table
    ##################################################

    number_of_zones_trip = 0
    total_od_flow = 0

    f = open(trip_table_file, "r")

    while (line=readline(f)) != ""
        if contains(line, "<NUMBER OF ZONES>")
            number_of_zones_trip = parse(Int, line[ search(line, '>')+1 : end-1 ] )
        elseif contains(line, "<TOTAL OD FLOW>")
            total_od_flow = parse(Float64, line[ search(line, '>')+1 : end-1 ] )
        elseif contains(line, "<END OF METADATA>")
            break
        end
    end

    @assert number_of_zones_trip == number_of_zones # Check if number_of_zone is same in both txt files
    @assert total_od_flow > 0

    travel_demand = zeros(number_of_zones, number_of_zones)
    od_pairs = Array{Tuple{Int64, Int64}}(0)
    while (line=readline(f)) != ""
        if contains(line, "Origin")
            origin = parse(Int, split(line)[2] )
        elseif contains(line, ";")
            pairs = split(line, ";")
            for i=1:size(pairs)[1]
                if contains(pairs[i], ":")
                    pair = split(pairs[i], ":")
                    destination = parse(Int, strip(pair[1]) )
                    od_flow = parse(Float64, strip(pair[2]) )
                    travel_demand[origin, destination] = od_flow
                    push!(od_pairs, (origin, destination))
                    # println("origin=$origin, destination=$destination, flow=$od_flow")
                end
            end
        end
    end

    # Preparing data to return
    ta_data = TA_Data(
        network_name,
        number_of_zones,
        number_of_nodes,
        first_thru_node,
        number_of_links,
        start_node,
        end_node,
        capacity,
        link_length,
        free_flow_time,
        B,
        power,
        speed_limit,
        toll,
        link_type,
        total_od_flow,
        travel_demand,
        od_pairs,
        toll_factor,
        distance_factor,
        best_objective)

    return ta_data

end # end of load_network function
