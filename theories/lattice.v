(** * Basic theory of complete lattices  *)

Require Export Setoid Morphisms.
Set Implicit Arguments.

(** * Class of complete lattices 
    we require all operations rather than deriving them from least upper bounds: 
    this way we can map them to the natural operations in the various instances *)

Class CompleteLattice (X: Type) := {
  weq: relation X;
  leq: relation X;
  sup: forall I, (I -> Prop) -> (I -> X) -> X;
  inf: forall I, (I -> Prop) -> (I -> X) -> X;
  cup: X -> X -> X;
  cap: X -> X -> X;
  bot: X;
  top: X;
  CL_props:
  (* PreOrder_leq:> *) PreOrder leq /\
  (* weq_spec: *) (forall x y, weq x y <-> (leq x y /\ leq y x)) /\
  (* sup_spec: *) (forall I P f z, leq (@sup I P f) z <-> forall i, P i -> leq (f i) z) /\
  (* inf_spec: *) (forall I P f z, leq z (@inf I P f) <-> forall i, P i -> leq z (f i)) /\
  (* cup_spec: *) (forall x y z, leq (cup x y) z <-> (leq x z /\ leq y z)) /\
  (* cap_spec: *) (forall x y z, leq z (cap x y) <-> (leq z x /\ leq z y)) /\
  (* leq_bx: *) (forall x, leq bot x) /\
  (* leq_xt: *) (forall x, leq x top)
}.

Declare Scope lattice.
Open Scope lattice.
Infix "==" := weq (at level 70): lattice.
Infix "<=" := leq: lattice.
Notation sup_all f := (sup (fun _ => True) f).
Notation inf_all f := (inf (fun _ => True) f).

