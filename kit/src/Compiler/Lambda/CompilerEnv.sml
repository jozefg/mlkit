
functor CompilerEnv(structure Ident: IDENT
		    structure TyCon : TYCON
		    structure TyName : TYNAME
		    structure StrId : STRID
		      sharing type Ident.strid = StrId.strid = TyCon.strid
		    structure Con: CON
		    structure Excon: EXCON
		    structure Environments : ENVIRONMENTS
		      sharing type Environments.strid = StrId.strid
			  and type Environments.id = Ident.id
			  and type Environments.longid = Ident.longid
			  and type Environments.tycon = TyCon.tycon
			  and type Environments.longtycon = TyCon.longtycon
			  and type Environments.longstrid = StrId.longstrid
		    structure LambdaExp : LAMBDA_EXP
		      sharing type LambdaExp.TyName = TyName.TyName
		    structure LambdaBasics : LAMBDA_BASICS
		      sharing type LambdaBasics.Type = LambdaExp.Type
                          and type LambdaBasics.tyvar = LambdaExp.tyvar
		    structure Lvars: LVARS
		    structure FinMap: FINMAP
		    structure FinMapEq : FINMAPEQ
		    structure PP: PRETTYPRINT
		      sharing type FinMap.StringTree = PP.StringTree
		          and type LambdaExp.StringTree = PP.StringTree 
			           = FinMapEq.StringTree = TyName.StringTree = Environments.StringTree
	            structure Flags : FLAGS
		    structure Crash: CRASH
		   ): COMPILER_ENV =
  struct

    open Edlib

    fun die s = Crash.impossible ("CompilerEnv."^s)

    type con = Con.con
    type excon = Excon.excon
    type Type = LambdaExp.Type
    type tyvar = LambdaExp.tyvar
    type lvar = Lvars.lvar
    type id = Ident.id
    type longid = Ident.longid
    type strid = StrId.strid
    type longstrid = StrId.longstrid
    type tycon = TyCon.tycon
    type longtycon = TyCon.longtycon
    type TyName = LambdaExp.TyName

    type instance_transformer = int list

    type subst = LambdaBasics.subst
    val mk_subst = LambdaBasics.mk_subst
    fun on_il(S, il) = map (LambdaBasics.on_Type S) il

    (* layout functions *)
    fun layout_scheme(tvs,tau) =
      PP.NODE{start="",finish="",indent=0,childsep=PP.NOSEP,
	      children=[layout_abs tvs,LambdaExp.layoutType tau]}
    and layout_abs tvs = PP.NODE{start="all(",finish=").",indent=0, childsep=PP.RIGHT ",", 
				 children=map (PP.LEAF o LambdaExp.pr_tyvar)tvs}
    fun pr_st st = 
      (PP.outputTree (print, st, !Flags.colwidth);
       print "\n")


    datatype result = LVAR of lvar * tyvar list * Type * Type list
                    | CON of con * tyvar list * Type * Type list * instance_transformer
                    | REF       (* ref is *not* a constructor in the backend, but a primitive! *)
                    | EXCON of excon * Type
                    | ABS | NEG | PLUS | MINUS | MUL | DIV | MOD | LESS 
		    | GREATER | LESSEQ | GREATEREQ
		                (* ABS .. GREATEREQ are place-holders for 
				   the built-in overloaded operators 
				   The compiler must turn these into the
				   corresponding PRIM_APP(n, ...) in
				   the lambda language *)
                    | RESET_REGIONS | FORCE_RESET_REGIONS
                    | PRIM	(* `PRIM' is a place-holder for the built-in
				   prim function: int * 'a -> 'b. The compiler
				   must turn this, plus its constant argument,
				   into a PRIM_APP(n, ...) in the lambda
				   language. *)

    datatype CEnv = CENV of {StrEnv:StrEnv, VarEnv:VarEnv, TyEnv:TyEnv}
    and StrEnv    = STRENV of (strid,CEnv) FinMap.map
    and VarEnv    = VARENV of (id,result) FinMap.map
    and TyEnv     = TYENV of (tycon,TyName list * CEnv) FinMap.map

    val emptyStrEnv    = STRENV FinMap.empty
    and emptyVarEnv    = VARENV FinMap.empty
    and emptyTyEnv     = TYENV FinMap.empty
    val emptyCEnv      = CENV {StrEnv=emptyStrEnv, VarEnv=emptyVarEnv, TyEnv=emptyTyEnv}

    fun initMap a = List.foldL (fn (v,r) => fn m => FinMap.add(v,r,m)) FinMap.empty a
    val initialStrEnv = emptyStrEnv

    val boolType = LambdaExp.boolType
    val exnType = LambdaExp.exnType
    val tyvar_list = LambdaExp.fresh_eqtyvar()
    val listType = LambdaExp.CONStype([LambdaExp.TYVARtype tyvar_list], TyName.tyName_LIST)

    val initialVarEnv = 
      VARENV(initMap [(Ident.id_PRIM, PRIM),
		      (Ident.id_ABS, ABS),
		      (Ident.id_NEG, NEG),
		      (Ident.id_PLUS, PLUS),
		      (Ident.id_MINUS, MINUS),
		      (Ident.id_MUL, MUL),
		      (Ident.id_DIV, DIV),
		      (Ident.id_MOD, MOD),
		      (Ident.id_LESS, LESS),
		      (Ident.id_GREATER, GREATER),
		      (Ident.id_LESSEQ, LESSEQ),
		      (Ident.id_GREATEREQ, GREATEREQ),
                      (Ident.resetRegions, RESET_REGIONS),
                      (Ident.forceResetting, FORCE_RESET_REGIONS),
		      (Ident.id_REF, REF),
		      (Ident.id_TRUE, CON(Con.con_TRUE,[],boolType,[],[])),
		      (Ident.id_FALSE, CON(Con.con_FALSE,[],boolType,[],[])),
		      (Ident.id_NIL, CON(Con.con_NIL,[tyvar_list],listType,
					 [LambdaExp.TYVARtype tyvar_list],[0])),
		      (Ident.id_CONS, CON(Con.con_CONS,[tyvar_list],listType,
					  [LambdaExp.TYVARtype tyvar_list],[0])),
		      (Ident.id_Div, EXCON(Excon.ex_DIV, exnType)),
		      (Ident.id_Match, EXCON(Excon.ex_MATCH, exnType)),
		      (Ident.id_Bind, EXCON(Excon.ex_BIND, exnType)),
		      (Ident.id_Overflow, EXCON(Excon.ex_OVERFLOW, exnType))
		      ])

    local open TyCon TyName
    in val initialTyEnv = TYENV(initMap [(tycon_INT, ([tyName_INT], emptyCEnv)),
					 (tycon_WORD, ([tyName_INT], emptyCEnv)),
					 (tycon_WORD8, ([tyName_INT], emptyCEnv)),
					 (tycon_REAL, ([tyName_REAL], emptyCEnv)),
					 (tycon_STRING, ([tyName_STRING], emptyCEnv)),
					 (tycon_CHAR, ([tyName_INT], emptyCEnv)),
					 (tycon_EXN, ([tyName_EXN], emptyCEnv)),
					 (tycon_REF, ([tyName_REF], emptyCEnv)),
					 (tycon_BOOL, ([tyName_BOOL], emptyCEnv)),
					 (tycon_LIST, ([tyName_LIST], emptyCEnv)),
					 (tycon_WORD_TABLE, ([tyName_WORD_TABLE], emptyCEnv)),
					 (tycon_UNIT, ([], emptyCEnv))
					 ])
    end

    val initialCEnv = CENV{StrEnv=initialStrEnv,
			   VarEnv=initialVarEnv,
			   TyEnv=initialTyEnv}

    fun declareVar(id, (lv, tyvars, tau), CENV{StrEnv,VarEnv=VARENV map,TyEnv}) =
      let val il0 = List.map LambdaExp.TYVARtype tyvars
      in CENV{StrEnv=StrEnv, TyEnv=TyEnv,
	      VarEnv=VARENV (FinMap.add(id, LVAR (lv,tyvars,tau,il0), map))}
      end

    fun declareCon(id, (con,tyvars,tau,it), CENV{StrEnv,VarEnv=VARENV map,TyEnv}) =
      let val il0 = List.map LambdaExp.TYVARtype tyvars
      in CENV{StrEnv=StrEnv, TyEnv=TyEnv,
	      VarEnv=VARENV(FinMap.add(id,CON (con,tyvars,tau,il0,it), map))}
      end

    fun declareExcon(id, excon, CENV{StrEnv,VarEnv=VARENV map,TyEnv}) =
      CENV{StrEnv=StrEnv,VarEnv=VARENV(FinMap.add(id,EXCON excon,map)),TyEnv=TyEnv}

    fun declare_strid(strid, env, CENV{StrEnv=STRENV m,VarEnv,TyEnv}) =
      CENV{StrEnv=STRENV(FinMap.add(strid,env,m)),VarEnv=VarEnv,TyEnv=TyEnv}

    fun declare_tycon(tycon, a, CENV{StrEnv,VarEnv,TyEnv=TYENV m}) =
      CENV{StrEnv=StrEnv,VarEnv=VarEnv,TyEnv=TYENV(FinMap.add(tycon,a,m))}

    fun plus (CENV{StrEnv,VarEnv,TyEnv}, CENV{StrEnv=StrEnv',VarEnv=VarEnv',TyEnv=TyEnv'}) =
      CENV{StrEnv=plusStrEnv(StrEnv,StrEnv'),
	   VarEnv=plusVarEnv(VarEnv,VarEnv'),
	   TyEnv=plusTyEnv(TyEnv,TyEnv')}

    and plusStrEnv    (STRENV m1,STRENV m2)       = STRENV (FinMap.plus(m1,m2))
    and plusVarEnv    (VARENV m1,VARENV m2)       = VARENV (FinMap.plus(m1,m2))
    and plusTyEnv     (TYENV m1,TYENV m2)         = TYENV (FinMap.plus(m1,m2))

    exception LOOKUP_ID
    fun lookupId (CENV{VarEnv=VARENV m,...}) id =
      case FinMap.lookup m id
	of SOME res => res
	 | NONE => raise LOOKUP_ID

    fun lookup_strid (CENV{StrEnv=STRENV m,...}) strid =
      case FinMap.lookup m strid
	of SOME res => res
	 | NONE => die ("lookup_strid(" ^ StrId.pr_StrId strid ^ ")")

    fun lookup_longid CEnv longid =
      let fun lookup CEnv ([],id) = lookupId CEnv id
	    | lookup CEnv (strid::strids,id) =
	          lookup (lookup_strid CEnv strid) (strids,id) 
      in SOME(lookup CEnv (Ident.decompose longid))
         handle _ => NONE
      end

    fun lookup_longstrid ce longstrid =
      let val (strids,strid) = StrId.explode_longstrid longstrid
	  fun lookup (ce, []) = lookup_strid ce strid
	    | lookup (ce, strid::strids) = lookup(lookup_strid ce strid, strids)
      in lookup(ce, strids)
      end

    fun lookup_tycon (CENV{TyEnv=TYENV m, ...}) tycon =
      case FinMap.lookup m tycon
	of SOME res => res
	 | NONE => die ("lookup_tycon(" ^ TyCon.pr_TyCon tycon ^ ")")

    fun lookup_longtycon ce longtycon =
      let val (strids,tycon) = TyCon.explode_LongTyCon longtycon
	  fun lookup (ce, []) = lookup_tycon ce tycon
	    | lookup (ce, strid::strids) = lookup(lookup_strid ce strid, strids)
      in lookup(ce, strids)
      end

 
    fun lvars_result (LVAR (lv,_,_,_), lvs) = lv :: lvs
      | lvars_result (_, lvs) = lvs
    fun primlvars_result (result, lvs) =
      case result
	of ABS => Lvars.absint_lvar :: Lvars.absfloat_lvar :: lvs
	 | NEG => Lvars.negint_lvar :: Lvars.negfloat_lvar :: lvs
	 | PLUS => Lvars.plus_int_lvar :: Lvars.plus_float_lvar :: lvs
	 | MINUS => Lvars.minus_int_lvar :: Lvars.minus_float_lvar :: lvs
	 | MUL => Lvars.mul_int_lvar :: Lvars.mul_float_lvar :: lvs
	 | LESS => Lvars.less_int_lvar :: Lvars.less_float_lvar :: lvs
	 | GREATER => Lvars.greater_int_lvar :: Lvars.greater_float_lvar :: lvs
	 | LESSEQ => Lvars.lesseq_int_lvar :: Lvars.lesseq_float_lvar :: lvs
	 | GREATEREQ => Lvars.greatereq_int_lvar :: Lvars.greatereq_float_lvar :: lvs
	 | _ => lvs
    fun cons_result (CON (c,_,_,_,_), cs) = c :: cs
      | cons_result (_, cs) = cs
    fun excons_result (EXCON (c,_), cs) = c :: cs
      | excons_result (_, cs) = cs

    fun tynames_tau (LambdaExp.CONStype(taus,t), tns) = tynames_taus(taus,t::tns)
      | tynames_tau (LambdaExp.ARROWtype(taus1,taus2),tns) = tynames_taus(taus1,tynames_taus(taus2,tns))
      | tynames_tau (LambdaExp.RECORDtype(taus), tns) = tynames_taus(taus,tns)
      | tynames_tau (LambdaExp.TYVARtype _, tns) = tns
    and tynames_taus ([],tns) = tns
      | tynames_taus (tau::taus,tns) = tynames_tau(tau,tynames_taus(taus,tns))

    fun tynames_result (LVAR (_,_,tau,il), tns) : TyName list = tynames_taus(il,tynames_tau(tau,tns))
      | tynames_result (CON(_,_,tau,il,_), tns) = tynames_taus(il,tynames_tau(tau,tns))
      | tynames_result (EXCON(_,tau), tns) = tynames_tau(tau,tns)
      | tynames_result (REF, tns) = TyName.tyName_REF :: tns
      | tynames_result (_, tns) = tns

    fun varsOfCEnv (vars_result : result * 'a list -> 'a list) ce : 'a list =
      let fun vars_ce (CENV{VarEnv=VARENV m,StrEnv,...}, vars) =
	    FinMap.fold vars_result (vars_se (StrEnv,vars)) m
	  and vars_se (STRENV m, vars) = FinMap.fold vars_ce vars m
      in vars_ce (ce, [])
      end

    val lvarsOfCEnv = varsOfCEnv lvars_result
    val consOfCEnv = varsOfCEnv cons_result
    val exconsOfCEnv = varsOfCEnv excons_result
    val primlvarsOfCEnv = varsOfCEnv primlvars_result 

    fun tynamesOfCEnv ce : TyName list =
      let fun tynames_TEentry((tns,ce),acc) = tynames_E(ce,tns@acc) 
          and tynames_TE(TYENV m, acc) = FinMap.fold tynames_TEentry acc m 
          and tynames_E(CENV{VarEnv=VARENV ve, StrEnv, TyEnv, ...}, acc) =
	    let val acc = tynames_SE (StrEnv,acc)
	        val acc = tynames_TE (TyEnv,acc)
	    in FinMap.fold tynames_result acc ve
	    end
	  and tynames_SE(STRENV m, acc) = FinMap.fold tynames_E acc m 
      in (TyName.Set.list o TyName.Set.fromList) (tynames_E(ce,[]))
      end

   fun mk_it tyvars tyvars0 =
     let  fun index _ _ [] = die "index"
	    | index n x' (x::xs) = if x=x' then n
				   else index (n+1) x' xs
          fun f [] a = rev a
	    | f (tv0::tvs0) a = f tvs0 (index 0 tv0 tyvars :: a)
     in f tyvars0 []
     end

   fun apply_it(it,types) =
     let fun sel 0 (x::xs) = x
	   | sel n (x::xs) = sel (n-1) xs
	   | sel _ _ = die "apply_it"
         fun f [] a = rev a
	   | f (n::ns) a = f ns (sel n types :: a)
     in f it []
     end


   (* -------------
    * Restriction
    * ------------- *)

   fun restrictFinMap(error_str, env : (''a,'b) FinMap.map, dom : ''a list) =
     foldl (fn (id, acc) =>
	    let val res = case FinMap.lookup env id
			    of SOME res => res
			     | NONE => die error_str
	    in FinMap.add(id,res,acc)
	    end) FinMap.empty dom

   fun restrictVarEnv(VARENV m, ids) = 
     VARENV(restrictFinMap("restrictCEnv.id not in env", m, ids))

   fun restrictTyEnv(TYENV m, tycons) =
     TYENV(restrictFinMap("restrictCEnv.tycon not in env", m, tycons))

   fun restrictStrEnv(STRENV m, strid_restrs) =
     STRENV(foldl (fn ((strid,restr:Environments.restricter), acc) =>
		   let val res = case FinMap.lookup m strid
				   of SOME res => restrictCEnv(res,restr)
				    | NONE => die "restrictStrEnv.strid not in env"
		   in FinMap.add(strid,res,acc)
		   end) FinMap.empty strid_restrs)

   and restrictCEnv(ce,Environments.Whole) = ce
     | restrictCEnv(CENV{StrEnv,VarEnv,TyEnv}, Environments.Restr{strids,vids,tycons}) =
     CENV{StrEnv=restrictStrEnv(StrEnv,strids),
	  VarEnv=restrictVarEnv(VarEnv,vids),
	  TyEnv=restrictTyEnv(TyEnv,tycons)}

   val restrictCEnv = fn (ce, longids) => restrictCEnv(ce, Environments.create_restricter longids)
     

   (* -------------
    * Enrichment
    * ------------- *)

   local

    val debug_man_enrich = ref false
    val _ = Flags.add_flag_to_menu (["Debug Kit", "Manager"], 
				    "debug_man_enrich", "debug man enrich",
				    debug_man_enrich)

     fun log s = TextIO.output(TextIO.stdOut,s)
     fun debug(s, b) = if !debug_man_enrich then
                         (if b then log("\n" ^ s ^ ": enrich succeeded.")
			  else log("\n" ^ s ^ ": enrich failed."); b)
		       else b


     fun eq_res (LVAR (lv1,tvs1,tau1,il1), LVAR (lv2,tvs2,tau2,il2)) = 
       Lvars.eq(lv1,lv2) andalso
       LambdaBasics.eq_sigma_with_il((tvs1,tau1,il1),(tvs2,tau2,il2))
       | eq_res (CON(con1,tvs1,tau1,il1,it1), CON(con2,tvs2,tau2,il2,it2)) =
       Con.eq(con1, con2) andalso it1 = it2 andalso
       LambdaBasics.eq_sigma_with_il((tvs1,tau1,il1),(tvs2,tau2,il2))
       | eq_res (REF, REF) = true
       | eq_res (EXCON (excon1,tau1), EXCON (excon2,tau2)) = 
       Excon.eq(excon1,excon2) andalso LambdaBasics.eq_Type(tau1,tau2)
       | eq_res (ABS,ABS) = true
       | eq_res (NEG,NEG) = true
       | eq_res (PLUS,PLUS) = true
       | eq_res (MINUS,MINUS) = true
       | eq_res (MUL,MUL) = true
       | eq_res (DIV,DIV) = true
       | eq_res (MOD,MOD) = true
       | eq_res (LESS,LESS) = true
       | eq_res (GREATER,GREATER) = true
       | eq_res (LESSEQ,LESSEQ) = true
       | eq_res (GREATEREQ,GREATEREQ) = true
       | eq_res (RESET_REGIONS,RESET_REGIONS) = true
       | eq_res (FORCE_RESET_REGIONS,FORCE_RESET_REGIONS) = true
       | eq_res (PRIM,PRIM) = true
       | eq_res _ = false
       
     fun enrichVarEnv(VARENV env1,VARENV env2) =
       FinMap.Fold (fn ((id2,res2),b) => b andalso
		    case FinMap.lookup env1 id2
		      of SOME res1 => eq_res(res1,res2)
		       | NONE => false) true env2

     fun eq_tynames(res1,res2) = TyName.Set.eq (TyName.Set.fromList res1) (TyName.Set.fromList res2)
       
     fun enrichTyEnv(TYENV m1,TYENV m2) =
       FinMap.Fold (fn ((id2,(res2,ce2)),b) => b andalso
		    case FinMap.lookup m1 id2
		      of SOME (res1,ce1) => eq_tynames(res1,res2) andalso eqCEnv(ce1,ce2)
		       | NONE => false) true m2
       
     and enrichCEnv(CENV{StrEnv,VarEnv,TyEnv},
		    CENV{StrEnv=StrEnv',VarEnv=VarEnv',TyEnv=TyEnv'}) =
       debug("StrEnv", enrichStrEnv(StrEnv,StrEnv')) andalso 
       debug("VarEnv", enrichVarEnv(VarEnv,VarEnv')) andalso
       debug("TyEnv", enrichTyEnv(TyEnv,TyEnv'))

     and eqCEnv(ce1,ce2) = enrichCEnv(ce1,ce2) andalso enrichCEnv(ce2,ce1)

     and enrichStrEnv(STRENV se1, STRENV se2) =
       FinMap.Fold (fn ((strid,env2),b) => b andalso
		    case FinMap.lookup se1 strid
		      of SOME env1 => enrichCEnv(env1,env2)
		       | NONE => false) true se2
   in

     val enrichCEnv = enrichCEnv

   end
       

   (* -------------
    * Matching
    * ------------- *)

   local  
     fun matchRes (LVAR (lv,_,_,_), LVAR (lv0,_,_,_)) = Lvars.match(lv,lv0)
       | matchRes (CON(con,_,_,_,it), CON(con0,_,_,_,it0)) = if it = it0 then Con.match(con,con0) else ()
       | matchRes (EXCON (excon,_), EXCON (excon0,_)) = Excon.match(excon,excon0)
       | matchRes _ = ()

     fun matchVarEnv(VARENV env, VARENV env0) =
       FinMap.Fold(fn ((id,res),_) =>
		   case FinMap.lookup env0 id
		     of SOME res0 => matchRes(res,res0)
		      | NONE => ()) () env 

     fun matchEnv(CENV{StrEnv,VarEnv, ...},
		  CENV{StrEnv=StrEnv0,VarEnv=VarEnv0, ...}) =
       (matchStrEnv(StrEnv,StrEnv0); matchVarEnv(VarEnv,VarEnv0))

     and matchStrEnv(STRENV se, STRENV se0) =
       FinMap.Fold(fn ((strid,env),_) =>
		   case FinMap.lookup se0 strid
		     of SOME env0 => matchEnv(env,env0)
		      | NONE => ()) () se
   in

     val match = matchEnv

   end

   type TypeScheme = Environments.TypeScheme
   type ElabEnv = Environments.Env

   val compileTypeScheme_knot: (TypeScheme -> tyvar list * Type) option ref = ref NONE   (* MEGA HACK *)
   fun set_compileTypeScheme c = compileTypeScheme_knot := (SOME c)

   val normalize_sigma_knot: (tyvar list * Type -> tyvar list * Type) option ref = ref NONE   (* MEGA HACK *)
   fun set_normalize_sigma c = normalize_sigma_knot := (SOME c)

   fun constrain (ce: CEnv, elabE : ElabEnv) =
     let open Environments
         val compileTypeScheme = case compileTypeScheme_knot 
				   of ref (SOME compileTypeScheme) => compileTypeScheme
				    | ref NONE => die "compileTypeScheme_knot not set" 
         val normalize_sigma = case normalize_sigma_knot
				   of ref (SOME f) =>f
				    | ref NONE => die "normalize_sigma_knot not set" 
         fun constr_ran (tr, er) =
	   case tr
	     of LVAR(lv,tvs,tau,il) =>
	       (case er
		  of VE.LONGVAR sigma => 
		    let val (tvs',tau') = compileTypeScheme sigma
		        val S = LambdaBasics.match_sigma((tvs,tau),tau')
			  handle X => (print ("\nMatch failed for var matching var " ^ Lvars.pr_lvar lv ^ "\n");
				       print "Type scheme in translation env:\n";
				       pr_st (layout_scheme(tvs,tau));
				       print "\nType scheme in signature:\n";
				       pr_st (layout_scheme(tvs',tau'));
				       raise X)
			val il' = map (LambdaBasics.on_Type S) il
		    in LVAR(lv,tvs',tau',il')
		    end
		   | _ => die "constr_ran.LVAR.longvar expected") 
	      | CON(con,tvs,tau,il,it) =>
	       (case er
		  of VE.LONGVAR sigma =>
		    let val (tvs',tau') = compileTypeScheme sigma
		        val S = LambdaBasics.match_sigma((tvs,tau),tau')
			  handle X => (print ("\nMatch failed for var matching con " ^ Con.pr_con con ^ "\n");
				       raise X)			
			val il' = map (LambdaBasics.on_Type S) il
		    in CON(con,tvs',tau',il',it)
		    end
		   | VE.LONGCON sigma =>
		    let val (tvs',tau') = compileTypeScheme sigma
                        (* the bound variables tvs' come in random order: 
                           normalize it along tvs: *)
                        val (tvs',tau') = normalize_sigma(tvs,tau')
		        val S = LambdaBasics.match_sigma((tvs,tau),tau')
			  handle X => (print ("\nMatch failed for con matching con " ^ Con.pr_con con ^ "\n");
				       raise X)			
			val il' = map (LambdaBasics.on_Type S) il
		    in if LambdaBasics.eq_sigma((tvs,tau),(tvs',tau')) then CON(con,tvs',tau',il',it)
		       else (print "\nconstr_ran.CON.type schemes should be equal.\n";
                             print "Elaboration environment:\n\n";
                             pr_st (Environments.E.layout elabE);
                             print ("constructor: " ^ Con.pr_con con ^ "\n");
                             print ("sigma1  = ");
                             pr_st (layout_scheme(tvs,tau)); print "\n";
                             print ("sigma2  = ");
                             pr_st (layout_scheme(tvs',tau')); print "\n";
                             die  ("constr_ran.CON.type schemes should be equal")
                            )
		    end
		   | _ => die "constr_ran.CON.longvar or longcon expected")
	      | EXCON(excon,tau) =>
	       (case er
		  of VE.LONGVAR sigma =>
		    let val (tvs',tau') = compileTypeScheme sigma
		    in if tvs' = [] andalso LambdaBasics.eq_Type(tau,tau') then EXCON(excon,tau)
		       else die "constr_ran.EXCON.LONGVAR"
		    end
		   | VE.LONGEXCON _ => EXCON(excon,tau)  (* we could check equality of types *)
		   | _ => die "constr_ran.EXCON.longvar or longexcon expected")
	      | _ => die "constr_ran.expecting LVAR, CON or EXCON"

         fun constr_ce(CENV{StrEnv, VarEnv, TyEnv}, elabE) =
	   let val (elabSE, elabTE, elabVE) = E.un elabE
	   in CENV{StrEnv=constr_se(StrEnv,elabSE), VarEnv=constr_ve(VarEnv,elabVE),
		   TyEnv=constr_te(TyEnv,elabTE)}
	   end

	 and constr_se(STRENV se, elabSE) =
	   STRENV(SE.Fold (fn (strid, elabE) => fn se' =>
			   case FinMap.lookup se strid
			     of SOME ce => let val ce' = constr_ce(ce,elabE)
					   in FinMap.add(strid,ce',se')
					   end
			      | NONE => die "constr_se") FinMap.empty elabSE)
		  
	 and constr_ve(VARENV ve, elabVE) =
	   VARENV(VE.Fold (fn (id, elabRan) => fn ve' =>
			   case FinMap.lookup ve id
			     of SOME transRan => let val transRan' = constr_ran(transRan, elabRan)
						 in FinMap.add(id,transRan', ve')
						 end
			      | NONE => die "constr_ve") FinMap.empty elabVE)

	 and constr_te(TYENV te, elabTE) =
	   TYENV(TE.Fold(fn (tycon, _) => fn te' =>
			 case FinMap.lookup te tycon
			   of SOME tynames => FinMap.add(tycon,tynames,te')
			    | NONE => die "constr_te") FinMap.empty elabTE) 
(*	 val _ = print "\n[Constraining ...\n" *)
	 val res = constr_ce(ce, elabE)
(*	 val _ = print " Done]\n" *)
     in res
     end


   type StringTree = FinMap.StringTree

    fun layoutCEnv (CENV{StrEnv,VarEnv,TyEnv}) =
      PP.NODE{start="CENV(",finish=")",indent=2,
	      children=[layoutStrEnv StrEnv,
			layoutVarEnv VarEnv,
			layoutTyEnv TyEnv],
	      childsep=PP.RIGHT ","}

    and layoutStrEnv (STRENV m) =
      PP.NODE{start="StrEnv = ",finish="",indent=2,
	      children= [FinMap.layoutMap {start="{", eq=" -> ", sep=", ", finish="}"}
			 (PP.layoutAtom StrId.pr_StrId)
			 (layoutCEnv) m],
	      childsep=PP.RIGHT ","}

    and layoutVarEnv (VARENV m) =
      PP.NODE{start="VarEnv = ",finish="",indent=2,
	      children= [FinMap.layoutMap {start="{", eq=" -> ", sep=", ", finish="}"}
			               (PP.layoutAtom Ident.pr_id)
				       (PP.layoutAtom 
					(fn LVAR (lv,_,_,_) => "LVAR(" ^ Lvars.pr_lvar lv ^ ")"
                                          | RESET_REGIONS => Ident.pr_id Ident.resetRegions
                                          | FORCE_RESET_REGIONS => Ident.pr_id Ident.forceResetting
					  | PRIM => "PRIM"
					  | ABS => "ABS"
					  | NEG => "NEG"
					  | PLUS => "PLUS"
					  | MINUS => "MINUS"
					  | MUL => "MUL"
					  | DIV => "DIV"
					  | MOD => "MOD"
					  | LESS => "LESS"
					  | GREATER => "GREATER"
					  | LESSEQ => "LESSEQ"
					  | GREATEREQ => "GREATEREQ"
					  | REF => "REF" 
					  | CON(con,_,_,_,it) => "CON(" ^ Con.pr_con con ^ ")"
					  | EXCON (excon,_) => "EXCON(" ^ Excon.pr_excon excon ^ ")"))
				       m],
	      childsep=PP.NOSEP}

    and layoutTyEnv (TYENV m) = 
      let fun layout_res (tynames,ce) = 
	    PP.NODE {start="([",finish="], ce)",indent=0, children=map TyName.layout tynames,
		     childsep=PP.RIGHT ","}
      in FinMap.layoutMap {start="TyEnv = {", eq=" -> ", sep = ", ", finish="}"} (PP.LEAF o TyCon.pr_TyCon)
	 layout_res m
      end

  end;

