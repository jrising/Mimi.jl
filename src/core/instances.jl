#
# Functions pertaining to instantiated models and their components
#

"""
    modeldef(mi)

Return the `ModelDef` contained by ModelInstance `mi`.
"""
modeldef(mi::ModelInstance) = mi.md

"""
    @method add_comp!(obj::CompositeComponentInstance, ci::AbstractComponentInstance)

Add the (leaf or composite) component `ci` to a composite's list of components, and add 
the `first` and `last` of `mi` to the ends of the composite's `firsts` and `lasts` lists.
"""
@method function add_comp!(obj::CompositeComponentInstance, ci::AbstractComponentInstance)
    obj.comps_dict[nameof(ci)] = ci

    # push!(obj.firsts, first_period(ci))         # TBD: perhaps this should be set when time is set?
    # push!(obj.lasts,  last_period(ci))
    nothing
end

#
# Setting/getting parameter and variable values
#

#
# TBD: once working, explore whether these can be methods of ComponentInstanceData{NT}
#
# Get the object stored for the given variable, not the value of the variable.
# This is used in the model building process to connect internal parameters.
@inline function get_property_obj(obj::ComponentInstanceParameters{NT}, name::Symbol) where {NT}
    return getproperty(nt(obj), name)
end

@inline function get_property_obj(obj::ComponentInstanceVariables{NT}, name::Symbol) where {NT}
    return getproperty(nt(obj), name)
end

@inline function _get_prop(nt::NT, name::Symbol) where {NT <: NamedTuple}
    obj = getproperty(nt, name)
    return fieldtype(NT, name) <: ScalarModelParameter ? obj.value : obj
end

@inline function Base.getproperty(obj::ComponentInstanceParameters{NT}, name::Symbol) where {NT}
    return _get_prop(nt(obj), name)
end

@inline function Base.getproperty(obj::ComponentInstanceVariables{NT}, name::Symbol) where {NT}
    return _get_prop(nt(obj), name)
end

@inline function Base.setproperty!(obj::ComponentInstanceParameters{NT}, name::Symbol, value::VTYPE) where {NT, VTYPE}
    prop_obj = get_property_obj(obj, name)
    T = fieldtype(NT, name)

    if T <: ScalarModelParameter
        return setproperty!(prop_obj, :value, value)
    else
        error("You cannot override indexed parameter $name::$T.")
    end
end

@inline function Base.setproperty!(obj::ComponentInstanceVariables{NT}, name::Symbol, value::VTYPE) where {NT, VTYPE}
    prop_obj = get_property_obj(obj, name)
    T = fieldtype(NT, name)

    if T <: ScalarModelParameter
        return setproperty!(prop_obj, :value, value)
    else
        error("You cannot override indexed variable $name::$T.")
    end
end

"""
    get_param_value(ci::ComponentInstance, name::Symbol)

Return the value of parameter `name` in (leaf or composite) component `ci`.
"""
@method function get_param_value(ci::ComponentInstance, name::Symbol)
    try 
        return getproperty(ci.parameters, name)
    catch err
        if isa(err, KeyError)
            error("Component $(ci.comp_id) has no parameter named $name")
        else
            rethrow(err)
        end
    end
end

"""
    get_var_value(ci::ComponentInstance, name::Symbol)

Return the value of variable `name` in component `ci`.
"""
@method function get_var_value(ci::ComponentInstance, name::Symbol)
    try
        # println("Getting $name from $(ci.variables)")
        return getproperty(ci.variables, name)
    catch err
        if isa(err, KeyError)
            error("Component $(ci.comp_id) has no variable named $name")
        else
            rethrow(err)
        end
    end
end

@method set_param_value(ci::ComponentInstance, name::Symbol, value) = setproperty!(ci.parameters, name, value)

@method set_var_value(ci::ComponentInstance, name::Symbol, value) = setproperty!(ci.variables, name, value)

"""
    variables(obj::AbstractCompositeComponentInstance, comp_name::Symbol)

Return the `ComponentInstanceVariables` for `comp_name` in CompositeComponentInstance `obj`.
"""
@method variables(obj::CompositeComponentInstance, comp_name::Symbol) = variables(compinstance(obj, comp_name))

function variables(m::Model)
    if ! is_built(m)
        error("Must build model to access variable instances. Use variables(modeldef(m)) to get variable definitions.")
    end
    return variables(modelinstance(m))
end

"""
    parameters(obj::AbstractCompositeComponentInstance, comp_name::Symbol)

Return the `ComponentInstanceParameters` for `comp_name` in CompositeComponentInstance `obj`.
"""
@method parameters(obj::CompositeComponentInstance, comp_name::Symbol) = parameters(compinstance(obj, comp_name))

function Base.getindex(mi::ModelInstance, comp_name::Symbol, datum_name::Symbol)
    if ! has_comp(mi, comp_name)
        error("Component :$comp_name does not exist in current model")
    end
    
    comp_inst = compinstance(mi, comp_name)
    vars = comp_inst.variables
    pars = comp_inst.parameters

    if datum_name in names(vars)
        which = vars
    elseif datum_name in names(pars)
        which = pars
    else
        error("$datum_name is not a parameter or a variable in component $comp_name.")
    end

    value = getproperty(which, datum_name)

    return value isa TimestepArray ? value.data : value
