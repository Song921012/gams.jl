
const LINE_BREAK = 120

mutable struct GAMSTranslateStream
   io::IOStream
   n_line::Int
end

GAMSTranslateStream(io::IOStream) = GAMSTranslateStream(io, 0)

function write(
   io::GAMSTranslateStream,
   str::String
)
   n = length(str)
   if io.n_line + n > LINE_BREAK
      idx = n+1
      while true
         idx = findprev(isequal(' '), str, idx-1)
         if idx == nothing || io.n_line + idx <= LINE_BREAK
            break
         end
      end
      if idx == nothing
         Base.write(io.io, "\n  ")
         io.n_line = Base.write(io.io, str)
      else
         Base.write(io.io, str[1:idx-1])
         Base.write(io.io, "\n ")
         Base.write(io.io, str[idx+1:end])
         io.n_line = n-idx
      end
   else
      Base.write(io.io, str)
      io.n_line += n
   end
end

function writeln(
   io::GAMSTranslateStream,
   str::String
)
   write(io, str)
   Base.write(io.io, "\n")
   io.n_line = 0
end

function dbl2str(
   value::Number
)
   @sprintf("%.16g", value)
end

function variable_name(
   model::Optimizer,
   idx::MOI.VariableIndex
)
   idx = idx.value
   if !isempty(model.variable_info[idx].name)
      name = replace(model.variable_info[idx].name, r"[^a-zA-Z0-9_]" => s"_")
      if length(name) > 0 && name[1] != '_'
         return name
      end
   end

   if model.variable_info[idx].type == VARTYPE_FREE
      return "x$idx"
   elseif model.variable_info[idx].type == VARTYPE_BINARY
      return "b$idx"
   elseif model.variable_info[idx].type == VARTYPE_INTEGER
      return "i$idx"
   elseif model.variable_info[idx].type == VARTYPE_SEMICONT
      return "sc$idx"
   elseif model.variable_info[idx].type == VARTYPE_SEMIINT
      return "si$idx"
   end
end

function equation_name(
   model::Optimizer,
   idx::MOI.ConstraintIndex{F, S}
) where {
   F <: Union{
      MOI.ScalarAffineFunction{Float64},
      MOI.ScalarQuadraticFunction{Float64},
   },
   S,
}
   idx = idx.value
   if !isempty(_constraints(model, F, S)[idx].name)
      name = replace(_constraints(model, F, S)[idx].name, r"[^a-zA-Z0-9_]" => s"_")
      if length(name) > 0 && name[1] != '_'
         return name
      end
   end

   idx += _offset(model, F, S)
   return "eq$idx"
end

function translate_header(
   io::GAMSTranslateStream
)
   writeln(io, "*\n* GAMS Model generated by GAMS.jl\n*\n")
   writeln(io, "\$offlisting")
end

function translate_defsets(
   io::GAMSTranslateStream,
   model::Optimizer
)
   n = length(model.sos1_constraints) + length(model.sos2_constraints)
   if n == 0
      return
   elseif n == 1
      writeln(io, "Set")
   else
      writeln(io, "Sets")
   end
   write(io, "  ")

   first = true
   for (i, con) = enumerate(model.sos1_constraints)
      translate_defsets(io, model, i, con.func, con.set, first=first)
      first = false
   end
   for (i, con) = enumerate(model.sos2_constraints)
      translate_defsets(io, model, i, con.func, con.set, first=first)
      first = false
   end
   writeln(io, "\n");
end

function translate_defsets(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::Int,
   func::MOI.VectorOfVariables,
   set::Union{MOI.SOS1{Float64}, MOI.SOS2{Float64}};
   first::Bool=true
)
   if ! first
      write(io, ", ")
   end

   if typeof(set) == MOI.SOS1{Float64}
      write(io, "sos1_s$idx / ")
   elseif typeof(set) == MOI.SOS2{Float64}
      write(io, "sos2_s$idx / ")
   end

   first_elem = true
   for vi in func.variables
      if ! first_elem
         write(io, ", ")
      end
      write(io, "$(vi.value)")
      first_elem = false
   end

   write(io, " /")
end

