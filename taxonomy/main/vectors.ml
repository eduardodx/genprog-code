open Batteries
open Set
open Utils
open Map
open Cabsvisit
open Cabswalker
open Difftypes
open Treediff
open Cfg
open Pdg
open Datapoint
module C=Cabs

let vector_hash = hcreate 10

let hfind ht key msg = ht_find ht key (fun _ -> failwith msg)

(* OK, what are the interesting nodes for cabs? *)
(* everything rooted at statement, including expressions?  I think so. *)

type tIndex = { 
  typedef : int;
  cv_const : int;
  cv_volatile : int;
  cv_restrict : int;
  attribute : int;
  no_storage : int;
  auto : int;
  static : int;
  extern : int;
  register : int;
  inline : int;
  pattern : int;
  tvoid : int;
  tchar : int;
  tshort : int;
  tint : int;
  tlong : int;
  tint64 : int;
  tfloat : int;
  tdouble : int;
  tsigned : int;
  tunsigned : int;
  tnamed : int;
  tsum : int;
  tstruct : int;
  tunion : int;
  tenum : int;
  ttypeof : int;
  exprop : int;
  typeop : int;
  
  (* decl_type type information *)
  parentype : int;
  arraytype : int;
  ptr : int;
  proto : int;
  
  (* general node type; primarily for changes *)
  expression : int;
  statement : int;
  definition : int;
  
  (* change vector info *)
  insertion : int;
  reorder : int;
  move : int;
  deletion : int;
  def_parent : int;
  stmt_parent : int;
  exp_parent : int;
  loop_guard : int;
  cond_guard : int;
  catch_guard : int;
  case_guard : int;
  
  (* statement vector info *)
  if_ind : int;
  loop : int;
  while_ind : int;
  dowhile_ind : int;
  for_ind : int;
  loop_mod : int;
  break : int;
  continue : int;
  return : int;
  switch : int;
  case : int;
  default : int;
  label : int;
  goto : int;
  asm : int;
  trystmt : int;
  except : int;
  finally : int;
  
  (* expression vector info *)
  unary : int;
  binary : int;
  bitwise : int;
  plus : int;
  minus : int;
  multiply : int;
  divide : int;
  modop : int;
  andop : int;
  orop : int;
  xorop : int;
  shift : int;
  left : int;
  right : int;
  assign : int;
  equal : int;
  notop : int;
  less_than : int;
  greater_than : int;
  addr : int;
  post : int;
  pre : int;
  incr : int;
  decr : int;
  question : int;
  cast : int;
  call : int;
  comma : int;
  constant : int;
  paren : int;
  variable : int;
  sizeof : int;
  alignof : int;
  index : int;
  memberof : int;
}

let i = 
  {
	  typedef=0;
      cv_const=1;
	  cv_volatile=2;
	  cv_restrict=3;
	  attribute=4;
      no_storage=5;
	  auto=6;
	  static=7;
	  extern=8;
	  register=9;
	  inline=10;
	  pattern=11;
      tvoid=12;
	  tchar=13;
	  tshort=14;
	  tint=15;
	  tlong=16;
	  tint64=17;
	  tfloat=18;
	  tdouble=19;
	  tsigned=20;
	  tunsigned=21;
	  tnamed=22;
	  tsum=23;
	  tstruct=24;
	  tunion=25;
	  tenum=26;
	  ttypeof=27;
	  exprop=28;
	  typeop=29;

(* decl_type type information *)
	  parentype=30;
	  arraytype=31;
	  ptr=32;
	  proto=33;

	  (* general node type; primarily for changes *)
	  expression=34;
	  statement=35;
	  definition=36;

	  (* change vector info *)
	  insertion=37;
	  reorder=38;
	  move=39;
	  deletion=40;
	  def_parent=41;
	  stmt_parent=42;
	  exp_parent=43;
	  loop_guard=44;
	  cond_guard=45;
	  case_guard=46;
	  catch_guard=47;

	  (* statement vector info *)
	  if_ind=48;
	  loop=49;
	  while_ind=50;
	  dowhile_ind=51;
	  for_ind=52;
	  loop_mod=53;
	  break=54;
	  continue=55;
	  return=56;
	  switch=57;
	  case=58;
	  default=59;
	  label=60;
	  goto=61;
	  asm=62;
	  trystmt=63;
	  except=64;
	  finally=65;

	  (* expression vector info *)
	  unary=66;
	  binary=67;
	  bitwise=68;
	  plus=69;
	  minus=70;
	  multiply=71;
	  divide=72;
	  modop=73;
	  andop=74;
	  orop=75;
	  xorop=76;
	  shift=77;
	  left=78;
	  right=79;
	  assign=80;
	  equal=81;
	  notop=82;
	  less_than=83;
	  greater_than=84;
	  addr=85;
	  post=86;
	  pre=87;
	  incr=88;
	  decr=89;
	  question=90;
	  cast=91;
	  call=92;
	  comma=93;
	  constant=94;
	  paren=95;
	  variable=96;
	  sizeof=97;
	  alignof=98;
	  index=99;
	  memberof=100;
}

