signature rlData =
sig

  include Abbrev

  val uni_flag : bool ref
  val uniq_flag : bool ref
  val computation_data :  
    term list -> int * int -> int * int * int -> (term * real list) list
  val inter_traintest : (term * real list) list * (term * real list) list -> int  
  val eval_ground : term -> int 
  val random_num : term list -> (int * int) -> term

  val rw : term -> int list option
  val full_trace : term -> ((term * int list) * int) list
  
  val term_cost : term -> int
  val proof_data : term list -> int * int -> int * int * int -> 
    (term * int) list
  val proof_data_glob : (term * int) list

end