function translate_defvars(
   io::GAMSTranslateStream,
   model::Optimizer
)
   translate_defvars(io, model, nothing)
   if model.n_binary > 0
      translate_defvars(io, model, VARTYPE_BINARY)
   end
   if model.n_integer > 0
      translate_defvars(io, model, VARTYPE_INTEGER)
   end
   if model.n_semicont > 0
      translate_defvars(io, model, VARTYPE_SEMICONT)
   end
   if model.n_semiint > 0
      translate_defvars(io, model, VARTYPE_SEMIINT)
   end
   if length(model.sos1_constraints) > 0
      translate_defvars(io, model, VARTYPE_SOS1)
   end
   if length(model.sos2_constraints) > 0
      translate_defvars(io, model, VARTYPE_SOS2)
   end
end

function translate_defvars(
   io::GAMSTranslateStream,
   model::Optimizer,
   filter::Union{GAMSVarType, Nothing}
)
   if filter == VARTYPE_SOS1
      n = length(model.sos1_constraints)
   elseif filter == VARTYPE_SOS2
      n = length(model.sos2_constraints)
   else
      n = length(model.variable_info)
   end

   if filter == VARTYPE_BINARY
      write(io, "Binary ")
   elseif filter == VARTYPE_INTEGER
      write(io, "Integer ")
   elseif filter == VARTYPE_SEMICONT
      write(io, "SemiCont ")
   elseif filter == VARTYPE_SEMIINT
      write(io, "SemiInt ")
   elseif filter == VARTYPE_SOS1
      write(io, "SOS1 ")
   elseif filter == VARTYPE_SOS2
      write(io, "SOS2 ")
   end
   if n == 1
      writeln(io, "Variable")
   else
      writeln(io, "Variables")
   end
   write(io, "  ")

   first = true
   if model.objvar && (isnothing(filter) || filter == VARTYPE_FREE)
      if n == 0
         write(io, "objvar;")
         return
      end
      write(io, "objvar")
      first = false
   end

   for i in 1:n
      if ! isnothing(filter) && model.variable_info[i].type != filter
         continue
      end
      if ! first
         write(io, ", ")
      end
      write(io, variable_name(model, MOI.VariableIndex(i)))
      first = false
   end

   # add sos1 variables
   if isnothing(filter) || filter == VARTYPE_SOS1
      for i in 1:length(model.sos1_constraints)
         if ! first
            write(io, ", ")
         end
         write(io, "sos1_x$i(sos1_s$(i))")
         first = false
      end
   end

   # add sos2 variables
   if isnothing(filter) || filter == VARTYPE_SOS2
      for i in 1:length(model.sos2_constraints)
         if ! first
            write(io, ", ")
         end
         write(io, "sos2_x$i(sos2_s$(i))")
         first = false
      end
   end
   writeln(io, ";\n")
end

function translate_defequs(
   io::GAMSTranslateStream,
   model::Optimizer
)

   m = model.m + length(model.sos1_constraints) + length(model.sos2_constraints) + length(model.complementarity_constraints)

   if m == 0 && ! model.objvar
      return
   end

   if m == 1
      writeln(io, "Equation")
   else m > 1
      writeln(io, "Equations")
   end
   write(io, "  ")

   if model.objvar && m == 0
      writeln(io, "obj;\n")
      return
   end

   first = true
   if model.objvar
      write(io, "obj")
      first = false
   end

   for i in 1:length(model.linear_le_constraints)
      name = equation_name(model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64}}(i))
      write(io, first ? name : ", " * name)
      first = false
   end
   for i in 1:length(model.linear_ge_constraints)
      name = equation_name(model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64}}(i))
      write(io, first ? name : ", " * name)
      first = false
   end
   for i in 1:length(model.linear_eq_constraints)
      name = equation_name(model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.EqualTo{Float64}}(i))
      write(io, first ? name : ", " * name)
      first = false
   end
   for i in 1:length(model.quadratic_le_constraints)
      name = equation_name(model, MOI.ConstraintIndex{MOI.ScalarQuadraticFunction{Float64}, MOI.LessThan{Float64}}(i))
      write(io, first ? name : ", " * name)
      first = false
   end
   for i in 1:length(model.quadratic_ge_constraints)
      name = equation_name(model, MOI.ConstraintIndex{MOI.ScalarQuadraticFunction{Float64}, MOI.GreaterThan{Float64}}(i))
      write(io, first ? name : ", " * name)
      first = false
   end
   for i in 1:length(model.quadratic_eq_constraints)
      name = equation_name(model, MOI.ConstraintIndex{MOI.ScalarQuadraticFunction{Float64}, MOI.EqualTo{Float64}}(i))
      write(io, first ? name : ", " * name)
      first = false
   end
   for i in 1:model.m_nonlin
      idx = i + _offset_nonlin(model)
      write(io, first ? "eq$idx" : ", eq$idx")
      first = false
   end

   # add sos1 constraints
   for i in 1:length(model.sos1_constraints)
      if ! first
         write(io, ", ")
      end
      write(io, "sos1_eq$(i)(sos1_s$(i))")
      first = false
   end

   # add sos2 constraints
   for i in 1:length(model.sos2_constraints)
      if ! first
         write(io, ", ")
      end
      write(io, "sos2_eq$(i)(sos2_s$(i))")
      first = false
   end

   # add complementarity constraints
   for (i, comp) in enumerate(model.complementarity_constraints)
      for j in 1:(comp.set.dimension ÷ 2)
         if ! first
            write(io, ", ")
         end
         write(io, "eq$(i)_$(j)")
      end
      first = false
   end

   writeln(io, ";\n")