let max_size = 101

(* we need to do everything in postorder *)
let array_incr array index =
  let currval = array.(index) in
	Array.set array index (currval + 1)
	     
let array_sum array1 array2 = (* for each i in array1, array1.(i) = array1.(i) + array2.(i) *)
  Array.iteri
	(fun index ->
	  fun val1 -> 
		Array.set array1 index (array1.(index) + array2.(index))) array1; array1
  
class vectorGenWalker = object(self)
  inherit [int Array.t ] singleCabsWalker

  method default_res () = Array.make max_size 0
  method combine array1 array2 = array_sum array1 array2
  method wDeclType dt = 
    let dt_array = Array.make max_size 0 in
    let incr = array_incr dt_array in 
      (match dt with
       | C.PARENTYPE _ -> incr i.parentype
       | C.ARRAY _ -> incr i.arraytype
       | C.PTR _ -> incr i.ptr
       | C.PROTO _ -> incr i.proto
       | _ -> ()); CombineChildren(dt_array)

  method wExpression exp =
    let exp_array = Array.make max_size 0 in
    let incr = array_incr exp_array in
      incr i.expression;
      (match C.dn exp with
       | C.UNARY(uop,exp1) -> 
	   incr i.unary;
	   (match uop with
	    | C.MINUS -> incr i.minus
	    | C.PLUS -> incr i.plus 
	    | C.NOT -> incr i.notop
	    | C.BNOT -> incr i.notop; incr i.bitwise
	    | C.MEMOF -> incr i.ptr 
	    | C.ADDROF -> incr i.addr
	    | C.PREINCR -> incr i.assign; incr i.pre; incr i.incr ; incr i.plus
	    | C.PREDECR -> incr i.assign; incr i.pre; incr i.decr ; incr i.minus
	    | C.POSINCR -> incr i.assign; incr i.post; incr i.incr; incr i.plus
	    | C.POSDECR -> incr i.assign; incr i.post; incr i.decr ; incr i.minus)
       | C.BINARY(bop,exp1,exp2) ->
	   incr i.binary;
	   (match bop with 
	    | C.ADD -> incr i.plus
	    | C.SUB -> incr i.minus
	    | C.MUL -> incr i.multiply
	    | C.DIV -> incr i.divide
	    | C.MOD -> incr i.modop
	    | C.AND -> incr i.andop
	    | C.OR -> incr i.orop
	    | C.BAND -> incr i.bitwise; incr i.andop
	    | C.BOR -> incr i.bitwise; incr i.orop
	    | C.XOR -> incr i.xorop
	    | C.SHL -> incr i.bitwise; incr i.shift; incr i.left
	    | C.SHR -> incr i.bitwise; incr i.shift; incr i.right
	    | C.EQ -> incr i.equal
	    | C.NE -> incr i.notop; incr i.equal
	    | C.LT -> incr i.less_than
	    | C.GT -> incr i.greater_than
	    | C.LE -> incr i.less_than; incr i.equal
	    | C.GE -> incr i.greater_than; incr i.equal
	    | C.ASSIGN -> incr i.assign 
	    | C.ADD_ASSIGN -> incr i.assign; incr i.plus
	    | C.SUB_ASSIGN -> incr i.assign; incr i.minus
	    | C.MUL_ASSIGN -> incr i.assign; incr i.multiply 
	    | C.DIV_ASSIGN -> incr i.assign; incr i.divide 
	    | C.MOD_ASSIGN -> incr i.assign; incr i.modop 
	    | C.BAND_ASSIGN -> incr i.bitwise; incr i.assign; incr i.andop
	    | C.BOR_ASSIGN -> incr i.bitwise; incr i.assign; incr i.orop
	    | C.XOR_ASSIGN -> incr i.bitwise; incr i.assign; incr i.xorop
	    | C.SHL_ASSIGN -> incr i.bitwise; incr i.assign; incr i.shift; incr i.left
	    | C.SHR_ASSIGN -> incr i.bitwise; incr i.assign; incr i.shift; incr i.right)
       | C.LABELADDR(str) -> incr i.addr; incr i.label
       | C.QUESTION(exp1,exp2,exp3) -> incr i.question
       | C.CAST((spec,dt),ie) -> incr i.cast
       | C.CALL(exp,elist) -> incr i.call
       | C.CONSTANT(const) -> incr i.constant
       | C.VARIABLE(str) -> incr i.variable
       | C.EXPR_SIZEOF(exp) -> incr i.sizeof; incr i.exprop
       | C.TYPE_SIZEOF(spec,dt) -> incr i.sizeof; incr i.typeop
       | C.EXPR_ALIGNOF(exp) -> incr i.alignof; incr i.exprop
       | C.TYPE_ALIGNOF(spec,dt) -> incr i.alignof; incr i.typeop
       | C.INDEX(e1,e2) -> incr i.index
       | C.MEMBEROF(exp,str) -> incr i.memberof
       | C.MEMBEROFPTR(exp,str) -> incr i.memberof; incr i.ptr
       | C.EXPR_PATTERN(str) -> incr i.variable; incr i.exprop; incr i.pattern;
       | _ -> ());
      CombineChildren(exp_array) 

  method wStatement stmt =
    if not (hmem vector_hash (IntSet.singleton (stmt.C.id))) then begin
      let stmt_array = Array.make max_size 0 in 
      let incr = array_incr stmt_array in
	incr i.statement;
	(match C.dn stmt with 
	 | C.IF _ -> incr i.if_ind
	 | C.WHILE _ -> incr i.loop; incr i.while_ind
	 | C.DOWHILE _ -> incr i.loop; incr i.dowhile_ind
	 | C.FOR _ -> incr i.loop; incr i.for_ind
	 | C.BREAK _ -> incr i.break; incr i.loop_mod
	 | C.CONTINUE _ -> incr i.continue; incr i.loop_mod
	 | C.RETURN _ -> incr i.return
	 | C.SWITCH _ -> incr i.switch
	 | C.CASE _ -> incr i.case; incr i.label
	 | C.CASERANGE _ -> incr i.case; incr i.label
	 | C.DEFAULT _ -> incr i.default; incr i.label
	 | C.LABEL _ -> incr i.label
	 | C.GOTO _ -> incr i.goto
	 | C.COMPGOTO _ -> incr i.goto; incr i.exprop
	 | C.ASM _ ->  incr i.asm
	 | C.TRY_EXCEPT _ -> incr i.trystmt; incr i.except
	 | C.TRY_FINALLY _ -> incr i.trystmt; incr i.except
	 | _ -> ()
	);
	ChildrenPost(fun child_arrays -> 
		       let stmt_array = array_sum stmt_array child_arrays in
			 hadd vector_hash (IntSet.singleton(stmt.C.id)) stmt_array;
			 (*						 pprintf "vector for stmt: %d --> %s: \n" stmt.C.id (Cfg.stmt_str stmt);
									 pprintf "%s\n" ("[" ^ (Array.fold_lefti (fun str -> fun index -> fun ele -> str ^ (Printf.sprintf "(%d:%d) " index ele)) "" stmt_array) ^ "]");
									 pprintf "\n";*)
			 stmt_array)
    end else Result(hfind vector_hash (IntSet.singleton(stmt.C.id)) "two")

  method wDefinition def = 
    let def_array = Array.make max_size 0 in
    let incr = array_incr def_array in 
      incr i.definition; 
      CombineChildren(def_array);

  method wTypeSpecifier ts = 
	let ts_array = Array.make max_size 0 in
	let incr = array_incr ts_array in
	  (match ts with 
		C.Tvoid -> incr i.tvoid
	  | C.Tchar -> incr i.tchar
	  | C.Tshort -> incr i.tshort
	  | C.Tint -> incr i.tint
	  | C.Tlong -> incr i.tlong
	  | C.Tint64 -> incr i.tint64
	  | C.Tfloat -> incr i.tfloat 
	  | C.Tdouble -> incr i.tdouble 
	  | C.Tsigned -> incr i.tsigned
	  | C.Tunsigned -> incr i.tunsigned
	  | C.Tnamed _ -> incr i.tnamed 
	  | C.Tstruct _ -> incr i.tsum; incr i.tstruct
	  | C.Tunion _ -> incr i.tsum; incr i.tunion
	  | C.Tenum _ -> incr i.tsum ; incr i.tenum
	  | C.TtypeofE _ -> incr i.ttypeof; incr i.exprop
	  | C.TtypeofT _ -> incr i.ttypeof; incr i.typeop); CombineChildren(ts_array)

  method wSpecElem se = 
	let se_array = Array.make max_size 0 in
	let incr = array_incr se_array in
	  (match se with
		C.SpecTypedef -> incr i.typedef
	  | C.SpecCV(C.CV_CONST) -> incr i.cv_const
	  | C.SpecCV(C.CV_VOLATILE) -> incr i.cv_volatile
	  | C.SpecCV(C.CV_RESTRICT) -> incr i.cv_restrict
	  | C.SpecStorage(C.NO_STORAGE) -> incr i.no_storage
	  | C.SpecStorage(C.AUTO) -> incr i.auto
	  | C.SpecStorage(C.STATIC) -> incr i.static
	  | C.SpecStorage(C.EXTERN) -> incr i.extern
	  | C.SpecStorage(C.REGISTER) -> incr i.register
	  | C.SpecInline -> incr i.inline
	  | C.SpecPattern _ -> incr i.pattern
	  | _ -> ()
	  ); CombineChildren(se_array)

  method wAttribute attr = 
	let attr_array = Array.make max_size 0 in
	  array_incr attr_array i.attribute;
	  CombineChildren(attr_array)
