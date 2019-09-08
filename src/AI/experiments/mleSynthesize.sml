(* ========================================================================= *)
(* FILE          : mleSynthesize.sml                                         *)
(* DESCRIPTION   : Specification of a term synthesis game                    *)
(* AUTHOR        : (c) Thibault Gauthier, Czech Technical University         *)
(* DATE          : 2019                                                      *)
(* ========================================================================= *)

structure mleSynthesize :> mleSynthesize =
struct

open HolKernel Abbrev boolLib aiLib smlParallel psMCTS psTermGen
  mlTreeNeuralNetwork mlTacticData mlReinforce mleLib mleArithData

val ERR = mk_HOL_ERR "mleSynthesize"

(* -------------------------------------------------------------------------
   Board
   ------------------------------------------------------------------------- *)

type board = ((term * int) * term)

val active_var = ``active_var:num``;

fun mk_startsit tm = ((tm,mleArithData.eval_numtm tm),active_var)
fun dest_startsit ((tm,_),_) = tm

fun is_ground tm = not (tmem active_var (free_vars_lr tm))

val synt_operl = [(active_var,0)] @ operl_of ``SUC 0 + 0 = 0 * 0``
fun nntm_of_sit ((ctm,_),tm) = mk_eq (ctm,tm)

fun normal_status_of ((ctm,n),tm) =
  let val ntm = mk_sucn n in
    if term_eq ntm tm then Win
    else if is_ground tm orelse term_size tm > 2 * n + 1 then Lose
    else Undecided
  end

fun copy_status_of ((ctm,n),tm) =
  if term_eq ctm tm then Win
  else if is_ground tm orelse term_size tm > 2 * (term_size ctm) + 1 then Lose
  else Undecided

fun eval_status_of ((ctm,n),tm) =
  if is_ground tm andalso mleArithData.eval_numtm tm = n then Win
  else if is_ground tm orelse 
    term_size tm > 2 * Int.min (n,term_size ctm) + 1 
    then Lose
  else Undecided

(* -------------------------------------------------------------------------
   Move
   ------------------------------------------------------------------------- *)

type move = (term * int)
val movel = operl_of ``SUC 0 + 0 * 0``;
val move_compare = cpl_compare Term.compare Int.compare

fun action_oper (oper,n) tm =
  let
    val res = list_mk_comb (oper, List.tabulate (n, fn _ => active_var))
    val sub = [{redex = active_var, residue = res}]
  in
    subst_occs [[1]] sub tm
  end

fun apply_move move (ctmn,tm) = (ctmn, action_oper move tm)

fun filter_sit sit = (fn l => l)

fun string_of_move (tm,_) = tts tm

fun write_targetl file targetl =
  let val tml = map dest_startsit targetl in 
    export_terml (file ^ "_targetl") tml
  end

fun read_targetl file =
  let val tml = import_terml (file ^ "_targetl") in
    map mk_startsit tml
  end

fun max_bigsteps ((ctm,n),_) = 4 * Int.max (n,term_size ctm) + 5

(* -------------------------------------------------------------------------
   Level
   ------------------------------------------------------------------------- *)

val train_file = dataarith_dir ^ "/train"
fun min_sizeeval x = Int.min (term_size x, eval_numtm x)

fun order_train baseout f =
  let
    val l1 = import_terml train_file
    val l2 = map (fn x => (x, f x)) l1
    val l3 = dict_sort compare_imin l2
  in
    export_terml (dataarith_dir ^ "/" ^ baseout) (map fst l3)
  end

fun mk_targetl basein level ntarget =
  let
    val tml1 = import_terml (dataarith_dir ^ "/" ^ basein)
    val tmll2 = map shuffle (first_n level (mk_batch 400 tml1))
    val tml3 = List.concat (list_combine tmll2)
  in
    map mk_startsit (first_n ntarget tml3)
  end

fun create_sorteddata () =
  (
  order_train "train_evalsorted" eval_numtm;
  order_train "train_sizesorted" term_size;
  order_train "train_sizeevalsorted" min_sizeeval
  )

(* -------------------------------------------------------------------------
   Interfaces: normal, copy, eval
   ------------------------------------------------------------------------- *)

val normal_gamespec =
  {
  movel = movel,
  move_compare = move_compare,
  status_of = normal_status_of,
  filter_sit = filter_sit,
  apply_move = apply_move,
  operl = synt_operl,
  nntm_of_sit = nntm_of_sit,
  mk_targetl = mk_targetl "train_evalsorted",
  write_targetl = write_targetl,
  read_targetl = read_targetl,
  string_of_move = string_of_move,
  max_bigsteps = max_bigsteps
  }