end

function translate_coefficient(
   io::GAMSTranslateStream,
   coef::Float64;
   first::Bool=false
)
   if coef < 0.0
      if first && coef == -1.0
         write(io, "-")
      elseif first
         write(io, "-" * dbl2str(-coef) * " * ")
      elseif coef == -1.0
         write(io, " - ")
      else
         write(io, " - " * dbl2str(-coef) * " * ")
      end
   elseif coef > 0.0
      if first && coef == 1.0
      elseif first
         write(io, dbl2str(coef) * " * ")
      elseif coef == 1.0
         write(io, " + ")
      else
         write(io, " + " * dbl2str(coef) * " * ")
      end
   end
   return
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::MOI.VariableIndex
)
   write(io, variable_name(model, idx))
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   terms::Vector{MOI.ScalarAffineTerm{Float64}}
)
   first = true
   for (j, term) in enumerate(terms)
      if term.coefficient == 0.0
         continue
      end
      translate_coefficient(io, term.coefficient, first=first)
      write(io, variable_name(model, term.variable))
      first = false
   end

   if first
      write(io, "0.0")
   end
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   func::MOI.ScalarAffineFunction{Float64}
)
   translate_function(io, model, func.terms)
   if func.constant < 0.0
      write(io, " - " * dbl2str(-func.constant))
   elseif func.constant > 0.0
      write(io, " + " * dbl2str(func.constant))
   end
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   terms::Vector{MOI.VectorAffineTerm{Float64}}
)
   sterms = [term.scalar_term for term in terms]
   translate_function(io, model, sterms)
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   func::MOI.ScalarQuadraticFunction{Float64}
)
   naff = length(func.affine_terms)

   if naff + length(func.quadratic_terms) == 0
      write(io, "0.0")
      return
   end

   first = true
   if naff > 0
      translate_function(io, model, func.affine_terms)
      first = false
   end

   for (j, term) in enumerate(func.quadratic_terms)
      if term.coefficient == 0.0
         continue
      end
      idx1 = term.variable_1
      idx2 = term.variable_2
      if idx1 == idx2
         translate_coefficient(io, term.coefficient / 2.0, first=first)
      else
         translate_coefficient(io, term.coefficient, first=first)
      end
      write(io, variable_name(model, idx1) * " * " * variable_name(model, idx2))
      first = false
   end

   if func.constant < 0.0
      write(io, " - " * dbl2str(-func.constant))
   elseif func.constant > 0.0
      write(io, " + " * dbl2str(func.constant))
   end
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   func::Expr;
   is_parenthesis::Bool = false
)
   if length(func.args) == 0
      write(io, "0.0")
      return
   end

   op = func.args[1]

   if op in (:+, :-)
      @assert length(func.args) >= 2
      if ! is_parenthesis
         write(io, "(")
      end
      if length(func.args) == 2
         write(io, "(" * string(op))
         translate_function(io, model, func.args[2], is_parenthesis=false)
         write(io, ")")
      else
         translate_function(io, model, func.args[2], is_parenthesis=true)
         for i in 3:length(func.args)
            write(io, " " * string(op) * " ")
            translate_function(io, model, func.args[i], is_parenthesis=(op==:+))
         end
      end
      if ! is_parenthesis
         write(io, ")")
      end

   elseif op in (:*, :/)
      @assert length(func.args) >= 3
      if ! is_parenthesis
         write(io, "(")
      end
      translate_function(io, model, func.args[2], is_parenthesis=false)
      for i in 3:length(func.args)
         write(io, " " * string(op) * " ")
         translate_function(io, model, func.args[i], is_parenthesis=false)
      end
      if ! is_parenthesis
         write(io, ")")
      end

   elseif op == :^
      @assert length(func.args) == 3
      if func.args[3] == 1.0
         translate_function(io, model, func.args[2])
      elseif func.args[3] == 2.0
         write(io, "sqr(")
         translate_function(io, model, func.args[2], is_parenthesis=true)
         write(io, ")")
      elseif func.args[3] isa Real && func.args[3] == round(func.args[3])
         write(io, "power(")
         translate_function(io, model, func.args[2], is_parenthesis=true)
         write(io, ", ")
         translate_function(io, model, func.args[3], is_parenthesis=true)
         write(io, ")")
      else
         translate_function(io, model, func.args[2], is_parenthesis=false)
         write(io, "**")
         translate_function(io, model, func.args[3], is_parenthesis=false)
      end

   elseif op in (:sqrt, :log, :log10, :log2, :exp, :sin, :sinh, :cos, :cosh, :tan, :tanh, :abs, :sign)
      @assert length(func.args) == 2
      write(io, string(op) * "(")
      translate_function(io, model, func.args[2], is_parenthesis=true)
      write(io, ")")

   elseif op in (:acos,)
      @assert length(func.args) == 2
      write(io, "arccos(")
      translate_function(io, model, func.args[2], is_parenthesis=true)
      write(io, ")")

   elseif op in (:asin,)
      @assert length(func.args) == 2
      write(io, "arcsin(")
      translate_function(io, model, func.args[2], is_parenthesis=true)
      write(io, ")")

   elseif op in (:atan,)
      @assert length(func.args) == 2
      write(io, "arctan(")
      translate_function(io, model, func.args[2], is_parenthesis=true)
      write(io, ")")

   elseif op in (:max, :min, :mod)
      @assert length(func.args) >= 2
      write(io, string(op) * "(")
      translate_function(io, model, func.args[2], is_parenthesis=true)
      for i in 3:length(func.args)
         write(io, ", ")
         translate_function(io, model, func.args[i], is_parenthesis=true)
      end
      write(io, ")")

   elseif typeof(op) == Symbol && func.args[2] isa MOI.VariableIndex
      write(io, variable_name(model, func.args[2]))
   else
      error("Unrecognized operation ($op)")
   end
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   func::Symbol;
   is_parenthesis::Bool = false
)
   write(io, string(func))
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   func::Float64;
   is_parenthesis::Bool = false
)
   if is_parenthesis && func > 0.0
      write(io, dbl2str(func))
   else
      write(io, "(" * dbl2str(func) * ")")
   end