Section s.
 Context `{L: CompleteLattice}.
 #[export] Instance PreOrder_leq: PreOrder leq.
 Proof. apply CL_props. Qed.
 Lemma weq_spec: forall x y, x == y <-> (x <= y /\ y <= x).
 Proof. apply CL_props. Qed.
 Lemma sup_spec: forall I P f z, @sup X L I P f <= z <-> forall i, P i -> f i <= z.
 Proof. apply CL_props. Qed.
 Lemma inf_spec: forall I P f z, z <= @inf X L I P f <-> forall i, P i -> z <= f i.
 Proof. apply CL_props. Qed.
 Lemma cup_spec: forall x y z, cup x y <= z <-> (x <= z /\ y <= z).
 Proof. apply CL_props. Qed.
 Lemma cap_spec: forall x y z, z <= cap x y <-> (z <= x /\ z <= y).
 Proof. apply CL_props. Qed.
 Lemma leq_bx: forall x, bot <= x.
 Proof. apply CL_props. Qed.
 Lemma leq_xt: forall x, x <= top.
 Proof. apply CL_props. Qed.
End s.
Global Hint Extern 0 => reflexivity: core.
Global Hint Resolve leq_bx leq_xt: core.
 

(** * Concrete instances *)

(** Prop is a complete lattice *)
#[export] Program Instance CompleteLattice_Prop: CompleteLattice Prop :=
  {| weq:=iff;
     leq:=Basics.impl;
     sup I P f:=exists2 i, P i & f i;
     inf I P f:=forall i, P i -> f i;
     cup:=or;
     cap:=and;
     bot:=False;
     top:=True |}.
Next Obligation. split; firstorder. Qed.

(** Dependent functions into complete lattices *)
Definition dpointwise_relation A (X: A -> Type) (R: forall {a}, relation (X a)): relation (forall a, X a)
  := fun f g => forall a, R (f a) (g a). 
Arguments dpointwise_relation [_] {_} _ /.

Ltac CL_split := split; [intros; simpl; auto | try (CL_split || auto)].
#[export] Program Instance CompleteLattice_dfun A (X: A -> Type) (O: forall a, CompleteLattice (X a)): CompleteLattice (forall a, X a) :=
  {| weq := dpointwise_relation (fun _ => weq);
     leq := dpointwise_relation (fun _ => leq);
     sup I P f a := sup P (fun i => f i a);
     inf I P f a := inf P (fun i => f i a);
     cup f g a := cup (f a) (g a);
     cap f g a := cap (f a) (g a);
     bot a := bot;
     top a := top
  |}.
Next Obligation.
  CL_split. split.
  now intros f x. 
  intros f g h H H' x. now transitivity (g x).
  setoid_rewrite weq_spec. now firstorder. 
  setoid_rewrite sup_spec. now firstorder. 
  setoid_rewrite inf_spec. now firstorder. 
  setoid_rewrite cup_spec. now firstorder. 
  setoid_rewrite cap_spec. now firstorder. 
Qed.
(*
Definition a1: CompleteLattice (nat -> Prop) := _. 
Definition a2: CompleteLattice (nat -> nat -> Prop) := _. 
Definition a3: CompleteLattice (forall n: nat, n = n -> Prop) := _.
*)
(* (** Functions into a complete lattice *) *)
(* #[export] Instance CompleteLattice_fun {A X} {L: CompleteLattice X}: CompleteLattice (A -> X) := *)
(*   CompleteLattice_dfun (fun _ => X) (fun _ => L).  *)

(** Dual lattice *)
Program Definition Dual {X} {L: CompleteLattice X}: CompleteLattice X :=
  {| weq:=weq;
     leq x y :=leq y x;
     sup:=inf;
     inf:=sup;
     cup:=cap;
     cap:=cup;
     bot:=top;
     top:=bot
  |}.
Next Obligation.
  CL_split. split. 
  now intro.
  intros ? x ???. now transitivity x.
  rewrite weq_spec. tauto. 
  now apply inf_spec.
  now apply sup_spec.
  now apply cap_spec.
  now apply cup_spec.
Qed.

  (** * Utilities  *)

(** tactics to solve goals by duality *)
Ltac dual t := apply (t _ Dual).


(** any monotone function preserves equality  *)
Lemma op_leq_weq_1 {X Y} {LX: CompleteLattice X} {LY: CompleteLattice Y} {f: X -> Y} 
  {Hf: Proper (leq ==> leq) f}: Proper (weq ==> weq) f.
Proof. intros x y. rewrite 2weq_spec. intro E; split; apply Hf; apply E. Qed.

Lemma op_leq_weq_2 {X Y Z} {LX: CompleteLattice X} {LY: CompleteLattice Y} {LZ: CompleteLattice Z} {f: X -> Y -> Z}
  {Hf: Proper (leq ==> leq ==> leq) f}: Proper (weq ==> weq ==> weq) f.
Proof. 
  intros x y E x' y' E'. rewrite weq_spec in E. rewrite weq_spec in E'.
  apply weq_spec. split; apply Hf; (apply E || apply E').
Qed.

(** * General properties of complete lattices *)

Section sup.
 Context {X} {L: CompleteLattice X}.

 (** Partial order *)
 Global Instance Equivalence_weq: Equivalence weq.
 Proof.
   constructor.
    intro x. now apply weq_spec.
    intros x y. rewrite 2weq_spec. tauto.
    intros x y z. rewrite 3weq_spec. split; transitivity y; tauto. 
  Qed.
 Global Instance PartialOrder_weq_leq: PartialOrder weq leq.
 Proof.
   intros x y. simpl. now rewrite weq_spec.
 Qed.
 Lemma antisym x y: x <= y -> y <= x -> x == y.
 Proof. rewrite weq_spec. tauto. Qed.

 Lemma antisym' x y: x <= y -> (x <= y -> y <= x) -> x == y.
 Proof. intros. apply antisym; tauto. Qed.
 
 Lemma from_above x y: (forall z, x<=z <-> y<=z) -> x==y.
 Proof. intro E. apply antisym; apply E; reflexivity. Qed.

 Lemma from_below x y: (forall z, z<=x <-> z<=y) -> x==y.
 Proof. intro E. apply antisym; apply E; reflexivity. Qed.

 
 (** Least upper bounds *)
 Global Instance sup_leq I:
   Proper (leq ==> leq ==> leq) (@sup X L I).
 Proof.
   intros P P' HP f f' Hf. apply sup_spec.
   intro i. rewrite (HP i), (Hf i). 
   now apply sup_spec.
 Qed.
 Global Instance sup_weq I: Proper (weq ==> weq ==> weq) (@sup X L I) := op_leq_weq_2.
 
 Lemma leq_xsup I (P: I -> Prop) (f: I -> X) i: P i -> f i <= sup P f.
 Proof. now apply sup_spec. Qed.
 Lemma leq_xsup_id (P: X -> Prop) x: P x -> x <= sup P id.
 Proof. apply (leq_xsup P id). Qed.
 Lemma leq_xsup_all I (f: I -> X) i: f i <= sup_all f.
 Proof. now apply leq_xsup. Qed.

 Lemma eleq_xsup I (P: I -> Prop) (f: I -> X) i x: P i -> x <= f i -> x <= sup P f.
 Proof. intros ? H. rewrite H. now apply leq_xsup. Qed.
 Lemma eleq_xsup_id (P: X -> Prop) y x: P y -> x <= y -> x <= sup P id.
 Proof. apply (eleq_xsup P id). Qed.
 Lemma eleq_xsup_all I (f: I -> X) i x: x <= f i -> x <= sup_all f.
 Proof. now apply eleq_xsup. Qed.

 Lemma sup_id_spec P z: sup P id <= z <-> forall y, P y -> y <= z.
 Proof. now rewrite sup_spec. Qed.
 Lemma sup_all_spec I (f: I -> X) z: sup_all f <= z <-> forall i, f i <= z.
 Proof. rewrite sup_spec. firstorder. Qed.

 
 (** Binary join *)
 Lemma leq_xcup x y z: z <= x \/ z <= y -> z <= cup x y.
 Proof.
   destruct (cup_spec x y (cup x y)) as [H _].
   now intros [E|E]; rewrite E; apply H.
 Qed.
 Lemma cup_l x y: x <= cup x y.
 Proof. auto using leq_xcup. Qed.
 Lemma cup_r x y: y <= cup x y.
 Proof. auto using leq_xcup. Qed.

 Lemma cupA x y z: cup x (cup y z) == cup (cup x y) z.
 Proof. apply from_above. intro. rewrite 4cup_spec. tauto. Qed.
 Lemma cupC x y: cup x y == cup y x.
 Proof. apply from_above. intro. rewrite 2cup_spec. tauto. Qed.
 Lemma cupI x: cup x x == x.
 Proof. apply from_above. intro. rewrite cup_spec. tauto. Qed.
 Lemma cupbx x: cup bot x == x.
 Proof. apply antisym. apply cup_spec. now split. apply cup_r. Qed.
 Lemma cupxb x: cup x bot == x.
 Proof. rewrite cupC. apply cupbx. Qed.
 Lemma cuptx x: cup top x == top.
 Proof. apply antisym. apply leq_xt. apply cup_l. Qed.
 Lemma cupxt x: cup x top == top.
 Proof. rewrite cupC. apply cuptx. Qed.
 
 Global Instance cup_leq: Proper (leq ==> leq ==> leq) cup.
 Proof.
   intros x x' Hx y y' Hy.
   apply cup_spec. rewrite Hx, Hy.
   now apply cup_spec.
 Qed.
 Global Instance cup_weq: Proper (weq ==> weq ==> weq) cup := op_leq_weq_2.

End sup.
Global Hint Resolve cup_l cup_r: core.


(** * Properties obtained by duality *)
Section inf.
 Context {X} {L: CompleteLattice X}.

 (** Greatest lower bounds *)
 Global Instance inf_leq I:
   Proper (leq --> leq ==> leq) (@inf X L I).
 Proof. intros ??????. now dual @sup_leq. Qed.
 Global Instance inf_weq I: Proper (weq ==> weq ==> weq) (@inf X L I).
 Proof. apply (@sup_weq _ (@Dual _ L)). Qed.
 
 Lemma leq_infx I (P: I -> Prop) (f: I -> X) i: P i -> inf P f <= f i.
 Proof. dual @leq_xsup. Qed.
 Lemma leq_infx_id (P: X -> Prop) x: P x -> inf P id <= x.
 Proof. dual @leq_xsup_id. Qed.
 Lemma leq_infx_all I (f: I -> X) i: inf_all f <= f i.
 Proof. dual @leq_xsup_all. Qed.
 Lemma eleq_infx I (P: I -> Prop) (f: I -> X) i x: P i -> f i <= x -> inf P f <= x.
 Proof. dual @eleq_xsup. Qed.
 Lemma eleq_infx_id (P: X -> Prop) y x: P y -> y <= x -> inf P id <= x.
 Proof. dual @eleq_xsup_id. Qed.
 Lemma eleq_infx_all I (f: I -> X) i x: f i <= x -> inf_all f <= x.
 Proof. dual @eleq_xsup_all. Qed.
 Lemma inf_id_spec P z: z <= inf P id <-> forall y, P y -> z <= y.
 Proof. dual @sup_id_spec. Qed.
 Lemma inf_all_spec I (f: I -> X) z: z <= inf_all f <-> forall i, z <= f i.
 Proof. dual @sup_all_spec. Qed.

 (** Binary meet *)
 Lemma leq_capx x y z: x <= z \/ y <= z -> cap x y <= z.
 Proof. dual @leq_xcup. Qed.
 Lemma cap_l x y: cap x y <= x.
 Proof. dual @cup_l. Qed.
 Lemma cap_r x y: cap x y <= y.
 Proof. dual @cup_r. Qed.
 
 Lemma capA x y z: cap x (cap y z) == cap (cap x y) z.
 Proof. dual @cupA. Qed.
 Lemma capC x y: cap x y == cap y x.
 Proof. dual @cupC. Qed.
 Lemma capI x: cap x x == x.
 Proof. dual @cupI. Qed.
 Lemma captx x: cap top x == x.
 Proof. dual @cupbx. Qed.
 Lemma capxt x: cap x top == x.
 Proof. dual @cupxb. Qed.
 Lemma capbx x: cap bot x == bot.
 Proof. dual @cuptx. Qed.
 Lemma capxb x: cap x bot == bot.
 Proof. dual @cupxt. Qed.

 Global Instance cap_leq: Proper (leq ==> leq ==> leq) cap.
 Proof. intros ??????. now dual @cup_leq. Qed.
 Global Instance cap_weq: Proper (weq ==> weq ==> weq) cap := op_leq_weq_2.

End inf.
Global Hint Resolve cap_l cap_r: core.

(** * The complete lattice of monotone endofunctions *)

Section mon. 
 Context {X} {L: CompleteLattice X}.
 
 (** monotone endofunctions *)
 Record mon := { body:> X -> X; Hbody: Proper (leq ==> leq) body }.
 
 (** the following instances are not global: more powerful ones are 
    given at the end of the section *)
 Existing Instance Hbody.
 Instance Hbody' (f: mon): Proper (weq ==> weq) f.
 Proof. intros x y. rewrite 2weq_spec. now split; apply f. Qed.

 (** constant function *)
 Program Definition const x: mon := {| body y := x |}.
 Next Obligation. intros ? ? ?. reflexivity. Qed.

 (** identity and composition
     the monotonicity proofs are transparent to get strong equalities
     - [id ° f = f ° id = f], and
     - [f ° (g ° h) = (f ° g) ° h]
  *)
 Definition id: mon := {| 
   body x := x; 
   Hbody x y H := H 
 |}.

 Definition comp (f g: mon): mon := {|
   body := fun x => f (g x); 
   Hbody x y H := Hbody f _ _ (Hbody g _ _ H) 
 |}.
 Infix "°" := comp (at level 20): lattice.
 
 (** monotone endofunctions form a new complete lattice *)
 #[export] Program Instance CompleteLattice_mon: CompleteLattice mon := {|
   weq := pointwise_relation X weq;
   leq := pointwise_relation X leq;
   sup I P f := {| body := fun x => sup P (fun i => f i x) |};
   inf I P f := {| body := fun x => inf P (fun i => f i x) |};
   cup f g := {| body := fun x => cup (f x) (g x) |};
   cap f g := {| body := fun x => cap (f x) (g x) |};
   bot := const bot;
   top := const top
 |}.
 Next Obligation.   
   intros x y H. apply sup_spec. intros i Hi.
   rewrite H. eapply eleq_xsup; eauto.
 Qed.
 Next Obligation.
   intros x y H. apply inf_spec. intros i Hi.
   rewrite <-H. eapply eleq_infx; eauto.
 Qed.
 Next Obligation. intros x y H. now rewrite H. Qed.
 Next Obligation. intros x y H. now rewrite H. Qed.
 Next Obligation.
   unfold pointwise_relation. CL_split. split.
   now intros f x. intros f g h H H' x. now transitivity (g x).   
   setoid_rewrite weq_spec. now firstorder.
   setoid_rewrite sup_spec. now firstorder.
   setoid_rewrite inf_spec. now firstorder.
   setoid_rewrite cup_spec. now firstorder.
   setoid_rewrite cap_spec. now firstorder.
 Qed.

 Global Instance comp_leq: Proper (leq ==> leq ==> leq) comp.
 Proof. intros f f' Hf g g' Hg x. simpl. rewrite (Hg x). apply Hf. Qed.
 Global Instance comp_weq: Proper (weq ==> weq ==> weq) comp := op_leq_weq_2.

 Lemma compA f g h: f ° (g ° h) = (f ° g) ° h.
 Proof. reflexivity. Qed.
 Lemma compIx f: id ° f = f.
 Proof. now case f. Qed. 
 Lemma compxI f: f ° id = f.
 Proof. now case f. Qed. 

 (** operations on [mon X] behave as expected on the left of compositions *)
 Lemma msup_o I f P h: sup P f ° h == sup P (fun i: I => (f i) ° h).
 Proof. now intro. Qed.
 Lemma mcup_o f g h: (cup f g) ° h == cup (f ° h) (g ° h).
 Proof. now intro. Qed.
 Lemma mbot_o f: bot ° f == bot.
 Proof. now intro. Qed.
 Lemma minf_o I f P h: inf P f ° h == inf P (fun i: I => (f i) ° h).
 Proof. now intro. Qed.
 Lemma mcap_o f g h: (cap f g) ° h == cap (f ° h) (g ° h).
 Proof. now intro. Qed. 
 Lemma mtop_o f: top ° f == top.
 Proof. now intro. Qed.

 (** instead, only one inclusion holds in general when they are on the left *)
 Lemma o_msup I f P h: sup P (fun i: I => h ° (f i)) <= h ° sup P f.
 Proof. intro. apply sup_spec. intros. apply h. eapply eleq_xsup; eauto. Qed.
 Lemma o_mcup f g h: cup (h ° f) (h ° g) <= h ° (cup f g).
 Proof. intro. apply cup_spec. split; apply h; now simpl. Qed.
 Lemma o_minf I f P h: h ° inf P f <= inf P (fun i: I => h ° (f i)).
 Proof. intro. apply inf_spec. intros. apply h. eapply eleq_infx; eauto. Qed.
 Lemma o_mcap f g h: h ° (cap f g) <= cap (h ° f) (h ° g).
 Proof. intro. apply cap_spec. split; apply h; now simpl. Qed.

End mon.
Arguments mon X {L}.
Infix "°" := comp (at level 20): lattice.
Global Opaque cup bot cap top.  (* TODO: check that we still need this *)

(** application as a function [X->X]->X->X is monotone in its two arguments *)
#[export] Instance app_leq {X} {L: CompleteLattice X}: Proper (leq ==> leq ==> leq) body.
Proof. intros f g fg x y xy. transitivity (f y). now apply f. now apply fg. Qed.
#[export] Instance app_weq {X} {L: CompleteLattice X}: Proper (weq ==> weq ==> weq) body := op_leq_weq_2.