end


let rec process_nodes sets window emitted =
  let emit () = 
    let set,array =
      lfoldl
	(fun (sets,arrays) ->
	   fun (set,array) ->
	     IntSet.union sets set,array_sum arrays array) (IntSet.empty,Array.make max_size 0) window in
      hadd vector_hash set array; set,array
  in
    match sets with
      set :: sets ->
	let setstr = IntSet.fold ( fun d -> fun str -> str^(Printf.sprintf "%d," d)) set "" in
	let array = hfind vector_hash set ("set:"^setstr) in
	let emitted,window = 
	  if (llen window) == 5 then (emit()::emitted, List.tl window)
	  else emitted,window
	in
	  process_nodes sets ((set,array) :: window) emitted
    | _ -> if (llen window) == 5 then emit() :: emitted else emitted 
	
let rec full_merge sets =
  let processed = process_nodes sets [] [] in
  let sets,arrays = List.split processed in 
    if (llen processed) > 4 then arrays @ (full_merge sets)
    else arrays

let vector_gen = new vectorGenWalker

class mergeWalker = object(self)
  inherit [int Array.t list] singleCabsWalker

  method default_res () = []
  method combine one two = one @ two

  method wBlock block = 
    let stmts = lmap (fun stmt -> ignore(vector_gen#walkStatement stmt); IntSet.singleton stmt.C.id) block.C.bstmts in
      CombineChildren(full_merge stmts)

end

let merge_gen = new mergeWalker

let guard_array (guard,exp) = 
  let guard_array = Array.make max_size 0 in
  let incr = array_incr guard_array in
    (match guard with
     | LOOP -> incr i.loop_guard
     | EXPG -> incr i.cond_guard
     | CATCH -> incr i.catch_guard
     | CASEG -> incr i.case_guard
     | _ -> failwith "Unhandled lifted guard in guard_array");
    let exp_array = vector_gen#walkExpression exp in
    let guard_part = Array.sub guard_array i.loop_guard (i.case_guard - i.loop_guard -1) in
    let exp_part = Array.sub exp_array i.unary (i.memberof - i.unary - 1) in
      Array.append guard_part exp_part

let change_array (id,change) =
  let change_array = Array.make max_size 0 in
  let incr = array_incr change_array in
  let parent_type = function 
	| PTREE
    | PDEF -> i.def_parent
    | PSTMT -> i.stmt_parent
    | PEXP -> i.exp_parent
    | LOOPGUARD | FORINIT -> i.loop_guard
    | CONDGUARD -> i.cond_guard 
    | p -> failwith ("Unhandled parent type in change_vectors:"^(ptyp_str p))
  in
  let get_arrays func1 func2 ele =
    let ast_array = array_sum (Array.copy (func1 ele)) change_array in
    let arrays = 
      lmap (fun array -> array_sum (Array.copy array) change_array) (func2 ele)
    in
      ast_array :: arrays
  in
  let def_arrays def = 
    let def_vector = vector_gen#walkDefinition def in
      array_sum change_array def_vector
  in
  let stmt_arrays stmt =
    let stmt_vector = vector_gen#walkStatement stmt in
      array_sum change_array stmt_vector
  in
  let exp_arrays exp = 
    let exp_vector = vector_gen#walkExpression exp in
      array_sum change_array exp_vector
  in
	(* FIXME: maybe eliminate reorder in favor of Move? Or move with some
	   signifier of the level/how far to move? *)
  let res = 
    match change with 
    | InsertDefinition(def,_,_,par) ->
	incr i.insertion; incr (parent_type par); incr i.definition;
	def_arrays def
    | MoveDefinition(def,_,_,_,par1,par2) ->
	incr i.move; incr (parent_type par1); incr (parent_type par2); incr i.definition;
	def_arrays def
    | ReorderDefinition(def,_,_,_,par) ->
	def_arrays def
    | DeleteDef(def,_,_,ptyp) -> 
	incr i.deletion; incr i.definition; incr (parent_type ptyp); 
	def_arrays def
    | InsertStatement(stmt,_,_,par) ->
	incr i.insertion; incr (parent_type par); incr i.statement;
	stmt_arrays stmt
    | MoveStatement(stmt,_,_,_,par1,par2) ->
	incr i.move; incr (parent_type par1); incr (parent_type par2); incr i.statement;
	stmt_arrays stmt
    | ReorderStatement(stmt,_,_,_,par) ->
	incr i.reorder; incr (parent_type par); incr i.statement;
	stmt_arrays stmt
    | DeleteStmt(stmt,_,_,ptyp) -> 
	incr i.deletion; incr i.statement; incr (parent_type ptyp); 
	stmt_arrays stmt
    | InsertExpression(exp,_,_,par) ->
	incr i.insertion; incr (parent_type par); incr i.expression;
	exp_arrays exp
    | MoveExpression(exp,_,_,_,par1,par2) ->
	incr i.move; incr (parent_type par1); incr (parent_type par2); incr i.expression;
	exp_arrays exp
    | ReorderExpression(exp,_,_,_,par) ->
	incr i.reorder; incr (parent_type par); incr i.expression;
	exp_arrays exp
    | DeleteExp(exp,_,_,ptyp) -> 
	incr i.deletion; incr i.expression; incr (parent_type ptyp); 
	exp_arrays exp
    | _ -> failwith "Unhandled edit type in change_vectors"
  in
    res
(* a vector describing context can refer to:
   the entire AST of surrounding context.
   the characteristic vectors of the PDG of the entire AST of surrounding context
   the vectors of the syntax of the modification site
   the characteristic vectors of a subgraph in which a modification site is contained *)
(* what do the vectors match? From the paper, it's either (1) a complete AST
   subtree, (2) a sequence of contiguous statements, or (3) another semantic
   vector: a slice of another procedure *)

(* FIXME: we may need some inter-procedural analysis for when entire definitions are inserted *)

let rec array_merge arrays = 
  let rec inner_merge arrays = 
    match arrays with
    | [one;two;three;four;five] -> 
	let one' = Array.copy one in 
	let two' = Array.copy two in
	let three' = Array.copy three in 
	let four' = Array.copy four in 
	let new_vec = array_sum one' (array_sum two' (array_sum three' (array_sum four' five))) in
	  [new_vec],[]
    | one :: two :: three :: four :: five:: rest -> 
	let one' = Array.copy one in 
	let two' = Array.copy two in
	let three' = Array.copy three in 
	let four' = Array.copy four in 
	let new_vec = array_sum one' (array_sum two' (array_sum three' (array_sum four' five))) in
	let rest_merged,rest = inner_merge (two::three::four::five::rest) in
	  new_vec :: rest_merged, rest
    | rest -> [], rest
  in 
  let new_vecs,rest = inner_merge arrays in
    if (llen (new_vecs @ rest)) > 4 then
      arrays @ (array_merge (new_vecs @ rest))
    else arrays @ new_vecs