end

function translate_function(
   io::GAMSTranslateStream,
   model::Optimizer,
   func::Int;
   is_parenthesis::Bool = false
)
   write(io, "$func")
end

function translate_objective(
   io::GAMSTranslateStream,
   model::Optimizer
)
   # do nothing if we don't need objective variable
   if model.model_type == GAMS.MODEL_TYPE_MCP || model.model_type == GAMS.MODEL_TYPE_CNS
      return
   end
   if ! model.objvar
      if ! (typeof(model.objective) == MOI.VariableIndex)
         error("GAMS needs obj variable")
      end
      return
   end

   if model.sense == MOI.MIN_SENSE
      write(io, "obj.. objvar =G= ")
   elseif model.sense == MOI.MAX_SENSE
      write(io, "obj.. objvar =L= ")
   else
      writeln(io, "obj.. objvar =E= 0.0;");
      return
   end

   if ! isnothing(model.nlp_data) && model.nlp_data.has_objective
      obj_expr = MOI.objective_expr(model.nlp_data.evaluator)
      translate_function(io, model, obj_expr, is_parenthesis=true)
   else
      translate_function(io, model, model.objective)
   end

   writeln(io, ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer
)
   for i in 1:length(model.linear_le_constraints)
      translate_equations(io, model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.LessThan{Float64}}(i))
   end
   for i in 1:length(model.linear_ge_constraints)
      translate_equations(io, model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.GreaterThan{Float64}}(i))
   end
   for i in 1:length(model.linear_eq_constraints)
      translate_equations(io, model, MOI.ConstraintIndex{MOI.ScalarAffineFunction{Float64}, MOI.EqualTo{Float64}}(i))
   end
   for i in 1:length(model.quadratic_le_constraints)
      translate_equations(io, model, MOI.ConstraintIndex{MOI.ScalarQuadraticFunction{Float64}, MOI.LessThan{Float64}}(i))
   end
   for i in 1:length(model.quadratic_ge_constraints)
      translate_equations(io, model, MOI.ConstraintIndex{MOI.ScalarQuadraticFunction{Float64}, MOI.GreaterThan{Float64}}(i))
   end
   for i in 1:length(model.quadratic_eq_constraints)
      translate_equations(io, model, MOI.ConstraintIndex{MOI.ScalarQuadraticFunction{Float64}, MOI.EqualTo{Float64}}(i))
   end
   for (i, con) in enumerate(model.complementarity_constraints)
      translate_equations(io, model, i, con.func, con.set)
   end
   for i in 1:model.m_nonlin
      translate_equations(io, model, i, MOI.constraint_expr(model.nlp_data.evaluator, i))
   end
   writeln(io, "")
   for (i, con) in enumerate(model.sos1_constraints)
      translate_equations(io, model, i, con.func, con.set)
   end
   for (i, con) in enumerate(model.sos2_constraints)
      translate_equations(io, model, i, con.func, con.set)
   end
   writeln(io, "")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::MOI.ConstraintIndex{F, MOI.LessThan{Float64}}
) where {
   F <: Union{
      MOI.ScalarAffineFunction{Float64},
      MOI.ScalarQuadraticFunction{Float64},
   }
}
   write(io, equation_name(model, idx) * ".. ")
   translate_function(io, model, _constraints(model, F, MOI.LessThan{Float64})[idx.value].func)
   writeln(io, " =L= " * dbl2str(_constraints(model, F, MOI.LessThan{Float64})[idx.value].set.upper) * ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::MOI.ConstraintIndex{F, MOI.GreaterThan{Float64}}
) where {
   F <: Union{
      MOI.ScalarAffineFunction{Float64},
      MOI.ScalarQuadraticFunction{Float64},
   }
}
   write(io, equation_name(model, idx) * ".. ")
   translate_function(io, model, _constraints(model, F, MOI.GreaterThan{Float64})[idx.value].func)
   writeln(io, " =G= " * dbl2str(_constraints(model, F, MOI.GreaterThan{Float64})[idx.value].set.lower) * ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::MOI.ConstraintIndex{F, MOI.EqualTo{Float64}}
) where {
   F <: Union{
      MOI.ScalarAffineFunction{Float64},
      MOI.ScalarQuadraticFunction{Float64},
   }
}
   write(io, equation_name(model, idx) * ".. ")
   translate_function(io, model, _constraints(model, F, MOI.EqualTo{Float64})[idx.value].func)
   writeln(io, " =E= " * dbl2str(_constraints(model, F, MOI.EqualTo{Float64})[idx.value].set.value) * ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::Int,
   func::Expr
)
   if length(func.args) == 0
      return
   end
   @assert(length(func.args) == 3)

   idx += _offset_nonlin(model)

   write(io, "eq$idx.. ")
   translate_function(io, model, func.args[2], is_parenthesis=true)
   if func.args[1] == :(==)
      write(io, " =E= ")
   elseif func.args[1] == :(<=)
      write(io, " =L= ")
   else
      write(io, " =G= ")
   end
   translate_function(io, model, func.args[3], is_parenthesis=true)
   writeln(io, ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::Int,
   func::MOI.VectorOfVariables,
   set::MOI.SOS1{Float64}
)
   write(io, "sos1_eq$idx(sos1_s$idx).. sos1_x$idx(sos1_s$idx) =e= ")
   for (i, vi) in enumerate(func.variables)
      if i > 1
         write(io, " + ")
      end
      write(io, variable_name(model, vi) * "\$sameas('$(vi.value)',sos1_s$idx)")
   end
   writeln(io, ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::Int,
   func::MOI.VectorOfVariables,
   set::MOI.SOS2{Float64}
)
   write(io, "sos2_eq$idx(sos2_s$idx).. sos2_x$idx(sos2_s$idx) =e= ")
   for (i, vi) in enumerate(func.variables)
      if i > 1
         write(io, " + ")
      end
      write(io, variable_name(model, vi) * "\$sameas('$(vi.value)',sos2_s$idx)")
   end
   writeln(io, ";")
   return