end

"""
    dim_count(mi::ModelInstance, dim_name::Symbol)

Return the size of index `dim_name`` in model instance `mi`.
"""
@delegate dim_count(mi::ModelInstance, dim_name::Symbol) => md

@method function reset_variables(ci::ComponentInstance)
    # println("reset_variables($(ci.comp_id))")
    vars = ci.variables

    for (name, T) in zip(names(vars), types(vars))
        value = getproperty(vars, name)

        if (T <: AbstractArray || T <: TimestepArray) && eltype(value) <: AbstractFloat
            fill!(value, NaN)

        elseif T <: AbstractFloat || (T <: ScalarModelParameter && T.parameters[1] <: AbstractFloat)            
            setproperty!(vars, name, NaN)

        elseif (T <: ScalarModelParameter)    # integer or bool
            setproperty!(vars, name, 0)
        end
    end
end

@method function reset_variables(obj::CompositeComponentInstance)
    for ci in components(obj)
        reset_variables(ci)
    end
    return nothing
end

@method function init(ci::ComponentInstance)
    reset_variables(ci)

    if ci.init != nothing
        ci.init(ci.parameters, ci.variables, dims)
    end
    return nothing
end

@method function init(obj::CompositeComponentInstance, dims::DimValueDict)
    for ci in components(obj)
        init(ci, dims)
    end
    return nothing
end

# @method function run_timestep(ci::ComponentInstance, clock::Clock)
#     if ci.run_timestep !== nothing
#         ci.run_timestep(parameters(ci), variables(ci), dim_value_dict(ci), clock.ts)
#     end

#     # TBD: move this outside this func if components share a clock
#     advance(clock)

#     return nothing
# end

# @method function run_timestep(obj::CompositeComponentInstance, clock::Clock)
#     for ci in components(obj)
#         run_timestep(ci, clock)
#     end
#     return nothing
# end

@method _runnable(ci::ComponentInstance, clock::Clock) = (ci.first <= gettime(clock) <= ci.last)

#
# New versions
#
@method function run_timestep(ci::ComponentInstance, clock::Clock, dims::DimValueDict)
    if ci.run_timestep !== nothing && _runnable(ci, clock)
        ci.run_timestep(ci.parameters, ci.variables, dims, clock.ts)
    end

    return nothing
end

@method function run_timestep(cci::CompositeComponentInstance, clock::Clock, dims::DimValueDict)
    if _runnable(cci, clock)
        for ci in components(cci)
            run_timestep(ci, clock, dims)
        end
    end
    return nothing
end

#
# TBD: might be obsolete
#
"""
    function _make_clocks(ci::AbstractComponentInstance, time_keys::Vector{Int})

Store a vector of of Clocks into a composite instance's `clocks` member,
and repeat recursively through any subcomps. For non-composites, do nothing.
"""
# _make_clocks(ci::ComponentInstance, time_keys::Vector{Int}) = nothing

# @method function _make_clocks(ci::CompositeComponentInstance, time_keys::Vector{Int})
#     clocks = ci.clocks  # preallocated in constructor

#     if isuniform(time_keys)
#         stepsize = step_size(time_keys)
#         for (i, (first, last)) in enumerate(zip(ci.firsts, ci.lasts))
#             clocks[i] = Clock{FixedTimestep}(first, stepsize, last)
#         end
#     else
#         for (i, (first, last)) in enumerate(zip(ci.firsts, ci.lasts))
#             first_index = findfirst(isequal(first), time_keys)
#             last_index  = findfirst(isequal(last), time_keys)
#             times = Tuple(time_keys[first_index:last_index])
#             clocks[i] = Clock{VariableTimestep}(times)
#         end
#     end

#     for subcomp in components(ci)
#         _make_clocks(subcomp, time_keys)
#     end
# end

# TBD: Write a reset(clock::Clock) method?

function Base.run(mi::ModelInstance, ntimesteps::Int=typemax(Int), 
                  dimkeys::Union{Nothing, Dict{Symbol, Vector{T} where T <: DimensionKeyTypes}}=nothing)

    if (ncomps = length(components(mi))) == 0
        error("Cannot run the model: no components have been created.")
    end

    time_keys::Vector{Int} = dimkeys === nothing ? dim_keys(mi.md, :time) : dimkeys[:time]

    # truncate time_keys if caller so desires
    if ntimesteps < length(time_keys)
        time_keys = time_keys[1:ntimesteps]
    end

    # _make_clocks(mi, time_keys)     # pre-generate all required sub-component clocks

    # TBD: Pass this, but substitute t from above?
    dim_val_dict = DimValueDict(dim_dict(mi.md))

    # recursively initializes all components
    init(mi)    
    
    clock = Clock(time_keys)
    while ! finished(clock)
        run_timestep(mi, clock, dim_val_dict)
        advance(clock)
    end

    nothing
end
