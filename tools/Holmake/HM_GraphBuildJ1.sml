structure HM_GraphBuildJ1 :> HM_GraphBuildJ1 =
struct

open Holmake_tools

type build_command = HM_DepGraph.t -> include_info -> buildcmds -> File -> bool
type mosml_build_command =
     Holmake_types.env ->
     {noecho : bool, ignore_error : bool, command : string} ->
     File list ->
     OS.Process.status option
type 'optv buildinfo_t = {
  optv : 'optv, hmake_options : string list,
  actual_overlay : string option,
  envlist : string -> string list,
  hmenv : Holmake_types.env,
  quit_on_failure : bool,
  outs : Holmake_tools.output_functions,
  SIGOBJ : string
}

fun is_heap_only() =
  case OS.Process.getEnv Systeml.build_after_reloc_envvar of
      SOME "1" => true
    | _ => false

fun b2status true = HM_DepGraph.Succeeded
  | b2status false = HM_DepGraph.Failed{needed=true}

fun updall nodes st g =
  List.foldl (fn (n,g) => HM_DepGraph.updnode(n,st) g) g nodes

fun upd1 node st g = HM_DepGraph.updnode(node,st) g

fun graphbuildj1 static_info =
  let
    val {build_command, mosml_build_command, outs, keep_going,
         quiet, hmenv, system} = static_info
    val {warn,diag,tgtfatal,info,...} = (outs : Holmake_tools.output_functions)
    val diagK = diag o (fn x => fn _ => x)
    fun build_graph g =
      let
        open HM_DepGraph
        val _ = diagK "Entering HMGBJ1.build_graph"
        val bc = build_command g
        fun recurse retval g =
          case find_runnable g of
              NONE => (retval, g)
            | SOME (n, nI : string nodeInfo) =>
              let
                val deps = map #2 (#dependencies nI)
                val depfs = map toFile deps
                val target_s = #target nI
                fun k upd res =
                  let
                    val g = upd (b2status res) g
                  in
                    if res then recurse retval g
                    else if keep_going then recurse OS.Process.failure g
                    else (OS.Process.success, g)
                  end
                fun stdprocess () =
                  case #command nI of
                      BuiltInCmd (BIC_Compile, ii) =>
                      (diagK("J1Build: Running built-in compile on " ^
                             #target nI);
                       case toFile (#target nI) of
                           UI c => k (upd1 n) (bc ii (Compile depfs) (SIG c))
                         | UO c => k (upd1 n) (bc ii (Compile depfs) (SML c))
                         | ART (RawArticle s) =>
                             k (upd1 n) (bc ii
                                            (BuildArticle(s,depfs))
                                            (SML (Script s)))
                         | ART (ProcessedArticle s) =>
                             k (upd1 n)
                               (bc ii (ProcessArticle s) (ART (RawArticle s)))
                         | _ => raise Fail ("bg tgt = " ^ #target nI))
                    | cmd as (BuiltInCmd (BIC_BuildScript thyname, ii)) =>
                      let
                        val others = find_nodes_by_command g cmd
                      in
                        k (updall (n::others))
                          (bc ii
                              (BuildScript(thyname, depfs))
                              (SML (Script thyname)))
                      end
                    | cmd as SomeCmd c =>
                      let
                        val hypargs as {noecho,ignore_error,command=c} =
                            process_hypat_options c
                      in
                        case mosml_build_command hmenv hypargs depfs of
                            SOME r => k (upd1 n) (OS.Process.isSuccess r)
                          | NONE =>
                            let
                              val () =
                                  if not noecho andalso not quiet then
                                    (TextIO.output(TextIO.stdOut, c ^ "\n");
                                     TextIO.flushOut TextIO.stdOut)
                                  else ()
                              val others = find_nodes_by_command g cmd
                              val result = system c
                              val res_b = OS.Process.isSuccess result
                            in
                              if not res_b andalso ignore_error
                              then
                                (warn ("[" ^ #target nI ^ "] Error (ignored)");
                                 k (updall (n::others)) true)
                              else k (updall (n::others)) res_b
                            end
                      end
                    | NoCmd => k (upd1 n) true
              in
                if not (#phony nI) andalso exists_readable (#target nI) andalso
                   #seqnum nI = 0
                then
                  let
                    val _ = diagK ("May not need to rebuild "^target_s)
                  in
                    case List.find
                           (fn (_, d) => forces_update_of(d,#target nI))
                           (#dependencies nI)
                     of
                        NONE => (diagK ("Can skip work on "^target_s);
                                 k (upd1 n) true)
                      | SOME (_,d) =>
                        (diagK ("Dependency "^d^" forces rebuild of "^target_s);
                         stdprocess())
                  end
                else
                  stdprocess()
              end
      in
        recurse OS.Process.success g
      end
  in
    build_graph
  end

end
