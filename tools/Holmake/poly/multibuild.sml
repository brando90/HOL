structure multibuild =
struct

open ProcessMultiplexor HM_DepGraph Holmake_tools

type 'a mosml_build_command = 'a HM_GraphBuildJ1.mosml_build_command
datatype buildresult =
         BR_OK
       | BR_ClineK of { cline : string * string list,
                        job_kont : (string -> unit) -> OS.Process.status ->
                                   bool,
                        other_nodes : HM_DepGraph.node list }
       | BR_Failed

val RealFail = Failed{needed=true}

infix ++
fun p1 ++ p2 = OS.Path.concat(p1, p2)
val loggingdir = ".hollogs"

fun pushd d f x =
    let
      val d0 = OS.FileSys.getDir()
      val _ = OS.FileSys.chDir d
    in
      f x before OS.FileSys.chDir d0
    end



fun graphbuild optinfo g =
  let
    val { build_command,
          mosml_build_command : GraphExtra.t mosml_build_command,
          warn, tgtfatal, diag,
          keep_going, quiet, hmenv, jobs, info, time_limit,
          relocbuild } = optinfo
    val _ = diag "Starting graphbuild"
    fun dropthySuffix s =
        if List.exists
             (fn sfx => String.isSuffix ("Theory." ^ sfx) s)
             ["dat", "sml", "sig"]
        then String.substring(s,0,String.size s - 4)
        else s
    fun safetag d t =
        if d = OS.Path.dir t then dropthySuffix (OS.Path.file t)
        else String.map (fn #"/" => #"-" | c => c) t
    fun genLF {tag, dir} =
        let
          val ldir = dir ++ loggingdir
          val _ = OS.FileSys.mkDir ldir handle _ => ()
        in
          ldir ++ safetag dir tag
        end

    val monitor =
        MB_Monitor.new {info = info, warn = warn, genLogFile = genLF,
                        time_limit = time_limit}

    val env =
        (if relocbuild then [Systeml.build_after_reloc_envvar^"=1"] else []) @
        Posix.ProcEnv.environ()
    fun cline_to_command (s, args) = {executable = s, nm_args = args, env = env}
    fun shell_command s =
      {executable = "/bin/sh", nm_args = ["/bin/sh", "-c", s], env = env}

    fun genjob (g,ok) =
      case (ok,find_runnable g) of
          (false, _) => GiveUpAndDie (g, false)
       |  (true, NONE) => NoMoreJobs (g, ok)
       |  (true, SOME (n,nI : GraphExtra.t nodeInfo)) =>
          let
            val _ = diag ("Found runnable node "^node_toString n)
            val extra = #extra nI
            fun eCompile ds = Compile(ds, extra)
            fun eBuildScript (s,deps) = BuildScript(s,deps,extra)
            fun eBuildArticle (s,deps) = BuildArticle(s,deps,extra)
            fun eProcessArticle s = ProcessArticle(s,extra)
            fun k b g =
              if b orelse keep_going then
                genjob (updnode(n, if b then Succeeded else RealFail) g, true)
              else GiveUpAndDie (g, ok)
            val deps = map #2 (#dependencies nI)
            val dir = Holmake_tools.hmdir.toAbsPath (#dir nI)
            val _ = is_pending (#status nI) orelse
                    raise Fail "runnable not pending"
            val target_s = dep_toString (#target nI)
            fun stdprocess() =
              case #command nI of
                  NoCmd => genjob (updnode (n,Succeeded) g, true)
                | cmd as SomeCmd c =>
                  let
                    val hypargs as {noecho,ignore_error,command=c} =
                        process_hypat_options c
                    val hypargs =
                        {noecho=true,ignore_error=ignore_error,command=c}
                    fun error b =
                      if b then Succeeded
                      else if ignore_error then
                        (warn ("Ignoring error executing: " ^ c);
                         Succeeded)
                      else RealFail
                  in
                    case pushd dir
                               (mosml_build_command hmenv extra hypargs) deps
                     of
                        SOME r =>
                          k (error (OS.Process.isSuccess r) = Succeeded) g
                      | NONE =>
                        let
                          val others = find_nodes_by_command g cmd
                          val _ = diag ("Found nodes " ^
                                        String.concatWith ", "
                                           (map node_toString others) ^
                                        " with duplicate commands")
                          fun updall (g, st) =
                            List.foldl (fn (n, g) => updnode (n, st) g)
                                       g
                                       (n::others)
                          fun update ((g,ok), b) =
                              let
                                val status = error b
                                val g' = updall (g, status)
                                val ok' = status = Succeeded orelse keep_going
                              in
                                (g',ok')
                              end
                        in
                          NewJob ({tag = target_s, command = shell_command c,
                                   update = update, dir = dir},
                                  (updall(g, Running), true))
                        end
                  end
                | BuiltInCmd (bic,incinfo) =>
                  let
                    val _ = diag ("Setting up for target >" ^ target_s ^
                                  "< with bic " ^ bic_toString bic)
                    fun bresk bres g =
                      case bres of
                          BR_OK => k true g
                        | BR_Failed => k false g
                        | BR_ClineK{cline, job_kont, other_nodes} =>
                          let
                            fun b2res b = if b then OS.Process.success
                                          else OS.Process.failure
                            fun updall s g =
                              List.foldl (fn (n,g) => updnode(n,s) g) g
                                         (n::other_nodes)
                            fun update ((g,ok), b) =
                              if job_kont (fn s => ()) (b2res b) then
                                (updall Succeeded g, true)
                              else
                                (updall RealFail g, keep_going)
                            fun cline_str (c,l) = "["^c^"] " ^
                                                  String.concatWith " " l
                          in
                            diag ("New graph job for "^target_s^
                                  " with c/line: " ^ cline_str cline);
                            diag ("Other nodes are: "^
                                  String.concatWith ", "
                                        (map node_toString other_nodes));
                            NewJob({tag = target_s, dir = dir,
                                    command = cline_to_command cline,
                                    update = update},
                                   (updall Running g, true))
                          end
                    fun bc c f = pushd dir (build_command g incinfo c) f
                    val _ = diag ("Handling builtin command " ^
                                  bic_toString bic ^ " for "^target_s)
                  in
                    case bic of
                        BIC_Compile =>
                        (case toFile target_s of
                             UI c => bresk (bc (eCompile deps) (SIG c)) g
                           | UO c => bresk (bc (eCompile deps) (SML c)) g
                           | ART (RawArticle s) =>
                               bresk (bc (eBuildArticle(s,deps))
                                         (SML (Script s)))
                                     g
                           | ART (ProcessedArticle s) =>
                               bresk (bc (eProcessArticle s)
                                         (ART (RawArticle s)))
                                     g
                           | _ => raise Fail ("bg tgt = " ^ target_s))
                      | BIC_BuildScript thyname =>
                          bresk (bc (eBuildScript(thyname, deps))
                                    (SML (Script thyname)))
                                g
                  end
          in
            if not (#phony nI) andalso depexists_readable (#target nI) andalso
               #seqnum nI = 0
               (* necessary to avoid dropping out of a multi-command execution
                  part way through *)
            then
              let
                val _ = diag ("May not need to rebuild "^target_s)
              in
                case List.find
                       (fn (_, d) => depforces_update_of(d,#target nI))
                       (#dependencies nI)
                 of
                    NONE => (diag ("Can skip work on "^target_s);
                             genjob (updnode (n, Succeeded) g, true))
                  | SOME (_,d) =>
                    (diag ("Dependency "^dep_toString d^" forces rebuild of "^
                           target_s);
                     stdprocess())
              end
            else
              stdprocess()
          end
    val worklist =
        new_worklist {worklimit = jobs,
                      provider = { initial = (g,true), genjob = genjob }}
  in
    do_work(worklist, monitor)
  end

end
