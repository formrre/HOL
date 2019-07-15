signature mlReinforce =
sig

  include Abbrev

  (* 'a is the type of board, 'b is the type for move *)
  type ('a,'b) gamespec =
    {
    movel : 'b list,
    move_compare : 'b * 'b -> order,
    string_of_move : 'b -> string,
    filter_sit : 'a -> (('b * real) list -> ('b * real) list),
    status_of : ('a -> psMCTS.status),
    apply_move : ('b -> 'a -> 'a),
    operl : (term * int) list,
    nntm_of_sit: 'a -> term,
    mk_targetl: int -> int -> 'a list,
    write_targetl: string -> 'a list -> unit,
    read_targetl: string -> 'a list,
    max_bigsteps : 'a -> int
    }
  type dhex = (term * real list * real list) list
  type dhtnn = mlTreeNeuralNetwork.dhtnn
  type flags = bool * bool * bool
  type 'a extgamespec =
     (flags * dhtnn, 'a, bool * dhex) smlParallel.extspec


  (* rl parameters *)
  val ngen_glob : int ref
  val ntarget_compete : int ref
  val ntarget_explore : int ref
  val level_glob : int ref
  val level_threshold : real ref
  (* nn parameters *)
  val exwindow_glob : int ref
  val uniqex_flag : bool ref
  val lr_glob : real ref
  val dim_glob : int ref
  val batchsize_glob : int ref
  val nepoch_glob : int ref
  val ncore_train_glob : int ref
  (* mcts parameters *)
  val nsim_glob : int ref
  val decay_glob : real ref
  val temp_flag : bool ref
  val ncore_mcts_glob : int ref

  val eval_dir : string

  (* debugging *)
  val mcts_test : 
    int -> ('a,'b) gamespec -> dhtnn -> 'a -> ('a,'b) psMCTS.tree
  val n_bigsteps_test : ('a,'b) gamespec -> mlTreeNeuralNetwork.dhtnn ->
    'a -> ('a,'b) psMCTS.node list

  (* training *)
  val random_dhtnn_gamespec :
    ('a,'b) gamespec -> dhtnn
  val train_dhtnn : ('a,'b) gamespec -> dhex -> dhtnn

  (* external parallel exploration specification *)
  val mk_extspec : string -> ('a,'b) gamespec -> 'a extgamespec

  (* reinforcement learning loop *)
  val logfile_glob : string ref
  val summary : string -> unit
  val start_rl_loop : ('a,'b) gamespec * 'a extgamespec -> dhex * dhtnn

end