end

function translate_equations(
   io::GAMSTranslateStream,
   model::Optimizer,
   idx::Int,
   func::MOI.VectorAffineFunction,
   set::MOI.Complements
)
   for i in 1:set.dimension ÷ 2
      row = filter(term -> term.output_index == i, func.terms)
      write(io, "eq$(idx)_$(i).. ")
      translate_function(io, model, row)
      if func.constants[i] < 0
         write(io, " - " * dbl2str(-func.constants[i]))
      elseif func.constants[i] > 0.0
         write(io, " + " * dbl2str(func.constants[i]))
      end
      writeln(io, " =N= 0;")
   end
end

function translate_vardata(
   io::GAMSTranslateStream,
   model::Optimizer
)
   for (i, var) in enumerate(model.variable_info)
      if _is_fixed(var)
         writeln(io, variable_name(model, MOI.VariableIndex(i)) * ".fx = " * dbl2str(var.lower_bound) * ";")
         continue
      end
      if _has_lower_bound(var)
         writeln(io, variable_name(model, MOI.VariableIndex(i)) * ".lo = " * dbl2str(var.lower_bound) * "; ")
      end
      if _has_start(var)
         writeln(io, variable_name(model, MOI.VariableIndex(i)) * ".l = " * dbl2str(var.start) * "; ")
      end
      if _has_upper_bound(var)
         writeln(io, variable_name(model, MOI.VariableIndex(i)) * ".up = " * dbl2str(var.upper_bound) * ";")
      end
   end
   write(io, "\n")
