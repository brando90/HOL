signature term_pp =
sig

  val pp_term :
    term_grammar.grammar -> parse_type.grammar -> Portable.ppstream ->
    Term.term -> unit

end;


