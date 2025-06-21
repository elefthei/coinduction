(** an OCaml plugin to perform reification and apply the lemmas implementing enhanced coinduction.
    see end-user tactics in [tactics.v]
 *)

open Constr
open EConstr
open Proofview

(* raise an error in Coq *)
let error s = Printf.ksprintf (fun s -> CErrors.user_err (Pp.str s)) ("[coinduction] "^^s)

(* access to Coq constants *)
let get_const s =
  lazy (EConstr.of_constr (UnivGen.constr_of_monomorphic_global (Global.env ()) (Rocqlib.lib_ref s)))

(* make an application using a lazy value *)
let force_app f = fun x -> mkApp (Lazy.force f,x)

(* typecheck a term and propagate universe constraints *)
let typecheck t =
  Goal.enter (fun goal ->
      let env = Tacmach.pf_env goal in
      let sigma = Tacmach.project goal in
      let sigma, _ = Typing.solve_evars env sigma t in
      Unsafe.tclEVARS sigma)

(* corresponding application tactics *)
let typecheck_and_apply t = tclTHEN (typecheck t) (Tactics.apply t)
let typecheck_and_eapply t = tclTHEN (typecheck t) (Tactics.eapply t)

(* creating OCaml functions from Coq ones *)
let get_fun_1 s = let v = get_const s in fun x -> force_app v [|x|]
let get_fun_2 s = let v = get_const s in fun x y -> force_app v [|x;y|]
let get_fun_3 s = let v = get_const s in fun x y z -> force_app v [|x;y;z|]
let get_fun_4 s = let v = get_const s in fun x y z t -> force_app v [|x;y;z;t|]
let get_fun_5 s = let v = get_const s in fun x y z t u -> force_app v [|x;y;z;t;u|]

(* Coq constants *)
module Coq = struct
  let eq_refl = get_fun_2 "core.eq.refl"
  let and_    = get_const "core.and.type"
  let pair    = get_fun_4 "core.prod.intro"
end

(* Coinduction constants *)
module Cnd = struct
  let body_       = get_const "coinduction.body"
  let body        = get_fun_4 "coinduction.body"
  let t           = get_fun_3 "coinduction.t"
  let bt          = get_fun_3 "coinduction.bt"
  let gfp         = get_const "coinduction.gfp"
  let sym_from    = get_const "coinduction.Sym_from"
  let ar_prp      = get_const "coinduction.PRP"
  let ar_abs      = get_fun_2 "coinduction.ABS"
  let tuple       = get_fun_1 "coinduction.tuple"
  let hol         = get_const "coinduction.hol"
  let abs         = get_fun_2 "coinduction.abs"
  let cnj         = get_fun_2 "coinduction.cnj"
  let fT          = get_fun_2 "coinduction.fT"
  let pT_         = get_const "coinduction.pT"
  let pT          = get_fun_4 "coinduction.pT"
  let tnil        = get_fun_1 "coinduction.tnil"
  let tcons       = get_fun_4 "coinduction.tcons"
  let coinduction = get_fun_4 "coinduction.coinduction"
  let accumulate  = get_fun_5 "coinduction.accumulate"
  let by_symmetry = get_fun_4 "coinduction.by_symmetry"
end


(* finding the bisimulation candidate of an ongoing coinductive proof.
   it must be of the shape [t ?b ?R], where [t] is the companion
   it is hidden under a few quantifications/implications and conjunctions, e.g.,
   [forall x y, P x y -> t b R u v /\ forall z, t b R p q]
   using [Generalize.generalize] is an ugly hack in order to give the value [t b R] back to Ltac
   TODO: better solution?
 *)
let find_candidate goal =
  let sigma = Tacmach.project goal in
  let rec parse e =
    match kind sigma e with
    | Prod(_,_,q) -> parse q
    | App(c,[|p;_|]) when c=Lazy.force Coq.and_ -> parse p
    | App(c,a) when c=Lazy.force Cnd.body_ -> mkApp(c,Array.sub a 0 4) (* body X L (t b) r ... *)
    | _ -> error "did not recognise an ongoing proof by enhanced coinduction"
  in
  let tbr = parse (Tacmach.pf_concl goal) in
  let _,ttbr = Tacmach.pf_type_of goal tbr in
  Generalize.generalize [Coq.eq_refl ttbr tbr]