end

function translate_solve(
   io::GAMSTranslateStream,
   model::Optimizer,
   name::String
)
   # model statement
   if model.model_type == GAMS.MODEL_TYPE_MPEC || model.model_type == GAMS.MODEL_TYPE_MCP
      write(io, "Model $name / ")

      m = model.m + length(model.sos1_constraints) + length(model.sos2_constraints) + length(model.complementarity_constraints)

      first = true
      if model.objvar
         write(io, "obj")
         first = false
      end

      for i in 1:model.m
         if ! first
            write(io, ", ")
         end
         write(io, "eq$i")
         first = false
      end

      # add sos1 constraints
      for i in 1:length(model.sos1_constraints)
         if ! first
            write(io, ", ")
         end
         write(io, "sos1_eq$(i)(sos1_s$(i))")
         first = false
      end

      # add sos2 constraints
      for i in 1:length(model.sos2_constraints)
         if ! first
            write(io, ", ")
         end
         write(io, "sos2_eq$(i)(sos2_s$(i))")
         first = false
      end

      # add complementarity constraints
      for (i, comp) in enumerate(model.complementarity_constraints)
         d = comp.set.dimension ÷ 2
         for j in 1:d
            if ! first
               write(io, ", ")
            end
            var = filter(term -> term.output_index == j + d, comp.func.terms)
            var_str = variable_name(model, var[1].scalar_term.variable)
            write(io, "eq$(i)_$(j).$(var_str)")
            first = false
         end
      end
      writeln(io, " /;")
   else
      writeln(io, "Model $name / all /;")
   end

   # solve statement
   write(io, "Solve $name using ")
   write(io, label(model.model_type))
   if model.model_type != GAMS.MODEL_TYPE_MCP && model.model_type != GAMS.MODEL_TYPE_CNS
      if model.sense == MOI.MAX_SENSE
         write(io, " maximizing ")
      else
         write(io, " minimizing ")
      end
      if model.objvar
         write(io, "objvar")
      elseif typeof(model.objective) == MOI.VariableIndex
         write(io, variable_name(model, model.objective))
      else
         error("GAMS needs obj variable")
      end
   end
   writeln(io, ";\n")
end
