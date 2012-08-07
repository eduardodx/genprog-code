open Batteries
open Set
open Ref
open Map
open Utils
open Cil

let printer = Cilprinter.noLineCilPrinter

let stmt_str stmt = Pretty.sprint ~width:80 (printStmt printer () stmt) 
let exp_str exp = Pretty.sprint ~width:80 (printExp printer () exp) 

module OrderedExp = struct
  type t = Cil.exp
  let compare e1 e2 = 
    let e1' = exp_str e1 in
    let e2' = exp_str e2 in
      compare e1' e2'
end

module OrderedStmt = struct
  type t =  int * string * Cil.stmt
  let compare (i1,_,_) (i2,_,_) = compare i1 i2
end
                                                         

module ExpSet = Set.Make(OrderedExp)
module StmtMap = Map.Make(OrderedStmt)
module StmtSet = Set.Make(OrderedStmt)


module OrderedExpSet =
  struct
    type t = ExpSet.t
    let compare e1 e2 = 
      if ExpSet.subset e1 e2 &&
        ExpSet.subset e2 e1 then 0 else
      compare (ExpSet.cardinal e1) (ExpSet.cardinal e2)
end

module ExpSetSet = Set.Make(OrderedExpSet)

module OrderedStmtPair = struct
  type t = Cil.stmt * Cil.stmt
  let compare (s11,s12) (s21,s22) = 
    let s11' = stmt_str s11 in
    let s21' = stmt_str s21 in
      if s11' = s21' then begin
        let s12' = stmt_str s12 in
        let s22' = stmt_str s22 in
          compare s12' s22'
      end else compare s11' s21'
end


module OrderedStringPair = struct
  type t = string * string
  let compare (s11,s12) (s21,s22) = 
    if s11 = s21 then
      compare s12 s22
    else compare s11 s21
end

module StmtPairSet = Set.Make(OrderedStmtPair)
module StringPairSet = Set.Make(OrderedStringPair)

type predicate = Cil.exp
type predicates = ExpSet.t
(* stmt_node: stmt and its typelabel *)
type stmt_node = int * Cil.stmt

type change_node =
    {
      change_id : int;
      file_name : string;
      function_name : string;
      add : stmt_node list;
      delete : stmt_node list;
      guards : predicates ;
    }

let rec change_node_str node =
  let str1 = 
    if not (ExpSet.is_empty node.guards) then begin
      "IF "^
      (ExpSet.fold (fun exp accum -> Printf.sprintf "%s%s &&\n" accum (exp_str exp)) node.guards "")
    end
    else "ALWAYS\n"
  in
  let str2 =
    if not (List.is_empty node.add) then
      lfoldl (fun accum (_,stmt) -> Printf.sprintf "%sINSERT %s\n" accum (stmt_str stmt)) "" node.add
    else "INSERT NOTHING\n"
  in
  let str3 = 
    if not (List.is_empty node.delete) then
      lfoldl (fun accum (_,stmt) -> Printf.sprintf "%sDELETE %s\n" accum (stmt_str stmt)) "" node.delete
    else "DELETE NOTHING\n"
  in
    str1^str2^str3

let typelabel_ht = Hashtbl.create 255 
let inv_typelabel_ht = Hashtbl.create 255 
let typelabel_counter = ref 0 
let dummyBlock = { battrs = [] ; bstmts = [] ; }  
let dummyLoc = { line = 0 ; file = "" ; byte = 0; } 