let mu (subgraph : Pdg.subgraph) = 
  (* this does both imaging and collection of vectors *)
  let cfg = lmap (fun p -> p.Pdg.cfg_node) subgraph in 
  let rec get_stmts = function 
    | BASIC_BLOCK (slist) -> lmap (fun stmt -> vector_gen#walkStatement stmt) slist
    | CONTROL_FLOW(_,exp) -> [vector_gen#walkExpression exp] 
    | REGION_NODE (cns) -> 
	lfoldl (fun lst -> fun (cn,_) -> lst @ get_stmts cn.cnode) [] cns
    | _ -> []
  in
  let all_vectors = 
    lfoldl
      (fun vecs ->
	 fun cn -> vecs @ (get_stmts cn.cnode)) [] cfg in
  let ret = array_merge all_vectors in
    ret
      
module ArraySet = Set.Make(struct
			     type t = int Array.t
			     let compare = Array.make_compare (Pervasives.compare)
			   end)
let uniq arrays = 
  let set = ArraySet.of_enum (List.enum arrays) in
    List.of_enum (ArraySet.enum set)


let rec collect_arrays fst lst1 =
  match lst1 with
	hd :: tl -> Array.append fst hd :: collect_arrays fst tl
  | [] -> []

let array_list vector = uniq (collect_arrays vector.VectPoint.change vector.VectPoint.mu)
  
let template_to_vectors template = 
  let stmt = match template.stmt with Some(stmt) -> stmt | None -> failwith "Impossible match" in
  let parent_vector1 = 
	vector_gen#walkStatement stmt in
  let parent_vector2 = 
	  merge_gen#walkStatement stmt in
  let parent_vectors : int Array.t list = uniq (parent_vector1 :: parent_vector2) in
  let edit_array : int Array.t = 
    lfoldl
      (fun array ->
	 fun edit ->
	 array_sum array (change_array edit)) 
      (Array.make max_size 0) template.edits in
  let guard_array : int Array.t = 
    lfoldl
      (fun array ->
	 fun guard ->
	 array_sum array (guard_array guard)) 
      (Array.make (i.memberof - i.unary - 1 + i.case_guard - i.loop_guard - 1) 0) (List.of_enum (GuardSet.enum template.guards)) in
  let pdg_subgraph_arrays : int Array.t list = mu template.subgraph in
  let vector = 
    { VectPoint.vid = VectPoint.new_id (); 
      VectPoint.template = template; 
      VectPoint.parent = parent_vectors; 
      VectPoint.guards = guard_array;
      VectPoint.change = edit_array;
      VectPoint.mu = uniq pdg_subgraph_arrays;
	  VectPoint.collected = []}
  in
  let collected = array_list vector in
	{vector with VectPoint.collected = collected }

let print_vectors fout vector =
  let print_vector vector =
    Array.iter (fun num -> output_string fout (Printf.sprintf "%d " num)) vector
  in
  let print_array_group group =
    output_string fout 
      (Printf.sprintf "# FILE:%s, TEMPLATEID:%d, REVNUM:%d, BENCH:%s, LINESTART:%d, LINEEND:%d, MSG:{%s}\n" 
		 vector.VectPoint.template.change.fname 
		 vector.VectPoint.template.template_id
		 vector.VectPoint.template.diff.rev_num
		 vector.VectPoint.template.diff.dbench
		 vector.VectPoint.template.linestart
		 vector.VectPoint.template.lineend
		 vector.VectPoint.template.diff.msg
      );
    print_vector group;
    output_string fout "\n"
  in
    liter print_array_group vector.VectPoint.collected;
    flush fout
