structure TCPretype :> TCPretype =
struct
open Exception
fun TCERR f msg = HOL_ERR {origin_structure = "TCPretype",
                           origin_function = f, message = msg}

datatype pretype =
  Vartype of string | Tyop of (string * pretype list) |
  UVar of pretype option ref

fun tyvars t =
  case t of
    Vartype s => [s]
  | Tyop(s, args) =>
      List.foldl (fn (t, set) => Lib.union (tyvars t) set) [] args
  | UVar (ref NONE) => []
  | UVar (ref (SOME t')) => tyvars t'

open optmonad
infix >> >-

fun new_uvar () = UVar(ref NONE)

infix ref_occurs_in
fun r ref_occurs_in value =
  case value of
    Vartype _ => false
  | Tyop (s, ts) => List.exists (fn t => r ref_occurs_in t) ts
  | UVar (r' as ref NONE) => r = r'
  | UVar (r' as ref (SOME t)) => r = r' orelse r ref_occurs_in t
infix ref_equiv
fun r ref_equiv value =
  case value of
    Vartype _ => false
  | Tyop _ => false
  | UVar (r' as ref NONE) => r = r'
  | UVar (r' as ref (SOME t)) => r = r' orelse r ref_equiv t


fun unsafe_bind f r value =
  if r ref_equiv value then
    ok
  else
    if r ref_occurs_in value orelse isSome (!r) then
      fail
    else
      (fn acc => (((r, !r)::acc, SOME ()) before r := SOME value))

fun gen_unify bind t1 t2 = let
  val gen_unify = gen_unify bind
in
  case (t1, t2) of
    (UVar (r as ref NONE), t) => bind gen_unify r t
  | (UVar (r as ref (SOME t1)), t2) => gen_unify t1 t2
  | (t1, t2 as UVar _) => gen_unify t2 t1
  | (Vartype s1, Vartype s2) => if s1 = s2 then ok else fail
  | (Tyop(op1, args1), Tyop(op2, args2)) =>
      if op1 <> op2 orelse length args1 <> length args2 then fail
      else
        mmap (fn (t1, t2) => gen_unify t1 t2) (ListPair.zip(args1, args2)) >>
        return ()
  | _ => fail
end

fun unify t1 t2 =
  case (gen_unify unsafe_bind t1 t2 []) of
    (bindings, SOME ()) => ()
  | (_, NONE) => raise TCERR "unify" "unify failed"

fun can_unify t1 t2 = let
  val (bindings, result) = gen_unify unsafe_bind t1 t2 []
  val _ = app (fn (r, oldvalue) => r := oldvalue) bindings
in
  isSome result
end


local
  fun (r ref_equiv value) env =
    case value of
      UVar (r' as ref NONE) =>
        r = r' orelse let
        in
          case Lib.assoc1 r' env of
            NONE => false
          | SOME (_, v) => (r ref_equiv v) env
        end
    | UVar (ref (SOME t)) => (r ref_equiv t) env
    | _ => false
  fun (r ref_occurs_in value) env =
    case value of
      UVar (r' as ref NONE) =>
        r = r' orelse let
        in
          case Lib.assoc1 r' env of
            NONE => false
          | SOME (_, v) => (r ref_occurs_in v) env
        end
    | UVar (ref (SOME t)) => (r ref_occurs_in t) env
    | Vartype _ => false
    | Tyop(_, args) => List.exists (fn t => (r ref_occurs_in t) env) args
in
  fun safe_bind unify r value env =
    case (Lib.assoc1 r env) of
      NONE =>
        if (r ref_equiv value) env then
          ok env
        else
          if (r ref_occurs_in value) env then
            fail env
          else
            ((r,value)::env, SOME ())
    | SOME (_, v) => unify v value env
end


fun safe_unify t1 t2 = gen_unify safe_bind t1 t2

fun apply_subst subst pty =
  case pty of
    Vartype _ => pty
  | Tyop(s, args) => Tyop(s, map (apply_subst subst) args)
  | UVar (ref (SOME t)) => apply_subst subst t
  | UVar (r as ref NONE) => let
    in
      case (Lib.assoc1 r subst) of
        NONE => UVar r
      | SOME (_, value) => apply_subst subst value
    end

(* passes over a type, turning all of the type variables into fresh
   UVars, but doing so consistently by using an env, which is an alist
   from variable names to type variable refs *)
local
  fun replace s env =
    case Lib.assoc1 s env of
      NONE => let
        val r = ref NONE
      in
        ((s, r)::env, SOME (UVar r))
      end
    | SOME (_, r) => (env, SOME (UVar r))
in
  fun rename_tv ty =
    case ty of
      Vartype s => replace s
    | Tyop(s, args) =>
        mmap rename_tv args >- (fn args' => return (Tyop(s, args')))
    | x => return x
  fun rename_typevars ty = valOf (#2 (rename_tv ty []))
end

fun fromType t =
  if Type.is_vartype t then Vartype (Type.dest_vartype t)
  else let
    val {Tyop = tyop, Args} = Type.dest_type t
  in
    Tyop(tyop, map fromType Args)
  end

  fun remove_made_links ty =
    case ty of
      UVar(ref (SOME ty')) => remove_made_links ty'
    | Tyop(s, args) => Tyop(s, map remove_made_links args)
    | _ => ty
  fun generate_new_name r used_so_far = let
    val result = Lib.gen_variant Lib.tyvar_vary used_so_far "'a"
    val _ = r := SOME (Vartype result)
  in
    (result::used_so_far, SOME ())
  end

  fun replace_null_links ty =
    case ty of
      UVar (r as ref NONE) => generate_new_name r
    | UVar (ref (SOME ty)) => replace_null_links ty
    | Tyop (s, args) => mmap replace_null_links args >> ok
    | Vartype _ => ok

  fun clean ty =
    case ty of
      Vartype s => Type.mk_vartype s
    | Tyop(s, args) => Type.mk_type{Tyop = s, Args = map clean args}
    | _ => raise Fail "Don't expect to see links remaining at this stage"
  fun toType ty = let
    val _ = replace_null_links ty (tyvars ty)
  in
    clean (remove_made_links ty)
  end

fun chase (Tyop("fun", [_, ty])) = ty
  | chase (UVar(ref (SOME ty))) = chase ty
  | chase _ = raise Fail "chase applied to non-function type"

end