val normal_extspec = mk_extspec "mleSynthesize.normal_extspec" normal_gamespec

val copy_gamespec =
  {
  movel = movel,
  move_compare = move_compare,
  status_of = copy_status_of,
  filter_sit = filter_sit,
  apply_move = apply_move,
  operl = synt_operl,
  nntm_of_sit = nntm_of_sit,
  mk_targetl = mk_targetl "train_sizesorted",
  write_targetl = write_targetl,
  read_targetl = read_targetl,
  string_of_move = string_of_move,
  max_bigsteps = max_bigsteps
  }

val copy_extspec = mk_extspec "mleSynthesize.copy_extspec" copy_gamespec

val eval_gamespec =
  {
  movel = movel,
  move_compare = move_compare,
  status_of = eval_status_of,
  filter_sit = filter_sit,
  apply_move = apply_move,
  operl = synt_operl,
  nntm_of_sit = nntm_of_sit,
  mk_targetl = mk_targetl "train_sizeevalsorted",
  write_targetl = write_targetl,
  read_targetl = read_targetl,
  string_of_move = string_of_move,
  max_bigsteps = max_bigsteps
  }

val eval_extspec = mk_extspec "mleSynthesize.eval_extspec" eval_gamespec

(* -------------------------------------------------------------------------
   Statistics
   ------------------------------------------------------------------------- *)

fun maxeval_atgen () =
  let
    val tml = mlTacticData.import_terml (dataarith_dir ^ "/train_evalsorted")
  in
    map (list_imax o map eval_numtm) (mk_batch 400 tml)
  end

fun stats_eval file =
  let
    val l0 = import_terml file
    val l1 = map (fn x => (x,eval_numtm x)) l0;
    val l1' = filter (fn x => snd x <= 100) l1;
    val _  = print_endline (its (length l1'));
    val l2 = dlist (dregroup Int.compare (map swap l1'));
  in
    map_snd length l2
  end

(* -------------------------------------------------------------------------
   Reinforcement learning
   ------------------------------------------------------------------------- *)

(*
load "mleSynthesize"; open mleSynthesize;
load "mlTreeNeuralNetwork"; open mlTreeNeuralNetwork;
load "mlReinforce"; open mlReinforce;
load "smlParallel"; open smlParallel;
load "aiLib"; open aiLib;

(* create_sorteddata (); *)

ncore_mcts_glob := 12;
ncore_train_glob := 4;
ntarget_compete := 400;
ntarget_explore := 400;
exwindow_glob := 40000;
uniqex_flag := false;
dim_glob := 12;
lr_glob := 0.02;
batchsize_glob := 16;
decay_glob := 0.99;
level_glob := 1;
nsim_glob := 1600;
nepoch_glob := 100;
ngen_glob := 100;

logfile_glob := "mleSynthesize_normal1";
parallel_dir := HOLDIR ^ "/src/AI/sml_inspection/parallel_" ^ (!logfile_glob);
val r = start_rl_loop (normal_gamespec,normal_extspec);

logfile_glob := "mleSynthesize_copy1";
parallel_dir := HOLDIR ^ "/src/AI/sml_inspection/parallel_" ^ (!logfile_glob);
val r = start_rl_loop (copy_gamespec,copy_extspec);

logfile_glob := "mleSynthesize_eval1";
parallel_dir := HOLDIR ^ "/src/AI/sml_inspection/parallel_" ^ (!logfile_glob);
val r = start_rl_loop (eval_gamespec,eval_extspec);
*)

(* -------------------------------------------------------------------------
   Small test
   ------------------------------------------------------------------------- *)

(*
load "mleRewrite"; open mleRewrite;
load "mlReinforce"; open mlReinforce;
load "psMCTS"; open psMCTS;
nsim_glob := 10000;
decay_glob := 0.9;
val _ = n_bigsteps_test gamespec (random_dhtnn_gamespec gamespec)
(mk_startsit ``SUC 0 * SUC 0``);

dim_glob := 4;
val tree = mcts_test 10000 gamespec (random_dhtnn_gamespec gamespec)
(mk_startsit ``SUC (SUC 0) + SUC 0``);
val nodel = trace_win (#status_of gamespec) tree [];

*)








end (* struct *)