(* applying one of the [reification.coinduction/accumulate/by_symmetry] lemmas
   and changing the obtained goal back into a user-friendly looking goal.
   Depending on the lemma we want to apply
   [mode] is either
   - `Coinduction
   - `Accumulate(n,rname)
   - `By_symmetry
   In the second case, [n] is the number of hypotheses to exploit (represented as a Coq constr of type [nat]),
   and [rname] is the identifier of the current bisimulation candidate.
 *)

let apply mode goal =
  let env = Tacmach.pf_env goal in
  let sigma = Tacmach.project goal in

  (* when [t] is [A -> B -> Prop], returns [ABS A (ABS B PRP)] *)
  let rec get_arity t =
    match kind sigma t with
    | Sort _ -> Lazy.force Cnd.ar_prp
    | Prod(i,a,q) -> Cnd.ar_abs a (mkLambda(i,a,get_arity q))
    | _ -> error "coinductive object must be a n-ary relation"
  in
  let tuple a xs = mkApp (Cnd.tuple a, Array.of_list xs) in
  let swap v xs =
    if v then Array.of_list xs
    else match xs with [x;y] -> [|y;x|]
         | _ -> failwith "by_symmetry: not a binary relation (please report)"
  in

  (* key function: parsing/reifying a type [e] of the shape

     [forall x y, P x y -> ?REL u v /\ forall z, ?REL p q]

     where x,y may appear in P, u, v, p, q and z may appear in p q
     and where REL is constrained by the current mode:
     - should be [gfp b] for some [b] with `Coinduction
     - should be [t b R] for some [b,R] with `Accumulate
     - should be [bt b R] for some [b,R] with `By_symmetry

     such a type [e] is interpreted as a bisimulation candidate

     returns a tuple [(a,s,l,b),r,c,x,q)] where
     - [a] is the arity of the considered relations
     - [s] is the type of [r]
     - [l] is the associated complete lattice
     - [b] is the (monotone) function of the coinductive game
     - [r] is a relation of arity [a], the aforementioned [REL]
     - [c] has type [reification.T] and is the skeleton of the bisimulation candidate
     - [x] has type [reification.fT a c] and are the elements related by the bisimulation candidate
     - [q] is a function making it possible to reconstruct a nice type for the goal resulting from the application of the considered lemma.

     the key invariant is that [e] should be convertible to [pT a c r x]

     in the above example,
     - [c] is [abs (fun x => abs (fun y => abs (fun _: P x y => cnj hol (abs (fun z => hol)))))]
     - [x] is [fun x y H => ((u,(v,tt)), fun z => (p,(q,tt)))]

     the OCaml type of [g] is a bit complicated: [bool -> int -> (int -> constr) -> constr]
     intuitively, [g true i REL'] should be [e] where [REL] has beend replaced by [REL']
     the integers are there to deal with de Bruijn indices:
     - in the `Coinduction case, [REL'] will involved a [mkRel] whose index depends on the depth at wich it gets replaced; [i] is used to record the current depth
     - in the other cases, [REL'] will constructed from the context so that integers will just be ignored
     the Boolean is only used for the `By_symmetry mode: setting it to false makes it possible to reverse all pairs in the candidate
   *)
  let rec parse e =
    match kind sigma e with
    | Prod(i,w,q) ->            (* both universal quantification and implication *)
       let (aslb,r,c,x,g) = parse q in
       (aslb,
        r,
        Cnd.abs w (mkLambda(i,w,c)),
        mkLambda(i,w,x),
        (fun v l r -> mkProd(i,w,g v (l+1) r)))
    | App(c,[|p1;p2|])          (* conjunction *)
         when c=Lazy.force Coq.and_ ->
       let (aslb,r, c1,x1,g1) = parse p1 in
       let (_,   r',c2,x2,g2) = parse p2 in
       let (a,_,_,_) = aslb in
       if not (Reductionops.is_conv env sigma r r') then
         error "only one coinductive predicate is allowed";
       (aslb,
        r,
        Cnd.cnj c1 c2,
        Coq.pair (Cnd.fT a c1) (Cnd.fT a c2) x1 x2,
       (fun v l r -> mkApp(c,[|g1 v l r;g2 v l r|])))
    | App(c,slb_)      (* gfp s l b ... *)
         when mode=`Coinduction &&
                c=Lazy.force Cnd.gfp ->
       (match Array.to_list slb_ with
        | s::l::b::xs ->
           let a = get_arity s in
           ((a,s,l,b),
            mkApp(c,[|s;l;b|]),
            Lazy.force Cnd.hol,tuple a xs,
            (fun v l r -> mkApp(r l,swap v xs)))
        | _ -> assert false
       )
    | App(c,sltbr_)    (* body s l (t _ _ b) r x y *)
         when mode<>`Coinduction && mode <>`By_symmetry &&
                c=Lazy.force Cnd.body_ ->
       (match Array.to_list sltbr_ with
        | s::l::tb::r::xs ->
           (match kind sigma tb with
            | App(_,[|_;_;b|]) ->
               let a = get_arity s in
               ((a,s,l,b),
                mkApp(c,[|s;l;tb;r|]),
                Lazy.force Cnd.hol,tuple a xs,
                (fun v l r -> mkApp(r l,swap v xs)))
            | _ -> error "unrecognised situation")
        | _ -> assert false
       )
    | App(c,args)    (* body s l (bt _ _ b) r x y *)
         when mode =`By_symmetry &&
                c=Lazy.force Cnd.body_ ->
       (match args with
          [|s;l;btb;r;x;y|] ->
           (match kind sigma btb with
            | App(_,[|_;_;b|]) ->
               let a = get_arity s in
               ((a,s,l,b),
                mkApp(c,[|s;l;btb;r|]),
                Lazy.force Cnd.hol,tuple a [x;y],
                (fun v l r -> mkApp(r l,swap v [x;y])))
            | _ -> error "unrecognised situation")
        | _ -> error "binary relation expected for reasonning by symmetry")
    | _ -> error "unrecognised situation"
  in

  (* extension of the above function for `Accumulate(n,rname):
     parsing/reifying a type [e] of the shape

     P1 -> ... -> Pn -> P

     where P and the Pi's are all of the shape described above for [parse]

     returns a tuple [(a,b,r,cs,c,x,g)] where
     - [a] is the arity of the considered relations
     - [b] is the (monotone) function of the coinductive game
     - [r] is a relation of arity [a], always of the form [t b ?R]
     - [cs] has type [reification.Ts a] and contains the reified form of P1...Pn
     - [c,x] is the reified form of P, as above in [parse]
     - [g] is a nice type for the goal resulting from the application of the accumulation lemma, i.e.,
       P1 -> ... -> Pn -> P -> P'
       where P' is obtained from P by replacing [r] with [b r]

     the key invariant is that the starting type [e]
     should be convertible to [pTs a cs r (pT a c r x)]
   *)
  let rec parse_acc n rname e =
    match kind sigma n with
    | App(_,[|n|]) ->
       begin                    (* S n *)
         match kind sigma e with
         | Prod(i,l,q) ->
            let (_,r,d,u,l') = parse l in
            let (a,b,r',cs,c,x,g) = parse_acc n rname q in
            if not (Reductionops.is_conv env sigma r r') then
              error "only one coinductive relation is allowed";
            (a,b,r,Cnd.tcons a d u cs, c, x, mkProd(i,l' true 0 (fun _ -> r),g))
         | _ -> error "anomaly, mismatch in hypotheses number"
       end
    | _ ->                      (* 0 *)
       let ((a,s,l,b),r,c,x,e') = parse e in
       (a,b,r,Cnd.tnil a, c, x,
        mkArrowR
          (e' true 0 (fun _ -> r))
          (e' true 0 (fun _ -> Cnd.body s l (Cnd.bt s l b) (mkVar rname))))
  in

  (* main entry point *)
  match mode with
  | `Accumulate (i,rname) ->
     let (a,b,_,cs,c,x,g) = parse_acc i rname (Tacmach.pf_concl goal) in
     (* here we first revert R and re-introduce it afterwards in order to keep the same name for the candidate.
        we do so in OCaml rather than in Ltac: this makes it possible to avoid the mess with de Bruijn indices *)
     tclTHEN (Generalize.revert [rname])
       (tclTHEN (typecheck_and_apply (Cnd.accumulate a b cs c x))
          (tclTHEN (Tactics.introduction rname)
             (Tactics.convert_concl ~cast:false ~check:true g DEFAULTcast)
       ))

  | `Coinduction ->
     let ((a,s,l,b),_,c,x,g) = parse (Tacmach.pf_concl goal) in
     (* we cannot use the same trick as above since the candidate [R] does not exist beforehand
        thus we create our own binder (whose name "R" will be overwritten by the subsequent intro in Ltac), and deal with de Bruijn indices explicitly
      *)
     let tr  j = Cnd.body s l (Cnd.t  s l b) (mkRel (1+j)) in
     let btr j = Cnd.body s l (Cnd.bt s l b) (mkRel (2+j)) in
     let p' = mkProd (EConstr.nameR (Names.Id.of_string "R"), s, (mkArrowR (g true 0 tr) (g true 0 btr)))  in
     tclTHEN (typecheck_and_apply (Cnd.coinduction a c b x))
       (Tactics.convert_concl ~cast:false ~check:true p' DEFAULTcast)

  | `By_symmetry ->
     let ((a,s,_,b),r,c,x,g) = parse (Tacmach.pf_concl goal) in
     (* several catches here...

        1. We would like to do just
        [Tactics.apply (by_symmetry a c x b)]
        unfortunately, this does not seem to trigger typeclass resolution for instantiating the next two arguments of [by_symmetry] (the function s, and a proof of [Sym_from converse b s])
        Thus we use [eapply] instead, and we perform an explicit call to typeclass resolution for the first generated subgoal.

        2. The unification problem seems to be more difficult here, and [eapply] fails unless we convert the goal first into its reified form.
        Using [refine (by_symmetry a c x b _ _ _ _)] works in Ltac, but it's painful to provide a term with holes in OCaml - at least I don't know how to do it nicely.
        Whence the first two steps.

        3. after eapplying [by_symmetry], we get three subgoals and we want to
        - run typeclass resolution on the first one
        - do a change with nice types on the second and third ones
        I don't know how to get access to those three goals separately (e.g., the tclTHENLAST tacticial has a different type than the tclTHEN I'm using here...), so that I take look at the resulting goals to recognise who is who.
      *)
     let p = Cnd.pT a c r x in
     let a' =
       match kind sigma a with
       | App(_,[|a';_|]) -> a'
       | _ -> assert false
     in
     (* Feedback.msg_warning (Printer.pr_leconstr_env env sigma (Cnd.by_symmetry a c x b)); *)
     tclTHEN (Tactics.convert_concl ~cast:false ~check:true p DEFAULTcast)
       (tclTHEN (typecheck_and_eapply (Cnd.by_symmetry a' c x b))
       (Goal.enter (fun goal ->
            let sigma = Tacmach.project goal in
            match kind sigma (Tacmach.pf_concl goal) with
            (* first subgoal (typeclass resolution)*)
            | App(c,_) when c=Lazy.force Cnd.sym_from ->
               Class_tactics.typeclasses_eauto [Class_tactics.typeclasses_db] ~depth:(Some 5)
            (* third subgoal (main goal) is of the shape [pT a r' c x] *)
            | App(c,[|_;_;r';_|]) when c=Lazy.force Cnd.pT_ ->
               (* here we need to look at the goal anyways, in order to discover the relation [r'] built from the function found by typeclass resolution, and use it to give a nice type *)
               let p' = (g true 0 (fun _ -> r'))  in
               Tactics.convert_concl ~cast:false ~check:true p' DEFAULTcast
            (* second subgoal (symmetry argument) *)
            | _ ->
               let p' =
                 mkProd (EConstr.nameR (Names.Id.of_string "R"), s,
                         mkArrowR (g true 1 mkRel) (g false 2 mkRel))
               in
               (* Feedback.msg_warning (Printer.pr_leconstr_env env sigma p'); *)
               Tactics.convert_concl ~cast:false ~check:true p' DEFAULTcast
       )))
