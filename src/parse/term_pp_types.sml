structure term_pp_types :> term_pp_types = struct
  datatype grav = Top | RealTop | Prec of (int * string)
  type sysprinter = (grav * grav * grav) -> int -> Term.term -> unit
  type userprinter =
    sysprinter -> (grav * grav * grav) -> int -> Portable.ppstream ->
    Term.term -> unit
  exception UserPP_Failed


end;