let stmt_to_typelabel (s : Cil.stmt) = 
  let convert_label l = match l with
    | Label(s,loc,b) -> Label(s,dummyLoc,b) 
    | Case(e,loc) -> Case(e,dummyLoc)
    | Default(loc) -> Default(dummyLoc)
  in 
  let labels = List.map convert_label s.labels in
  let convert_il il = 
    List.map (fun i -> match i with
    | Set(lv,e,loc) -> Set(lv,e,dummyLoc)
    | Call(None,Lval(Var(vi),o),el,loc) when vi.vname = "log_error_write" -> 
	  Call(None,Lval(Var(vi),o),[],dummyLoc) 
    | Call(lvo,e,el,loc) -> Call(lvo,e,el,dummyLoc) 
    | Asm(a,b,c,d,e,loc) -> Asm(a,b,c,d,e,dummyLoc)
    ) il 
  in
  let skind = match s.skind with
    | Instr(il)  -> Instr(convert_il il) 
    | Return(eo,l) -> Return(eo,dummyLoc) 
    | Goto(sr,l) -> Goto(sr,dummyLoc) 
    | Break(l) -> Break(dummyLoc) 
    | Continue(l) -> Continue(dummyLoc) 
    | If(e,b1,b2,l) -> If(e,dummyBlock,dummyBlock,l)
    | Switch(e,b,sl,l) -> Switch(e,dummyBlock,[],l) 
    | Loop(b,l,so1,so2) -> Loop(dummyBlock,l,None,None) 
    | Block(block) -> Block(dummyBlock) 
    | TryFinally(b1,b2,l) -> TryFinally(dummyBlock,dummyBlock,dummyLoc) 
    | TryExcept(b1,(il,e),b2,l) ->
      TryExcept(dummyBlock,(convert_il il,e),dummyBlock,dummyLoc) 
  in
  let s' = { s with skind = skind ; labels = labels } in 
  let doc = dn_stmt () s' in 
  let str = Pretty.sprint ~width:80 doc in 
    if Hashtbl.mem typelabel_ht str then begin 
      Hashtbl.find typelabel_ht str 
    end else begin
      let res = !typelabel_counter in
        incr typelabel_counter ; 
        Hashtbl.add typelabel_ht str res ; 
        Hashtbl.add inv_typelabel_ht res str; 
        res 
    end 

let change_count = ref 0
let new_node fname funname add delete g = 
  let adds = lmap (fun stmt -> stmt_to_typelabel stmt, stmt) add in 
  let deletes = lmap (fun stmt -> stmt_to_typelabel stmt, stmt) delete in 
  { change_id = Ref.post_incr change_count; 
    file_name = fname;
    function_name = funname;
    add = adds; 
    delete=deletes;
    guards = g
  }
let change_ht = hcreate 10 

let store_change ((rev_num, msg, change) : (int * string * change_node)) : unit = 
  hadd change_ht change.change_id (rev_num,msg,change)

let get_change change_id = hfind change_ht change_id

type concrete_delta = change_node list 
    
type full_diff = {
  mutable fullid : int;
  rev_num : int;
  msg : string;
  changes : change_node list ; (* (string * (change_node list StringMap.t)) list ; functions to changes *)
  dbench : string
}

(* diff type and initialization *)

let diff_ht_counter = ref 0
let diffid = ref 0
let changeid = ref 0

let new_diff revnum msg changes benchmark = 
  {fullid = (post_incr diffid);rev_num=revnum;msg=msg; changes = changes; dbench = benchmark }
(*
let template_id = ref 0 
let new_template () = Ref.post_incr template_id

type template =
    { template_id : int ;
      diff : full_diff;
      change : change_node ;
      linestart : int ;
      lineend : int ;
      edits : change list ;
      names : StringSet.t ;
    }
*)


let alpha_ht = hcreate 10
let name_id = ref 0

class alphaRenameVisitor = object
  inherit nopCilVisitor

  method vinst i =
    match i with
      Call(l,e1,elist,l2) ->
        let this_instr = Pretty.sprint 
          ~width:80 
          (d_instr () i) in
        Printf.printf "this instruction is currently: {%s}\n" this_instr;
          let copy = copy e1 in
        ChangeDoChildrenPost([i], 
                             (fun i ->
                               match i with
                                 [Call(l,foo,elist,l2)] -> 
        let this_instr = Pretty.sprint 
          ~width:80 
          (d_instr () (Call(l,copy,elist,l2))) in
        Printf.printf "this instruction is currently: {%s}\n" this_instr;

[Call(l,copy,elist,l2)]
                               | _ -> i))
    | _ -> DoChildren

  method vvrbl varinfo = 
    let new_name = 
      ht_find alpha_ht varinfo.vname 
        (fun _ -> incr name_id; "___alpha"^(string_of_int !name_id)) in
      varinfo.vname <- new_name; SkipChildren
end
let my_alpha = new alphaRenameVisitor


let alpha_rename change =
  hclear alpha_ht ;
  let predicates = ExpSet.elements change.guards in 
  let predicates = lmap (fun exp -> visitCilExpr my_alpha exp) predicates in
  let adds = lmap (fun (n,stmt) -> n,visitCilStmt my_alpha stmt) change.add in
  let dels = lmap (fun (n,stmt) -> n,visitCilStmt my_alpha stmt) change.delete in
    {change with guards = (ExpSet.of_enum (List.enum predicates)); add = adds; delete = dels }
    
